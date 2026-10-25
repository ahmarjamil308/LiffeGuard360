import uuid
from datetime import datetime, timezone
from app.extensions import db
from app.utils.security import hash_password, check_password


class User(db.Model):
    """User account model containing personal, security, and emergency profile data."""
    __tablename__ = 'users'

    id = db.Column(db.BigInteger().with_variant(db.Integer, "sqlite"), primary_key=True, autoincrement=True)
    uuid = db.Column(db.String(36), unique=True, nullable=False, default=lambda: str(uuid.uuid4()))
    full_name = db.Column(db.String(120), nullable=False)
    email = db.Column(db.String(191), unique=True, nullable=False, index=True)
    phone = db.Column(db.String(30), unique=True, nullable=False, index=True)
    password_hash = db.Column(db.String(255), nullable=False)
    
    # Emergency & Medical Profile
    blood_group = db.Column(db.String(10), nullable=True)
    allergies = db.Column(db.Text, nullable=True)
    medical_notes = db.Column(db.Text, nullable=True)
    emergency_notes = db.Column(db.Text, nullable=True)
    default_emergency_number = db.Column(db.String(20), nullable=False, default='911')

    # Configurable Grace Periods (Strictly Separated)
    checkin_grace_period_minutes = db.Column(db.Integer, nullable=False, default=10)
    pre_alert_countdown_seconds = db.Column(db.Integer, nullable=False, default=20)

    is_active = db.Column(db.Boolean, nullable=False, default=True)
    created_at = db.Column(db.DateTime, nullable=False, default=lambda: datetime.now(timezone.utc))
    updated_at = db.Column(
        db.DateTime,
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc)
    )

    # Relationships
    contacts = db.relationship('EmergencyContact', backref='user', lazy='dynamic', cascade='all, delete-orphan')
    checkins = db.relationship('CheckIn', backref='user', lazy='dynamic', cascade='all, delete-orphan')
    incidents = db.relationship('Incident', backref='user', lazy='dynamic', cascade='all, delete-orphan')
    telemetry = db.relationship('SensorTelemetry', backref='user', lazy='dynamic', cascade='all, delete-orphan')
    risk_assessments = db.relationship('RiskAssessment', backref='user', lazy='dynamic', cascade='all, delete-orphan')

    def set_password(self, password: str):
        self.password_hash = hash_password(password)

    def verify_password(self, password: str) -> bool:
        return check_password(self.password_hash, password)

    def to_dict(self, include_medical=True):
        data = {
            "id": self.id,
            "uuid": self.uuid,
            "full_name": self.full_name,
            "email": self.email,
            "phone": self.phone,
            "default_emergency_number": self.default_emergency_number,
            "checkin_grace_period_minutes": self.checkin_grace_period_minutes,
            "pre_alert_countdown_seconds": self.pre_alert_countdown_seconds,
            "is_active": self.is_active,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }
        if include_medical:
            data.update({
                "blood_group": self.blood_group,
                "allergies": self.allergies,
                "medical_notes": self.medical_notes,
                "emergency_notes": self.emergency_notes,
            })
        return data
