from typing import Dict, Any, Optional
from datetime import datetime, timezone, timedelta


class RiskEngine:
    """
    Transparent, explainable risk scoring engine for LifeGuard 360.
    
    Formula:
        R_raw = w_C * S_C + w_I * S_I + w_B * S_B + w_T * S_T
        R = round(clamp(R_raw, 0, 100))
        
    Weights:
        w_C = 0.40 (Check-In)
        w_I = 0.35 (Impact / Fall Dynamic)
        w_B = 0.15 (Battery Level)
        w_T = 0.10 (Transit Route / Off-Path)
        Sum = 1.00
        
    Thresholds:
        0 <= R < 30   : SAFE (Green)
        30 <= R < 70  : CAUTION (Amber)
        70 <= R <= 100 : CRITICAL (Red)
    """

    WEIGHT_CHECKIN = 0.40
    WEIGHT_IMPACT = 0.35
    WEIGHT_BATTERY = 0.15
    WEIGHT_TRANSIT = 0.10

    DISCLAIMER = (
        "This score is an assistive decision-support heuristic and does not guarantee personal safety. "
        "Missing or stationary sensor data alone does not trigger emergency escalation."
    )

    @classmethod
    def calculate_checkin_factor(cls, checkin_state: Optional[str]) -> tuple[int, str]:
        """
        Evaluate check-in score (0 - 100).
        States:
            SCHEDULED / SAFE_COMPLETED / CANCELLED / None -> 0
            IN_GRACE_PERIOD -> 50
            OVERDUE_PRE_ALERT -> 80
            OVERDUE_ESCALATED -> 100
        """
        if not checkin_state or checkin_state in ('SCHEDULED', 'SAFE_COMPLETED', 'CANCELLED', 'UNKNOWN'):
            return 0, "No overdue check-in"
        if checkin_state == 'IN_GRACE_PERIOD':
            return 50, "Check-in target passed; currently within user grace period"
        if checkin_state == 'OVERDUE_PRE_ALERT':
            return 80, "Check-in grace period expired; pre-alert cancellation countdown active"
        if checkin_state == 'OVERDUE_ESCALATED':
            return 100, "Check-in severely overdue past all grace and cancellation windows"
        return 0, "Normal check-in state"

    @classmethod
    def calculate_impact_factor(
        cls,
        accel_rms: Optional[float],
        motion_variance: Optional[float],
        is_sensor_stale_or_missing: bool = False
    ) -> tuple[int, str]:
        """
        Evaluate impact and fall dynamic (0 - 100).
        
        Crucial Safety Invariant:
        - Missing or stale sensor data yields 0 points (marked DEGRADED).
        - A phone resting still on a surface (accel_rms ~1.0g, variance ~0.0) yields 0 points (NORMAL_RESTING).
        """
        if is_sensor_stale_or_missing or accel_rms is None:
            return 0, "Motion sensors unavailable or degraded (0 risk contribution)"

        # Normal resting or gentle movement
        if accel_rms < 2.5:
            return 0, "Normal movement or resting stationary state"

        # Moderate bump or vibration
        if 2.5 <= accel_rms < 3.5:
            return 30, "Moderate shock or device drop detected"

        # Severe shock (accel_rms >= 3.5g)
        variance = motion_variance if motion_variance is not None else 1.0
        if variance <= 0.10:
            # High impact followed by sustained immobility -> Signature Fall
            return 100, "Severe impact followed by complete immobility (potential fall/collapse)"
        else:
            return 50, "High impact detected, but subsequent active motion is continuing"

    @classmethod
    def calculate_battery_factor(
        cls,
        battery_pct: Optional[int],
        is_charging: Optional[bool]
    ) -> tuple[int, str]:
        """
        Evaluate battery depletion factor (0 - 100).
        Missing battery data yields 0 points.
        """
        if battery_pct is None:
            return 0, "Battery status unavailable (0 risk contribution)"

        pct = max(0, min(100, battery_pct))
        charging = bool(is_charging)

        if pct > 20:
            return 0, f"Adequate battery level ({pct}%)"
        if 10 < pct <= 20:
            return 30, f"Low battery advisory ({pct}%)"
        if 5 < pct <= 10:
            if charging:
                return 20, f"Low battery ({pct}%), but device is actively charging"
            return 70, f"Critical low battery ({pct}%) and discharging"
        # pct <= 5
        if charging:
            return 40, f"Depleted battery ({pct}%), but currently on charger"
        return 100, f"Extreme battery depletion ({pct}%) with imminent shutdown risk"

    @classmethod
    def calculate_transit_factor(
        cls,
        is_active_trip: bool,
        stationary_minutes: Optional[float],
        is_gps_unavailable: bool = False
    ) -> tuple[int, str]:
        """
        Evaluate transit route/stoppage factor (0 - 100).
        Missing GPS data yields 0 points.
        """
        if not is_active_trip:
            return 0, "No active transit journey scheduled"
        if is_gps_unavailable or stationary_minutes is None:
            return 0, "GPS location unavailable during trip (marked degraded, 0 risk contribution)"

        if stationary_minutes <= 15:
            return 0, "Journey progressing normally"
        if 15 < stationary_minutes <= 30:
            return 40, f"Unexpected transit stoppage for {int(stationary_minutes)} minutes"
        return 80, f"Prolonged stationary delay in transit ({int(stationary_minutes)} minutes)"

    @classmethod
    def compute(
        cls,
        checkin_state: Optional[str] = None,
        accel_rms: Optional[float] = None,
        motion_variance: Optional[float] = None,
        is_sensor_degraded: bool = False,
        battery_pct: Optional[int] = None,
        is_charging: Optional[bool] = None,
        is_active_trip: bool = False,
        stationary_minutes: Optional[float] = None,
        is_gps_degraded: bool = False,
    ) -> Dict[str, Any]:
        """
        Computes composite transparent risk score and explanations.
        Clamped to [0, 100]. Returns full breakdown.
        """
        s_c, exp_c = cls.calculate_checkin_factor(checkin_state)
        s_i, exp_i = cls.calculate_impact_factor(accel_rms, motion_variance, is_sensor_degraded)
        s_b, exp_b = cls.calculate_battery_factor(battery_pct, is_charging)
        s_t, exp_t = cls.calculate_transit_factor(is_active_trip, stationary_minutes, is_gps_degraded)

        raw_score = (
            cls.WEIGHT_CHECKIN * s_c +
            cls.WEIGHT_IMPACT * s_i +
            cls.WEIGHT_BATTERY * s_b +
            cls.WEIGHT_TRANSIT * s_t
        )

        clamped_score = max(0.0, min(100.0, raw_score))
        final_score = int(round(clamped_score))

        if final_score >= 70:
            level = "CRITICAL"
        elif final_score >= 30:
            level = "CAUTION"
        else:
            level = "SAFE"

        # Collect plain-English contributing factors
        explanations = []
        if s_c > 0:
            explanations.append(exp_c)
        if s_i > 0:
            explanations.append(exp_i)
        if s_b > 0:
            explanations.append(exp_b)
        if s_t > 0:
            explanations.append(exp_t)
        if not explanations:
            explanations.append("All safety and telemetry indicators within normal operational parameters.")

        return {
            "composite_score": final_score,
            "risk_level": level,
            "weights": {
                "checkin": cls.WEIGHT_CHECKIN,
                "impact": cls.WEIGHT_IMPACT,
                "battery": cls.WEIGHT_BATTERY,
                "transit": cls.WEIGHT_TRANSIT,
            },
            "factor_scores": {
                "checkin": s_c,
                "impact": s_i,
                "battery": s_b,
                "transit": s_t,
            },
            "weighted_contributions": {
                "checkin": round(cls.WEIGHT_CHECKIN * s_c, 2),
                "impact": round(cls.WEIGHT_IMPACT * s_i, 2),
                "battery": round(cls.WEIGHT_BATTERY * s_b, 2),
                "transit": round(cls.WEIGHT_TRANSIT * s_t, 2),
            },
            "explanations": explanations,
            "disclaimer": cls.DISCLAIMER,
        }
