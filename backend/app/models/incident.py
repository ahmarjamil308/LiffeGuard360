import uuid
from datetime import datetime, timezone
from app.extensions import db


class IncidentTriggerSource:
    MANUAL = 'MANUAL'
    AUTOMATED_RISK = 'AUTOMATED_RISK'
    OVERDUE_CHECKIN = 'OVERDUE_CHECKIN'
    SEVERE_FALL = 'SEVERE_FALL'


class IncidentStatus:
    QUEUED_OFFLINE = 'QUEUED_OFFLINE'
    ACTIVE = 'ACTIVE'
    CANCELLED_FALSE_ALARM = 'CANCELLED_FALSE_ALARM'
    RESOLVED = 'RESOLVED'


class Incident(db.Model):
    """Authoritative emergency incident entity with idempotent client UUID."""
    __tablename__ = 'incidents'

    id = db.Column(db.BigInteger().with_variant(db.Integer, "sqlite"), primary_key=True, autoincrement=True)
    client_incident_uuid = db.Column(
        db.String(36),
        unique=True,
        nullable=False,
        index=True,
        default=lambda: str(uuid.uuid4())
    )
    user_id = db.Column(
        db.BigInteger().with_variant(db.Integer, "sqlite"),
        db.ForeignKey('users.id', ondelete='CASCADE'),
        nullable=False,
        index=True
    )
    trigger_source = db.Column(db.String(30), nullable=False, default=IncidentTriggerSource.MANUAL)
    risk_score_at_trigger = db.Column(db.Float, nullable=False, default=0.0)
    status = db.Column(db.String(30), nullable=False, default=IncidentStatus.ACTIVE, index=True)
    
    # Location at trigger
    trigger_latitude = db.Column(db.Float, nullable=True)
    trigger_longitude = db.Column(db.Float, nullable=True)
    location_accuracy = db.Column(db.Float, nullable=True)

    false_alarm_reason = db.Column(db.String(255), nullable=True)
    triggered_at = db.Column(db.DateTime, nullable=False, default=lambda: datetime.now(timezone.utc))
    resolved_at = db.Column(db.DateTime, nullable=True)

    created_at = db.Column(db.DateTime, nullable=False, default=lambda: datetime.now(timezone.utc))
    updated_at = db.Column(
        db.DateTime,
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc)
    )

    dispatches = db.relationship('IncidentDispatch', backref='incident', lazy='dynamic', cascade='all, delete-orphan')
    telemetry_logs = db.relationship('SensorTelemetry', backref='incident', lazy='dynamic')

    def to_dict(self, include_dispatches=False):
        data = {
            "id": self.id,
            "client_incident_uuid": self.client_incident_uuid,
            "user_id": self.user_id,
            "trigger_source": self.trigger_source,
            "risk_score_at_trigger": self.risk_score_at_trigger,
            "status": self.status,
            "location": {
                "latitude": self.trigger_latitude,
                "longitude": self.trigger_longitude,
                "accuracy": self.location_accuracy,
            },
            "false_alarm_reason": self.false_alarm_reason,
            "triggered_at": self.triggered_at.isoformat() if self.triggered_at else None,
            "resolved_at": self.resolved_at.isoformat() if self.resolved_at else None,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }
        if include_dispatches:
            data["dispatches"] = [d.to_dict() for d in self.dispatches.all()]
        return data
