from datetime import datetime, timezone, timedelta
from app.extensions import db
from app.models.checkin import CheckIn, CheckInStatus
from app.models.user import User
from app.models.incident import Incident, IncidentStatus
from app.services.audit_service import AuditService


class CheckInService:
    LOCKOUT_THRESHOLD = 5
    LOCKOUT_COOLDOWN_MINUTES = 15

    @classmethod
    def _check_lockout_and_cooldown(cls, checkin: CheckIn, user_id: int, now: datetime) -> None:
        """
        Enforces 5-attempt brute-force protection and time-limited cooldown (15m).
        If cooldown has elapsed, resets attempt counter and restores verification access.
        """
        if checkin.is_pin_locked(now):
            locked_time = checkin.locked_until.replace(tzinfo=timezone.utc) if checkin.locked_until.tzinfo is None else checkin.locked_until
            remaining_seconds = max(1, int((locked_time - now).total_seconds()))
            remaining_minutes = (remaining_seconds + 59) // 60
            raise ValueError(
                f"Too many failed PIN attempts. Check-in locked for security. "
                f"Cooldown expires in {remaining_minutes} minute(s). "
                f"You can also unlock immediately using your account password."
            )

        if checkin.locked_until and now >= checkin.locked_until:
            # Cooldown window has elapsed; reset counter
            checkin.failed_pin_attempts = 0
            checkin.locked_until = None
            db.session.commit()
            AuditService.log_event(
                user_id=user_id,
                event_type='CHECKIN_LOCKOUT_COOLDOWN_EXPIRED',
                action_description=f"PIN lockout cooldown expired for check-in #{checkin.id}. Verification unlocked."
            )

    @staticmethod
    def schedule_checkin(user_id: int, data: dict) -> CheckIn:
        # Cancel any active scheduled check-ins first to avoid confusing overlaps
        active_existing = CheckIn.query.filter_by(user_id=user_id)\
            .filter(CheckIn.status.in_([CheckInStatus.SCHEDULED, CheckInStatus.IN_GRACE_PERIOD, CheckInStatus.OVERDUE_PRE_ALERT]))\
            .all()
        for c in active_existing:
            c.status = CheckInStatus.CANCELLED

        checkin = CheckIn(
            user_id=user_id,
            title=data.get('title', 'Routine Check-In'),
            destination_note=data.get('destination_note'),
            scheduled_for=data['scheduled_for'],
            grace_period_minutes=data.get('grace_period_minutes', 10),
            pre_alert_seconds=data.get('pre_alert_seconds', 20),
            status=CheckInStatus.SCHEDULED,
        )
        if data.get('safety_pin'):
            checkin.set_pin(data['safety_pin'])

        db.session.add(checkin)
        db.session.commit()

        AuditService.log_event(
            user_id=user_id,
            event_type='CHECKIN_SCHEDULED',
            action_description=f"Scheduled check-in '{checkin.title}' for {checkin.scheduled_for.isoformat()}"
        )
        return checkin

    @classmethod
    def confirm_checkin(cls, user_id: int, checkin_id: int, pin: str = None) -> CheckIn:
        checkin = CheckIn.query.filter_by(id=checkin_id, user_id=user_id).first()
        if not checkin:
            raise ValueError("Check-in record not found.")

        if checkin.status == CheckInStatus.SAFE_COMPLETED:
            return checkin  # Idempotent confirmation

        if checkin.status == CheckInStatus.CANCELLED:
            raise ValueError("Check-in has already been cancelled.")

        now = datetime.now(timezone.utc)
        cls._check_lockout_and_cooldown(checkin, user_id, now)

        if checkin.safety_pin_hash:
            if not pin or not checkin.verify_pin(pin):
                checkin.failed_pin_attempts = (checkin.failed_pin_attempts or 0) + 1
                if checkin.failed_pin_attempts >= cls.LOCKOUT_THRESHOLD:
                    checkin.locked_until = now + timedelta(minutes=cls.LOCKOUT_COOLDOWN_MINUTES)
                    db.session.commit()
                    AuditService.log_event(
                        user_id=user_id,
                        event_type='CHECKIN_PIN_LOCKED',
                        action_description=f"Security lockout: Check-in #{checkin.id} locked for {cls.LOCKOUT_COOLDOWN_MINUTES}m after {cls.LOCKOUT_THRESHOLD} failed attempts."
                    )
                    raise ValueError(
                        f"Too many failed PIN attempts. Check-in locked for security for {cls.LOCKOUT_COOLDOWN_MINUTES} minutes. "
                        f"You can unlock immediately using your account password."
                    )

                db.session.commit()
                AuditService.log_event(
                    user_id=user_id,
                    event_type='CHECKIN_PIN_FAILED',
                    action_description=f"Failed PIN attempt {checkin.failed_pin_attempts}/{cls.LOCKOUT_THRESHOLD} for check-in #{checkin.id}"
                )
                raise ValueError(f"Incorrect safety PIN. Attempt {checkin.failed_pin_attempts}/{cls.LOCKOUT_THRESHOLD}.")

        # Successful PIN verification resets failed count and locks
        checkin.failed_pin_attempts = 0
        checkin.locked_until = None
        checkin.status = CheckInStatus.SAFE_COMPLETED
        checkin.checked_in_at = now
        db.session.commit()

        AuditService.log_event(
            user_id=user_id,
            event_type='CHECKIN_CONFIRMED',
            action_description=f"User confirmed safe for check-in #{checkin.id} ('{checkin.title}')"
        )
        return checkin

    @classmethod
    def cancel_checkin(cls, user_id: int, checkin_id: int, pin: str = None) -> CheckIn:
        """
        Cancels a scheduled or active check-in timer with PIN authentication if configured.
        CRITICAL RACE SAFETY:
        If the check-in has already escalated to an active emergency incident on the backend,
        a late cancellation is strictly rejected to prevent silently erasing or falsely
        resolving active responder dispatches.
        """
        checkin = CheckIn.query.filter_by(id=checkin_id, user_id=user_id).first()
        if not checkin:
            raise ValueError("Check-in record not found.")

        if checkin.status == CheckInStatus.CANCELLED:
            return checkin  # Idempotent cancellation

        if checkin.status == CheckInStatus.SAFE_COMPLETED:
            raise ValueError("Cannot cancel a check-in that has already been confirmed safe.")

        if checkin.status == CheckInStatus.OVERDUE_ESCALATED:
            client_uuid = f"checkin_overdue_{checkin.id}_{user_id}"
            incident = Incident.query.filter_by(client_incident_uuid=client_uuid).first()
            if incident and incident.status == IncidentStatus.ACTIVE:
                raise ValueError(
                    f"Check-in #{checkin.id} has already escalated to active emergency incident #{incident.id}. "
                    "Emergency dispatches may have already been transmitted to responders. "
                    "You must cancel the emergency incident directly from the SOS screen."
                )

        now = datetime.now(timezone.utc)
        cls._check_lockout_and_cooldown(checkin, user_id, now)

        if checkin.safety_pin_hash:
            if not pin or not checkin.verify_pin(pin):
                checkin.failed_pin_attempts = (checkin.failed_pin_attempts or 0) + 1
                if checkin.failed_pin_attempts >= cls.LOCKOUT_THRESHOLD:
                    checkin.locked_until = now + timedelta(minutes=cls.LOCKOUT_COOLDOWN_MINUTES)
                    db.session.commit()
                    AuditService.log_event(
                        user_id=user_id,
                        event_type='CHECKIN_PIN_LOCKED',
                        action_description=f"Security lockout: Check-in #{checkin.id} locked for {cls.LOCKOUT_COOLDOWN_MINUTES}m after {cls.LOCKOUT_THRESHOLD} failed attempts during cancellation."
                    )
                    raise ValueError(
                        f"Too many failed PIN attempts. Check-in locked for security for {cls.LOCKOUT_COOLDOWN_MINUTES} minutes. "
                        f"You can unlock immediately using your account password."
                    )

                db.session.commit()
                AuditService.log_event(
                    user_id=user_id,
                    event_type='CHECKIN_PIN_FAILED',
                    action_description=f"Failed PIN attempt {checkin.failed_pin_attempts}/{cls.LOCKOUT_THRESHOLD} during cancellation of #{checkin.id}"
                )
                raise ValueError(f"Incorrect safety PIN. Attempt {checkin.failed_pin_attempts}/{cls.LOCKOUT_THRESHOLD}.")

        checkin.failed_pin_attempts = 0
        checkin.locked_until = None
        checkin.status = CheckInStatus.CANCELLED
        db.session.commit()

        AuditService.log_event(
            user_id=user_id,
            event_type='CHECKIN_CANCELLED',
            action_description=f"User cancelled check-in #{checkin.id} ('{checkin.title}')"
        )
        return checkin

    @classmethod
    def extend_checkin(cls, user_id: int, checkin_id: int, additional_minutes: int, pin: str = None) -> CheckIn:
        """Extends check-in scheduled deadline safely before or during grace period."""
        if additional_minutes <= 0 or additional_minutes > 1440:
            raise ValueError("Extension must be between 1 and 1440 minutes (24 hours).")

        checkin = CheckIn.query.filter_by(id=checkin_id, user_id=user_id).first()
        if not checkin:
            raise ValueError("Check-in record not found.")

        if checkin.status in [CheckInStatus.SAFE_COMPLETED, CheckInStatus.CANCELLED]:
            raise ValueError(f"Cannot extend check-in with terminal status '{checkin.status}'.")

        if checkin.status == CheckInStatus.OVERDUE_ESCALATED:
            raise ValueError(f"Cannot extend check-in #{checkin.id} because it has already escalated to an emergency incident.")

        now = datetime.now(timezone.utc)
        cls._check_lockout_and_cooldown(checkin, user_id, now)

        if checkin.safety_pin_hash and pin:
            if not checkin.verify_pin(pin):
                checkin.failed_pin_attempts = (checkin.failed_pin_attempts or 0) + 1
                if checkin.failed_pin_attempts >= cls.LOCKOUT_THRESHOLD:
                    checkin.locked_until = now + timedelta(minutes=cls.LOCKOUT_COOLDOWN_MINUTES)
                    db.session.commit()
                    raise ValueError(f"Too many failed PIN attempts. Check-in locked for {cls.LOCKOUT_COOLDOWN_MINUTES} minutes.")
                db.session.commit()
                raise ValueError(f"Incorrect safety PIN. Attempt {checkin.failed_pin_attempts}/{cls.LOCKOUT_THRESHOLD}.")

        # Extend scheduled timestamp
        checkin.scheduled_for = checkin.scheduled_for + timedelta(minutes=additional_minutes)
        # Recalculate status based on new extended schedule
        checkin.status = checkin.calculate_current_state()
        db.session.commit()

        AuditService.log_event(
            user_id=user_id,
            event_type='CHECKIN_EXTENDED',
            action_description=f"Check-in #{checkin.id} extended by {additional_minutes} mins to {checkin.scheduled_for.isoformat()}"
        )
        return checkin

    @classmethod
    def recover_lockout(cls, user_id: int, checkin_id: int, account_password: str) -> CheckIn:
        """
        Recovers a locked-out check-in using the user's primary account password.
        Guarantees brute-force recovery without bypassing ownership or authentication.
        """
        checkin = CheckIn.query.filter_by(id=checkin_id, user_id=user_id).first()
        if not checkin:
            raise ValueError("Check-in record not found.")

        user = db.session.get(User, user_id)
        if not user or not user.verify_password(account_password):
            AuditService.log_event(
                user_id=user_id,
                event_type='CHECKIN_RECOVERY_FAILED',
                action_description=f"Failed account password recovery attempt for locked check-in #{checkin.id}"
            )
            raise ValueError("Invalid account password. Lockout recovery rejected.")

        checkin.failed_pin_attempts = 0
        checkin.locked_until = None
        db.session.commit()

        AuditService.log_event(
            user_id=user_id,
            event_type='CHECKIN_LOCKOUT_RECOVERED',
            action_description=f"User recovered lockout for check-in #{checkin.id} using verified account password."
        )
        return checkin

    @staticmethod
    def get_active_checkin(user_id: int) -> tuple[CheckIn, str]:
        """Finds active check-in and computes its real-time evaluated status."""
        active = CheckIn.query.filter_by(user_id=user_id)\
            .filter(CheckIn.status.in_([
                CheckInStatus.SCHEDULED,
                CheckInStatus.IN_GRACE_PERIOD,
                CheckInStatus.OVERDUE_PRE_ALERT
            ]))\
            .order_by(CheckIn.scheduled_for.desc())\
            .first()

        if not active:
            return None, 'NONE'

        realtime_status = active.calculate_current_state()
        if realtime_status != active.status and active.status != CheckInStatus.SAFE_COMPLETED:
            active.status = realtime_status
            db.session.commit()

        return active, realtime_status
