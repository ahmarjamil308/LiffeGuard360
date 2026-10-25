from app.services.risk_engine import RiskEngine


def test_risk_weights_sum_to_one():
    total_weights = (
        RiskEngine.WEIGHT_CHECKIN +
        RiskEngine.WEIGHT_IMPACT +
        RiskEngine.WEIGHT_BATTERY +
        RiskEngine.WEIGHT_TRANSIT
    )
    assert abs(total_weights - 1.0) < 1e-6


def test_stationary_phone_produces_zero_risk():
    """
    SAFETY INVARIANT:
    A phone resting still on a table or in a pocket with zero movement
    MUST produce a risk score of 0 and NEVER trigger an emergency.
    """
    res = RiskEngine.compute(
        checkin_state="SCHEDULED",
        accel_rms=1.0,           # Normal earth gravity resting
        motion_variance=0.0,     # Stillness
        battery_pct=85,
        is_charging=False,
        is_active_trip=False
    )
    assert res['composite_score'] == 0
    assert res['risk_level'] == "SAFE"
    assert res['factor_scores']['impact'] == 0


def test_missing_and_degraded_sensors_produce_zero_contribution():
    """
    SAFETY INVARIANT:
    Missing sensor data or disabled GPS MUST be tagged degraded/unknown
    and MUST NOT increase danger scores.
    """
    res = RiskEngine.compute(
        checkin_state=None,
        accel_rms=None,          # Offline / denied accelerometer
        motion_variance=None,
        is_sensor_degraded=True,
        battery_pct=None,        # Unavailable battery
        is_gps_degraded=True,    # No GPS fix
        is_active_trip=False
    )
    assert res['composite_score'] == 0
    assert res['risk_level'] == "SAFE"
    assert res['factor_scores']['impact'] == 0
    assert res['factor_scores']['battery'] == 0
    assert res['factor_scores']['transit'] == 0


def test_signature_fall_and_immobility():
    """
    Severe acceleration spike (>= 3.5g) followed by sustained stillness (variance <= 0.10g)
    triggers the Impact factor (S_I = 100).
    Weighted contribution: 0.35 * 100 = 35 points -> Elevated CAUTION.
    """
    res = RiskEngine.compute(
        accel_rms=4.2,
        motion_variance=0.04,    # Immobility post-impact
        battery_pct=90
    )
    assert res['factor_scores']['impact'] == 100
    assert res['weighted_contributions']['impact'] == 35.0
    assert res['composite_score'] == 35
    assert res['risk_level'] == "CAUTION"


def test_compound_critical_escalation():
    """
    Check-in severely overdue (100) + Fall impact with immobility (100) + Discharging critical battery (70).
    R = 0.40(100) + 0.35(100) + 0.15(70) + 0.10(0) = 40 + 35 + 10.5 = 85.5 -> 86 -> CRITICAL.
    """
    res = RiskEngine.compute(
        checkin_state="OVERDUE_ESCALATED",
        accel_rms=3.8,
        motion_variance=0.08,
        battery_pct=8,
        is_charging=False
    )
    assert res['factor_scores']['checkin'] == 100
    assert res['factor_scores']['impact'] == 100
    assert res['factor_scores']['battery'] == 70
    assert res['composite_score'] == 86
    assert res['risk_level'] == "CRITICAL"


def test_clamping_and_disclaimer():
    res = RiskEngine.compute(checkin_state="SCHEDULED")
    assert 0 <= res['composite_score'] <= 100
    assert "heuristic" in res['disclaimer'].lower()
    assert "not guarantee" in res['disclaimer'].lower()
