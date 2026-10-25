import json
from datetime import datetime, timezone
from app.extensions import db


class AuditLog(db.Model):
    """Immutable audit trail for all security, authentication, and emergency actions."""
    __tablename__ = 'audit_logs'

    id = db.Column(db.BigInteger().with_variant(db.Integer, "sqlite"), primary_key=True, autoincrement=True)
    user_id = db.Column(
        db.BigInteger().with_variant(db.Integer, "sqlite"),
        db.ForeignKey('users.id', ondelete='SET NULL'),
        nullable=True,
        index=True
    )
    event_type = db.Column(db.String(80), nullable=False, index=True)
    action_description = db.Column(db.String(255), nullable=False)
    ip_address = db.Column(db.String(45), nullable=True)
    user_agent = db.Column(db.String(255), nullable=True)
    event_metadata_json = db.Column(db.JSON, nullable=True)
    
    created_at = db.Column(db.DateTime, nullable=False, default=lambda: datetime.now(timezone.utc), index=True)

    user = db.relationship('User', backref='audit_logs')

    def to_dict(self):
        metadata = self.event_metadata_json
        if isinstance(metadata, str):
            try:
                metadata = json.loads(metadata)
            except Exception:
                pass
        return {
            "id": self.id,
            "user_id": self.user_id,
            "event_type": self.event_type,
            "action_description": self.action_description,
            "ip_address": self.ip_address,
            "user_agent": self.user_agent,
            "metadata": metadata,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
