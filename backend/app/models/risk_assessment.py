import json
from datetime import datetime, timezone
from app.extensions import db


class RiskLevel:
    SAFE = 'SAFE'
    CAUTION = 'CAUTION'
    CRITICAL = 'CRITICAL'


class RiskAssessment(db.Model):
    """Historical log of explainable risk assessments."""
    __tablename__ = 'risk_assessments'

    id = db.Column(db.BigInteger().with_variant(db.Integer, "sqlite"), primary_key=True, autoincrement=True)
    user_id = db.Column(
        db.BigInteger().with_variant(db.Integer, "sqlite"),
        db.ForeignKey('users.id', ondelete='CASCADE'),
        nullable=False,
        index=True
    )
    composite_score = db.Column(db.Integer, nullable=False)
    risk_level = db.Column(db.String(20), nullable=False, default=RiskLevel.SAFE)
    
    # 4 Factor Scores (0 - 100)
    checkin_score = db.Column(db.Integer, nullable=False, default=0)
    impact_score = db.Column(db.Integer, nullable=False, default=0)
    battery_score = db.Column(db.Integer, nullable=False, default=0)
    transit_score = db.Column(db.Integer, nullable=False, default=0)

    factors_json = db.Column(db.JSON, nullable=False)
    explanation_text = db.Column(db.Text, nullable=False)
    disclaimer = db.Column(
        db.Text,
        nullable=False,
        default="This score is a decision-support heuristic and does not guarantee personal safety."
    )

    evaluated_at = db.Column(db.DateTime, nullable=False, default=lambda: datetime.now(timezone.utc), index=True)
    created_at = db.Column(db.DateTime, nullable=False, default=lambda: datetime.now(timezone.utc))

    def to_dict(self):
        factors = self.factors_json
        if isinstance(factors, str):
            try:
                factors = json.loads(factors)
            except Exception:
                pass
        return {
            "id": self.id,
            "user_id": self.user_id,
            "composite_score": self.composite_score,
            "risk_level": self.risk_level,
            "factors": {
                "checkin": self.checkin_score,
                "impact": self.impact_score,
                "battery": self.battery_score,
                "transit": self.transit_score,
                "details": factors,
            },
            "explanation": self.explanation_text,
            "disclaimer": self.disclaimer,
            "evaluated_at": self.evaluated_at.isoformat() if self.evaluated_at else None,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
