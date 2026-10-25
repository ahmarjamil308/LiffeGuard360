import uuid
import threading
from datetime import datetime, timezone
from app.extensions import db
from app.models.incident import Incident, IncidentTriggerSource, IncidentStatus
from app.models.incident_dispatch import IncidentDispatch, DispatchChannel, DispatchStatus
from app.models.contact import EmergencyContact
from app.services.audit_service import AuditService

_sos_lock = threading.Lock()


class SOSService:
    @staticmethod
    def trigger_sos(user_id: int, data: dict) -> tuple[Incident, bool]:
        """
        Idempotently creates an emergency incident and initiates multi-tier dispatch.
        
        CRITICAL SAFETY RULE:
        - Completely bypasses risk scoring calculation.
        - Idempotent against client_incident_uuid retries: If already persisted, returns
          the existing incident WITHOUT creating duplicate dispatches or spamming contacts.
        
        Returns: (incident, is_new)
        """
        with _sos_lock:
            client_uuid = data.get('client_incident_uuid')
            if client_uuid:
                existing = Incident.query.filter_by(client_incident_uuid=client_uuid).first()
                if existing:
                    # Idempotent replay: return existing incident
                    return existing, False
            else:
                client_uuid = str(uuid.uuid4())

            trigger_source = data.get('trigger_source', IncidentTriggerSource.MANUAL)
            risk_score = float(data.get('risk_score_at_trigger', 0.0))
            lat = data.get('latitude')
            lon = data.get('longitude')
            acc = data.get('accuracy')
            triggered_at = data.get('triggered_at') or datetime.now(timezone.utc)

            incident = Incident(
                client_incident_uuid=client_uuid,
                user_id=user_id,
                trigger_source=trigger_source,
                risk_score_at_trigger=risk_score,
                status=IncidentStatus.ACTIVE,
                trigger_latitude=lat,
                trigger_longitude=lon,
                location_accuracy=acc,
                triggered_at=triggered_at
            )
            db.session.add(incident)
            db.session.flush()  # Assigns incident.id
            incident_id = incident.id

            # Fetch active emergency contacts for tiered dispatch
            contacts = EmergencyContact.query.filter_by(user_id=user_id, is_active=True)\
                .order_by(EmergencyContact.priority_tier.asc())\
                .all()

            location_str = f"https://maps.google.com/?q={lat},{lon}" if lat and lon else "Location unavailable"
            alert_body = f"EMERGENCY ALERT: LifeGuard 360 distress triggered! User needs immediate assistance. {location_str}"

            if contacts:
                for c in contacts:
                    # Dispatch Tier 1 immediately; Tier 2/3 queued for escalation
                    status = DispatchStatus.SENT if c.priority_tier == 1 else DispatchStatus.QUEUED
                    dispatch = IncidentDispatch(
                        incident_id=incident_id,
                        contact_id=c.id,
                        tier=c.priority_tier,
                        channel=DispatchChannel.SMS if c.notify_sms else DispatchChannel.PUSH,
                        dispatch_status=status,
                        message_body=alert_body,
                        sent_at=datetime.now(timezone.utc) if status == DispatchStatus.SENT else None
                    )
                    db.session.add(dispatch)
            else:
                # Fallback dispatch record to system emergency queue when no contacts configured
                dispatch = IncidentDispatch(
                    incident_id=incident_id,
                    contact_id=None,
                    tier=1,
                    channel=DispatchChannel.PUSH,
                    dispatch_status=DispatchStatus.SENT,
                    message_body=alert_body,
                    sent_at=datetime.now(timezone.utc)
                )
                db.session.add(dispatch)

            from sqlalchemy.exc import IntegrityError
            try:
                db.session.commit()
            except IntegrityError:
                db.session.rollback()
                db.session.expunge_all()
                existing = Incident.query.filter_by(client_incident_uuid=client_uuid).first()
                if existing:
                    return existing, False
                raise

            AuditService.log_event(
                user_id=user_id,
                event_type='SOS_TRIGGERED',
                action_description=f"Emergency SOS triggered ({trigger_source}) - Incident #{incident_id} (UUID: {client_uuid})"
            )
            return incident, True

    @staticmethod
    def sync_offline_incidents(user_id: int, items: list[dict]) -> list[dict]:
        """
        Idempotent bulk synchronization of offline queued emergency incidents.
        Guarantees that network retries never produce duplicate incidents or redundant alerts.
        """
        synced_results = []
        for item in items:
            client_uuid = item['client_incident_uuid']
            existing = Incident.query.filter_by(client_incident_uuid=client_uuid).first()

            if existing:
                synced_results.append({
                    "client_incident_uuid": client_uuid,
                    "incident_id": existing.id,
                    "status": existing.status,
                    "synced": True,
                    "is_duplicate_ignored": True
                })
            else:
                incident, _ = SOSService.trigger_sos(user_id, item)
                synced_results.append({
                    "client_incident_uuid": client_uuid,
                    "incident_id": incident.id,
                    "status": incident.status,
                    "synced": True,
                    "is_duplicate_ignored": False
                })

        return synced_results

    @staticmethod
    def cancel_sos(user_id: int, incident_id: int = None, client_uuid: str = None, reason: str = None) -> Incident:
        """Cancels an active incident and flags as false alarm."""
        query = Incident.query.filter_by(user_id=user_id)
        if incident_id:
            incident = query.filter_by(id=incident_id).first()
        elif client_uuid:
            incident = query.filter_by(client_incident_uuid=client_uuid).first()
        else:
            raise ValueError("Either incident_id or client_incident_uuid must be provided.")

        if not incident:
            raise ValueError("Emergency incident not found.")

        incident.status = IncidentStatus.CANCELLED_FALSE_ALARM
        incident.false_alarm_reason = reason or "User entered false alarm PIN"
        incident.resolved_at = datetime.now(timezone.utc)

        # Update remaining queued dispatches to cancelled
        for d in incident.dispatches:
            if d.dispatch_status in [DispatchStatus.QUEUED, DispatchStatus.QUEUED_OFFLINE]:
                d.dispatch_status = DispatchStatus.FAILED
                d.failure_reason = "Cancelled by user as false alarm"

        db.session.commit()

        AuditService.log_event(
            user_id=user_id,
            event_type='SOS_CANCELLED',
            action_description=f"Incident #{incident.id} marked false alarm: {incident.false_alarm_reason}"
        )
        return incident

    @staticmethod
    def get_incident(user_id: int, incident_id: int) -> Incident:
        incident = Incident.query.filter_by(id=incident_id, user_id=user_id).first()
        if not incident:
            raise ValueError("Emergency incident not found.")
        return incident
