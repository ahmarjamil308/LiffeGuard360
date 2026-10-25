import secrets
from datetime import datetime, timezone
from app.extensions import db


class DispatchChannel:
    PUSH = 'PUSH'
    SMS = 'SMS'
    TELEPHONY = 'TELEPHONY'


class DispatchStatus:
    QUEUED_OFFLINE = 'QUEUED_OFFLINE'  # Saved locally on device outbox
    QUEUED = 'QUEUED'                  # Registered on backend outbox
    SENT = 'SENT'                      # Accepted by gateway (Twilio / FCM)
    DELIVERED = 'DELIVERED'            # Confirmed handset delivery receipt (carrier DLR)
    VIEWED = 'VIEWED'                  # Alert web link opened (viewed only, not yet confirmed)
    ACKNOWLEDGED = 'ACKNOWLEDGED'      # Explicit responder confirmation action
    FAILED = 'FAILED'                  # Hard failure or carrier rejection
    UNKNOWN = 'UNKNOWN'                # Provider returned unexpected or ambiguous status


class IncidentDispatch(db.Model):
    """Tracks delivery status of an emergency alert to an individual contact or authority."""
    __tablename__ = 'incident_dispatches'

    id = db.Column(db.BigInteger().with_variant(db.Integer, "sqlite"), primary_key=True, autoincrement=True)
    incident_id = db.Column(
        db.BigInteger().with_variant(db.Integer, "sqlite"),
        db.ForeignKey('incidents.id', ondelete='CASCADE'),
        nullable=False,
        index=True
    )
    contact_id = db.Column(
        db.BigInteger().with_variant(db.Integer, "sqlite"),
        db.ForeignKey('emergency_contacts.id', ondelete='SET NULL'),
        nullable=True,
        index=True
    )
    tier = db.Column(db.Integer, nullable=False, default=1)
    channel = db.Column(db.String(20), nullable=False, default=DispatchChannel.PUSH)
    dispatch_status = db.Column(db.String(30), nullable=False, default=DispatchStatus.QUEUED, index=True)
    
    message_body = db.Column(db.Text, nullable=False)
    gateway_message_id = db.Column(db.String(100), nullable=True)
    sent_at = db.Column(db.DateTime, nullable=True)
    viewed_at = db.Column(db.DateTime, nullable=True)
    acknowledged_at = db.Column(db.DateTime, nullable=True)
    failure_reason = db.Column(db.String(255), nullable=True)
    retry_count = db.Column(db.Integer, nullable=False, default=0)
    last_attempted_at = db.Column(db.DateTime, nullable=True)
    acknowledgment_token = db.Column(
        db.String(64),
        unique=True,
        nullable=False,
        default=lambda: secrets.token_hex(24)
    )

    created_at = db.Column(db.DateTime, nullable=False, default=lambda: datetime.now(timezone.utc))

    contact = db.relationship('EmergencyContact', backref='dispatches')

    def to_dict(self):
        return {
            "id": self.id,
            "incident_id": self.incident_id,
            "contact_id": self.contact_id,
            "contact_name": self.contact.name if self.contact else None,
            "contact_phone": self.contact.phone if self.contact else None,
            "tier": self.tier,
            "channel": self.channel,
            "dispatch_status": self.dispatch_status,
            "message_body": self.message_body,
            "gateway_message_id": self.gateway_message_id,
            "sent_at": self.sent_at.isoformat() if self.sent_at else None,
            "viewed_at": self.viewed_at.isoformat() if self.viewed_at else None,
            "acknowledged_at": self.acknowledged_at.isoformat() if self.acknowledged_at else None,
            "failure_reason": self.failure_reason,
            "retry_count": self.retry_count,
            "last_attempted_at": self.last_attempted_at.isoformat() if self.last_attempted_at else None,
            "acknowledgment_token": self.acknowledgment_token,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
