from datetime import datetime, timezone
from app.extensions import db


class EmergencyContact(db.Model):
    """Priority-tiered emergency contact entity (Tier 1 Primary, Tier 2 Secondary, Tier 3 Guardian)."""
    __tablename__ = 'emergency_contacts'

    id = db.Column(db.BigInteger().with_variant(db.Integer, "sqlite"), primary_key=True, autoincrement=True)
    user_id = db.Column(
        db.BigInteger().with_variant(db.Integer, "sqlite"),
        db.ForeignKey('users.id', ondelete='CASCADE'),
        nullable=False,
        index=True
    )
    name = db.Column(db.String(120), nullable=False)
    phone = db.Column(db.String(30), nullable=False)
    email = db.Column(db.String(191), nullable=True)
    relationship = db.Column(db.String(50), nullable=False, default='Family')
    
    # Priority Tier: 1 = Immediate Primary, 2 = Secondary Escalation, 3 = Guardian/Medical Authority
    priority_tier = db.Column(db.Integer, nullable=False, default=1)
    
    # Notification preferences
    notify_sms = db.Column(db.Boolean, nullable=False, default=True)
    notify_push = db.Column(db.Boolean, nullable=False, default=True)
    notify_call = db.Column(db.Boolean, nullable=False, default=False)
    
    is_active = db.Column(db.Boolean, nullable=False, default=True)
    created_at = db.Column(db.DateTime, nullable=False, default=lambda: datetime.now(timezone.utc))
    updated_at = db.Column(
        db.DateTime,
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc)
    )

    def to_dict(self):
        return {
            "id": self.id,
            "user_id": self.user_id,
            "name": self.name,
            "phone": self.phone,
            "email": self.email,
            "relationship": self.relationship,
            "priority_tier": self.priority_tier,
            "notify_sms": self.notify_sms,
            "notify_push": self.notify_push,
            "notify_call": self.notify_call,
            "is_active": self.is_active,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }
