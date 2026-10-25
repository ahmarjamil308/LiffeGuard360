from flask import Blueprint, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from app.extensions import db
from app.models.risk_assessment import RiskAssessment
from app.services.risk_engine import RiskEngine
from app.utils.responses import success_response

risk_bp = Blueprint('risk', __name__, url_prefix='/api/v1/risk')


@risk_bp.route('/calculate', methods=['POST'])
@jwt_required()
def calculate_risk():
    user_id = int(get_jwt_identity())
    body = request.get_json() or {}

    result = RiskEngine.compute(
        checkin_state=body.get('checkin_state'),
        accel_rms=body.get('accel_rms'),
        motion_variance=body.get('motion_variance'),
        is_sensor_degraded=body.get('is_sensor_degraded', False),
        battery_pct=body.get('battery_pct'),
        is_charging=body.get('is_charging'),
        is_active_trip=body.get('is_active_trip', False),
        stationary_minutes=body.get('stationary_minutes'),
        is_gps_degraded=body.get('is_gps_degraded', False),
    )

    # Persist assessment record for audit & transparency history
    assessment = RiskAssessment(
        user_id=user_id,
        composite_score=result['composite_score'],
        risk_level=result['risk_level'],
        checkin_score=result['factor_scores']['checkin'],
        impact_score=result['factor_scores']['impact'],
        battery_score=result['factor_scores']['battery'],
        transit_score=result['factor_scores']['transit'],
        factors_json=result['factor_scores'],
        explanation_text="; ".join(result['explanations']),
        disclaimer=result['disclaimer']
    )
    db.session.add(assessment)
    db.session.commit()

    return success_response(
        data={
            "assessment_id": assessment.id,
            "risk_assessment": result
        },
        message="Risk assessment calculated successfully"
    )
