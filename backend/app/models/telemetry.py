from datetime import datetime, timezone
from app.extensions import db


class TelemetryStatus:
    NORMAL = 'NORMAL'
    STALE = 'STALE'
    DEGRADED = 'DEGRADED'
    OFFLINE = 'OFFLINE'


class SensorTelemetry(db.Model):
    """Stores periodic or incident-triggered device telemetry."""
    __tablename__ = 'sensor_telemetry'

    id = db.Column(db.BigInteger().with_variant(db.Integer, "sqlite"), primary_key=True, autoincrement=True)
    user_id = db.Column(
        db.BigInteger().with_variant(db.Integer, "sqlite"),
        db.ForeignKey('users.id', ondelete='CASCADE'),
        nullable=False,
        index=True
    )
    incident_id = db.Column(
        db.BigInteger().with_variant(db.Integer, "sqlite"),
        db.ForeignKey('incidents.id', ondelete='SET NULL'),
        nullable=True,
        index=True
    )
    
    # Location
    latitude = db.Column(db.Float, nullable=True)
    longitude = db.Column(db.Float, nullable=True)
    speed = db.Column(db.Float, nullable=True)
    altitude = db.Column(db.Float, nullable=True)
    accuracy = db.Column(db.Float, nullable=True)

    # Motion / Accelerometer
    accel_rms = db.Column(db.Float, nullable=True)
    motion_variance = db.Column(db.Float, nullable=True)

    # Battery
    battery_percentage = db.Column(db.Integer, nullable=True)
    is_charging = db.Column(db.Boolean, nullable=True)

    telemetry_status = db.Column(db.String(20), nullable=False, default=TelemetryStatus.NORMAL)
    recorded_at = db.Column(db.DateTime, nullable=False, default=lambda: datetime.now(timezone.utc), index=True)
    created_at = db.Column(db.DateTime, nullable=False, default=lambda: datetime.now(timezone.utc))

    def to_dict(self):
        return {
            "id": self.id,
            "user_id": self.user_id,
            "incident_id": self.incident_id,
            "latitude": self.latitude,
            "longitude": self.longitude,
            "speed": self.speed,
            "altitude": self.altitude,
            "accuracy": self.accuracy,
            "accel_rms": self.accel_rms,
            "motion_variance": self.motion_variance,
            "battery_percentage": self.battery_percentage,
            "is_charging": self.is_charging,
            "telemetry_status": self.telemetry_status,
            "recorded_at": self.recorded_at.isoformat() if self.recorded_at else None,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
