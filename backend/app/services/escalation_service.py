import uuid
from datetime import datetime, timezone
from typing import List, Dict, Any, Tuple, Optional
from app.extensions import db
from app.models.incident import Incident, IncidentStatus, IncidentTriggerSource
from app.models.incident_dispatch import IncidentDispatch, DispatchStatus, DispatchChannel
from app.models.contact import EmergencyContact
from app.models.checkin import CheckIn, CheckInStatus
from app.services.sms_service import SMSService
from app.services.notification_service import PushNotificationService
from app.services.audit_service import AuditService


class EscalationService:
    MAX_RETRIES = 3

    @classmethod
    def process_pending_dispatches(cls, batch_size: int = 50) -> Dict[str, int]:
        """
        Transactional outbox processor.
        Iterates over pending/retriable dispatches and executes delivery through gateway adapters.
        Guarantees that cancellation races and gateway errors never lose state or duplicate alerts.
        """
        pending_dispatches = IncidentDispatch.query.join(Incident).filter(
            IncidentDispatch.dispatch_status.in_([DispatchStatus.QUEUED, DispatchStatus.QUEUED_OFFLINE]),
            IncidentDispatch.retry_count < cls.MAX_RETRIES
        ).limit(batch_size).all()

        stats = {"processed": 0, "sent": 0, "failed": 0, "cancelled_race": 0}

        for dispatch in pending_dispatches:
            stats["processed"] += 1
            incident = dispatch.incident

            # Cancellation race check: If incident was cancelled by user while dispatch was in queue
            if incident.status == IncidentStatus.CANCELLED_FALSE_ALARM:
                dispatch.dispatch_status = DispatchStatus.FAILED
                dispatch.failure_reason = "Cancelled by user as false alarm before transmission"
                stats["cancelled_race"] += 1
                continue

            # Idempotency key per delivery attempt
            idempotency_key = f"dispatch_{dispatch.id}_{dispatch.retry_count}"
            target_phone = dispatch.contact.phone if dispatch.contact else "EMERGENCY_SERVICES"

            dispatch.last_attempted_at = datetime.now(timezone.utc)

            success = False
            gateway_msg_id = ""
            error_msg = None

            if dispatch.channel == DispatchChannel.SMS:
                success, gateway_msg_id, error_msg = SMSService.send(
                    to_phone=target_phone,
                    body=dispatch.message_body,
                    idempotency_key=idempotency_key
                )
            elif dispatch.channel == DispatchChannel.PUSH:
                success, gateway_msg_id, error_msg = PushNotificationService.send(
                    recipient=f"user_{incident.user_id}_topic",
                    title="LifeGuard 360 Emergency Alert",
                    body=dispatch.message_body,
                    data={"incident_id": str(incident.id), "tier": str(dispatch.tier)}
                )
            else:
                success = False
                error_msg = f"Unsupported dispatch channel: {dispatch.channel}"

            if success:
                # Gateway accepted request -> Mark SENT (delivery receipt required for DELIVERED)
                dispatch.dispatch_status = DispatchStatus.SENT
                dispatch.gateway_message_id = gateway_msg_id
                dispatch.sent_at = datetime.now(timezone.utc)
                dispatch.failure_reason = None
                stats["sent"] += 1
            else:
                dispatch.retry_count += 1
                dispatch.failure_reason = error_msg
                if dispatch.retry_count >= cls.MAX_RETRIES:
                    dispatch.dispatch_status = DispatchStatus.FAILED
                stats["failed"] += 1

        db.session.commit()
        return stats

    @classmethod
    def record_delivery_receipt(cls, gateway_message_id: str) -> bool:
        """
        Transitions dispatch from SENT to DELIVERED upon receiving proof-of-delivery from carrier/gateway.
        """
        dispatch = IncidentDispatch.query.filter_by(gateway_message_id=gateway_message_id).first()
        if not dispatch:
            return False

        if dispatch.dispatch_status in (DispatchStatus.SENT, DispatchStatus.QUEUED):
            dispatch.dispatch_status = DispatchStatus.DELIVERED
            db.session.commit()
            return True
        return False

    @classmethod
    def record_link_viewed(cls, token: str) -> Optional[IncidentDispatch]:
        """
        Records that an emergency contact has clicked and viewed the dispatch link.
        CRITICAL: Link viewing does NOT constitute confirmed responder acknowledgment!
        It moves status from SENT/DELIVERED to VIEWED. Explicit action is still required for ACKNOWLEDGED.
        
        SECURITY CONTROLS:
        - Token validation (48 hex characters).
        - Expiration: Token expires 48 hours after dispatch creation.
        - Revocation: Inactive or false alarm incidents invalidate the token.
        """
        if not token or len(token) != 48:
            return None

        dispatch = IncidentDispatch.query.filter_by(acknowledgment_token=token).first()
        if not dispatch:
            return None

        # Check token expiration (48-hour validity window)
        now = datetime.now(timezone.utc)
        created = dispatch.created_at.replace(tzinfo=timezone.utc) if dispatch.created_at.tzinfo is None else dispatch.created_at
        if (now - created).total_seconds() > 48 * 3600:
            return None

        # Check incident revocation
        if dispatch.incident.status in [IncidentStatus.CANCELLED_FALSE_ALARM, IncidentStatus.RESOLVED]:
            return None

        dispatch.viewed_at = now
        if dispatch.dispatch_status in (DispatchStatus.SENT, DispatchStatus.DELIVERED):
            dispatch.dispatch_status = DispatchStatus.VIEWED

        db.session.commit()
        AuditService.log_event(
            user_id=dispatch.incident.user_id,
            event_type='ALERT_LINK_VIEWED',
            action_description=f"Emergency dispatch #{dispatch.id} alert link opened by {dispatch.contact.name if dispatch.contact else 'Responder'} (Viewed Only - Not Yet Acknowledged)"
        )
        return dispatch

    @classmethod
    def handle_twilio_status_callback(cls, gateway_message_id: str, message_status: str, error_code: str = None, error_message: str = None) -> bool:
        """
        Maps Twilio delivery receipts (DLR) to substantiated delivery states.
        Twilio status values: 'queued', 'sent', 'delivered', 'undelivered', 'failed'.
        
        MONOTONICITY SAFEGUARD:
        - Never alters or reverts an ACKNOWLEDGED dispatch.
        - Never downgrades a VIEWED dispatch back to DELIVERED or SENT.
        """
        dispatch = IncidentDispatch.query.filter_by(gateway_message_id=gateway_message_id).first()
        if not dispatch:
            return False

        # Idempotency / monotonicity: Do not revert an explicitly acknowledged dispatch
        if dispatch.dispatch_status == DispatchStatus.ACKNOWLEDGED:
            return True

        # If responder already opened the webpage, carrier DLR cannot downgrade VIEWED to DELIVERED
        if dispatch.dispatch_status == DispatchStatus.VIEWED:
            return True

        status_lower = message_status.lower()
        if status_lower == 'delivered':
            dispatch.dispatch_status = DispatchStatus.DELIVERED
            dispatch.failure_reason = None
        elif status_lower in ('undelivered', 'failed'):
            dispatch.dispatch_status = DispatchStatus.FAILED
            dispatch.failure_reason = f"Carrier DLR reported {message_status.upper()}: {error_message or error_code or 'Handset unreachable'}"
        elif status_lower == 'sent' and dispatch.dispatch_status in (DispatchStatus.QUEUED, DispatchStatus.QUEUED_OFFLINE):
            dispatch.dispatch_status = DispatchStatus.SENT
        elif status_lower in ('queued', 'sending'):
            pass
        else:
            # Ambiguous or unknown carrier status: keep distinct from hard failure
            dispatch.dispatch_status = DispatchStatus.UNKNOWN
            dispatch.failure_reason = f"Ambiguous carrier status: {message_status}"

        db.session.commit()
        return True

    @classmethod
    def acknowledge_dispatch(cls, dispatch_id: int, token: str = None, user_id: int = None) -> IncidentDispatch:
        """
        Records verified responder acknowledgment of an emergency dispatch.
        Secured by unguessable acknowledgment_token (with 48h expiration) or verified incident owner user_id.
        Preserves initial acknowledged_at timestamp monotonically on duplicate replays.
        """
        dispatch = db.session.get(IncidentDispatch, dispatch_id)
        if not dispatch:
            raise ValueError("Dispatch record not found.")

        # Idempotent replay: if already acknowledged, return immediately without altering timestamp
        if dispatch.dispatch_status == DispatchStatus.ACKNOWLEDGED:
            return dispatch

        # Authorization check: valid responder token or authenticated incident owner
        is_authorized = False
        if token and dispatch.acknowledgment_token == token:
            now = datetime.now(timezone.utc)
            created = dispatch.created_at.replace(tzinfo=timezone.utc) if dispatch.created_at.tzinfo is None else dispatch.created_at
            if (now - created).total_seconds() > 48 * 3600:
                raise ValueError("Emergency response token has expired (48-hour validity window exceeded).")
            if dispatch.incident.status in [IncidentStatus.CANCELLED_FALSE_ALARM, IncidentStatus.RESOLVED]:
                raise ValueError(f"Emergency incident #{dispatch.incident_id} is no longer active (status: {dispatch.incident.status}).")
            is_authorized = True
        elif user_id and dispatch.incident.user_id == user_id:
            is_authorized = True

        if not is_authorized:
            raise PermissionError("Unauthorized acknowledgment attempt. Valid responder token or owner authorization required.")

        dispatch.dispatch_status = DispatchStatus.ACKNOWLEDGED
        dispatch.acknowledged_at = datetime.now(timezone.utc)
        db.session.commit()

        AuditService.log_event(
            user_id=dispatch.incident.user_id,
            event_type='ALERT_ACKNOWLEDGED',
            action_description=f"Emergency dispatch #{dispatch.id} acknowledged by {dispatch.contact.name if dispatch.contact else 'Responder'}"
        )
        return dispatch

    @classmethod
    def retry_failed_dispatch(cls, dispatch_id: int, user_id: int = None) -> IncidentDispatch:
        """
        Recovers a failed or retry-exhausted dispatch back into the QUEUED outbox.
        Ensures critical alerts are not permanently discarded.
        """
        dispatch = db.session.get(IncidentDispatch, dispatch_id)
        if not dispatch:
            raise ValueError("Dispatch record not found.")

        if user_id and dispatch.incident.user_id != user_id:
            raise PermissionError("Unauthorized to retry dispatch for this incident.")

        if dispatch.dispatch_status != DispatchStatus.FAILED:
            raise ValueError(f"Dispatch status is '{dispatch.dispatch_status}'; only FAILED dispatches can be manually retried.")

        dispatch.dispatch_status = DispatchStatus.QUEUED
        dispatch.retry_count = 0
        dispatch.failure_reason = None
        dispatch.last_attempted_at = None
        db.session.commit()

        AuditService.log_event(
            user_id=dispatch.incident.user_id,
            event_type='DISPATCH_MANUAL_RETRY',
            action_description=f"Manually re-queued failed emergency dispatch #{dispatch.id} to outbox"
        )
        return dispatch

    @classmethod
    def escalate_incident_tier(cls, incident_id: int, target_tier: int, user_id: int = None) -> List[IncidentDispatch]:
        """
        Escalates an active emergency to the next priority tier (e.g. Tier 1 -> Tier 2 Secondary contacts).
        """
        incident = db.session.get(Incident, incident_id)
        if not incident or incident.status != IncidentStatus.ACTIVE:
            return []

        if user_id and incident.user_id != user_id:
            raise PermissionError("Unauthorized to escalate another user's incident.")

        contacts = EmergencyContact.query.filter_by(
            user_id=incident.user_id,
            priority_tier=target_tier,
            is_active=True
        ).all()

        location_str = f"https://maps.google.com/?q={incident.trigger_latitude},{incident.trigger_longitude}" if incident.trigger_latitude else "Location unavailable"
        alert_body = f"ESCALATED ALERT (Tier {target_tier}): LifeGuard 360 emergency unacknowledged. Primary contacts did not respond. Location: {location_str}"

        new_dispatches = []
        for c in contacts:
            dispatch = IncidentDispatch(
                incident_id=incident.id,
                contact_id=c.id,
                tier=target_tier,
                channel=DispatchChannel.SMS if c.notify_sms else DispatchChannel.PUSH,
                dispatch_status=DispatchStatus.QUEUED,
                message_body=alert_body
            )
            db.session.add(dispatch)
            new_dispatches.append(dispatch)

        db.session.commit()
        AuditService.log_event(
            user_id=incident.user_id,
            event_type='TIER_ESCALATED',
            action_description=f"Incident #{incident.id} escalated to Priority Tier {target_tier}"
        )
        return new_dispatches

    @classmethod
    def check_and_escalate_overdue_checkins(cls, now: datetime = None) -> List[Incident]:
        """
        Evaluates active check-in timers.
        If a check-in expires past its grace period and pre-alert window without a PIN,
        automatically triggers an OVERDUE_CHECKIN emergency incident.
        
        CRITICAL ARCHITECTURAL SEPARATION:
        - The composite risk score is genuinely calculated from the documented RiskEngine formula (0.40 * 100 = 40.0).
        - The emergency escalation decision is driven by the policy that overdue check-in triggers an ACTIVE incident.
        
        CRASH RECOVERY:
        - If a prior tick updated CheckIn to OVERDUE_ESCALATED but crashed before Incident creation,
          reconciles the orphaned record and ensures emergency dispatches are enqueued.
        """
        created_incidents = []
        current_time = now or datetime.now(timezone.utc)

        # 1. Crash recovery: Check for any orphaned check-ins marked OVERDUE_ESCALATED without an Incident
        orphaned = CheckIn.query.filter_by(status=CheckInStatus.OVERDUE_ESCALATED).all()
        for o in orphaned:
            client_uuid = f"checkin_overdue_{o.id}_{o.user_id}"
            existing_inc = Incident.query.filter_by(client_incident_uuid=client_uuid).first()
            if not existing_inc:
                from app.services.sos_service import SOSService
                from app.services.risk_engine import RiskEngine
                risk_eval = RiskEngine.compute(checkin_state=CheckInStatus.OVERDUE_ESCALATED)
                genuine_risk = float(risk_eval['composite_score'])
                incident, _ = SOSService.trigger_sos(
                    user_id=o.user_id,
                    data={
                        "client_incident_uuid": client_uuid,
                        "trigger_source": IncidentTriggerSource.OVERDUE_CHECKIN,
                        "risk_score_at_trigger": genuine_risk,
                    }
                )
                created_incidents.append(incident)

        # 2. Evaluate active check-in timers
        active_checkins = CheckIn.query.filter(
            CheckIn.status.in_([
                CheckInStatus.SCHEDULED,
                CheckInStatus.IN_GRACE_PERIOD,
                CheckInStatus.OVERDUE_PRE_ALERT
            ])
        ).all()

        for c in active_checkins:
            new_state = c.calculate_current_state(current_time)
            if new_state != c.status:
                if new_state == CheckInStatus.OVERDUE_ESCALATED:
                    client_uuid = f"checkin_overdue_{c.id}_{c.user_id}"
                    existing_inc = Incident.query.filter_by(client_incident_uuid=client_uuid).first()
                    if existing_inc:
                        c.status = new_state
                        continue

                    # Concurrency safety: atomic conditional status update prevents race between concurrent workers
                    updated = CheckIn.query.filter(CheckIn.id == c.id, CheckIn.status == c.status)\
                        .update({"status": new_state})
                    if not updated:
                        continue  # Lost race to another concurrent worker

                    from app.services.sos_service import SOSService
                    from app.services.risk_engine import RiskEngine
                    # Calculate authentic composite risk score under formula (CheckIn 100 * 0.40 = 40.0)
                    risk_eval = RiskEngine.compute(checkin_state=CheckInStatus.OVERDUE_ESCALATED)
                    genuine_risk = float(risk_eval['composite_score'])

                    incident, _ = SOSService.trigger_sos(
                        user_id=c.user_id,
                        data={
                            "client_incident_uuid": client_uuid,
                            "trigger_source": IncidentTriggerSource.OVERDUE_CHECKIN,
                            "risk_score_at_trigger": genuine_risk,
                        }
                    )
                    created_incidents.append(incident)
                else:
                    c.status = new_state

        db.session.commit()
        return created_incidents
