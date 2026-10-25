from datetime import datetime, timezone, timedelta
from app.extensions import db
from app.utils.security import hash_pin, check_pin


class CheckInStatus:
    SCHEDULED = 'SCHEDULED'
    SAFE_COMPLETED = 'SAFE_COMPLETED'
    IN_GRACE_PERIOD = 'IN_GRACE_PERIOD'
    OVERDUE_PRE_ALERT = 'OVERDUE_PRE_ALERT'
    OVERDUE_ESCALATED = 'OVERDUE_ESCALATED'
    CANCELLED = 'CANCELLED'


class CheckIn(db.Model):
    """Smart Scheduled Check-In model with separated grace period and pre-alert window."""
    __tablename__ = 'check_ins'

    id = db.Column(db.BigInteger().with_variant(db.Integer, "sqlite"), primary_key=True, autoincrement=True)
    user_id = db.Column(
        db.BigInteger().with_variant(db.Integer, "sqlite"),
        db.ForeignKey('users.id', ondelete='CASCADE'),
        nullable=False,
        index=True
    )
    title = db.Column(db.String(150), nullable=False, default='Routine Check-In')
    destination_note = db.Column(db.String(255), nullable=True)
    scheduled_for = db.Column(db.DateTime, nullable=False, index=True)
    
    # Separated durations
    grace_period_minutes = db.Column(db.Integer, nullable=False, default=10)
    pre_alert_seconds = db.Column(db.Integer, nullable=False, default=20)
    
    status = db.Column(db.String(30), nullable=False, default=CheckInStatus.SCHEDULED, index=True)
    safety_pin_hash = db.Column(db.String(255), nullable=True)
    failed_pin_attempts = db.Column(db.Integer, nullable=False, default=0)
    locked_until = db.Column(db.DateTime, nullable=True)
    checked_in_at = db.Column(db.DateTime, nullable=True)
    
    created_at = db.Column(db.DateTime, nullable=False, default=lambda: datetime.now(timezone.utc))
    updated_at = db.Column(
        db.DateTime,
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc)
    )

    def set_pin(self, pin: str):
        if pin:
            self.safety_pin_hash = hash_pin(pin)

    def verify_pin(self, pin: str) -> bool:
        if not self.safety_pin_hash:
            return True  # No PIN challenge required
        return check_pin(self.safety_pin_hash, pin)

    def is_pin_locked(self, now: datetime = None) -> bool:
        """Checks if check-in is currently in an active security lockout cooldown."""
        if not self.locked_until:
            return False
        current_time = now or datetime.now(timezone.utc)
        if self.locked_until.tzinfo is None and current_time.tzinfo is not None:
            locked = self.locked_until.replace(tzinfo=timezone.utc)
        elif self.locked_until.tzinfo is not None and current_time.tzinfo is None:
            locked = self.locked_until
            current_time = current_time.replace(tzinfo=timezone.utc)
        else:
            locked = self.locked_until
        return current_time < locked

    def calculate_current_state(self, now: datetime = None) -> str:
        """Deterministically evaluates the state of this check-in based on current timestamp."""
        if self.status in [CheckInStatus.SAFE_COMPLETED, CheckInStatus.CANCELLED, CheckInStatus.OVERDUE_ESCALATED]:
            return self.status

        current_time = now or datetime.now(timezone.utc)
        # Ensure timezone-aware comparison if scheduled_for has tzinfo
        if self.scheduled_for.tzinfo is None and current_time.tzinfo is not None:
            sched = self.scheduled_for.replace(tzinfo=timezone.utc)
        elif self.scheduled_for.tzinfo is not None and current_time.tzinfo is None:
            sched = self.scheduled_for
            current_time = current_time.replace(tzinfo=timezone.utc)
        else:
            sched = self.scheduled_for

        if current_time < sched:
            return CheckInStatus.SCHEDULED

        grace_expiry = sched + timedelta(minutes=self.grace_period_minutes)
        if current_time < grace_expiry:
            return CheckInStatus.IN_GRACE_PERIOD

        pre_alert_expiry = grace_expiry + timedelta(seconds=self.pre_alert_seconds)
        if current_time < pre_alert_expiry:
            return CheckInStatus.OVERDUE_PRE_ALERT

        return CheckInStatus.OVERDUE_ESCALATED

    def to_dict(self):
        return {
            "id": self.id,
            "user_id": self.user_id,
            "title": self.title,
            "destination_note": self.destination_note,
            "scheduled_for": self.scheduled_for.isoformat() if self.scheduled_for else None,
            "grace_period_minutes": self.grace_period_minutes,
            "pre_alert_seconds": self.pre_alert_seconds,
            "status": self.status,
            "has_pin": bool(self.safety_pin_hash),
            "failed_pin_attempts": self.failed_pin_attempts,
            "locked_until": self.locked_until.isoformat() if self.locked_until else None,
            "is_locked": self.is_pin_locked(),
            "checked_in_at": self.checked_in_at.isoformat() if self.checked_in_at else None,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }
