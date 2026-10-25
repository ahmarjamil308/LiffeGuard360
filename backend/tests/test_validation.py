import pytest
from marshmallow import ValidationError
from app.schemas.auth_schemas import RegisterSchema, ProfileUpdateSchema
from app.schemas.contact_schemas import ContactCreateSchema
from app.schemas.checkin_schemas import CheckInCreateSchema
from app.schemas.sos_schemas import SOSTriggerSchema


def test_register_schema_validation():
    schema = RegisterSchema()
    
    # Valid payload
    valid_data = {
        "full_name": "Jane Doe",
        "email": "jane@example.com",
        "phone": "+12025550111",
        "password": "StrongPassword123!"
    }
    assert schema.load(valid_data)["email"] == "jane@example.com"

    # Too short password
    with pytest.raises(ValidationError) as exc:
        schema.load({**valid_data, "password": "short"})
    assert "password" in exc.value.messages

    # Bad phone format
    with pytest.raises(ValidationError) as exc:
        schema.load({**valid_data, "phone": "abc-not-a-phone"})
    assert "phone" in exc.value.messages


def test_checkin_grace_period_boundaries():
    schema = CheckInCreateSchema()
    base = {
        "scheduled_for": "2026-10-21T16:00:00Z"
    }

    # Within valid limits: grace 1 to 60 mins, pre-alert 10 to 45 secs
    assert schema.load({**base, "grace_period_minutes": 1, "pre_alert_seconds": 10})
    assert schema.load({**base, "grace_period_minutes": 60, "pre_alert_seconds": 45})

    # Grace period < 1 min rejected
    with pytest.raises(ValidationError):
        schema.load({**base, "grace_period_minutes": 0})

    # Grace period > 60 mins rejected
    with pytest.raises(ValidationError):
        schema.load({**base, "grace_period_minutes": 61})

    # Pre-alert < 10 secs rejected
    with pytest.raises(ValidationError):
        schema.load({**base, "pre_alert_seconds": 5})

    # Pre-alert > 45 secs rejected
    with pytest.raises(ValidationError):
        schema.load({**base, "pre_alert_seconds": 50})


def test_contact_tier_boundaries():
    schema = ContactCreateSchema()
    base = {"name": "Contact", "phone": "+15551234567"}

    # Valid tiers 1, 2, 3
    for tier in [1, 2, 3]:
        assert schema.load({**base, "priority_tier": tier})["priority_tier"] == tier

    # Invalid tier
    with pytest.raises(ValidationError):
        schema.load({**base, "priority_tier": 4})


def test_sos_coordinates_validation():
    schema = SOSTriggerSchema()
    
    # Valid coordinates
    assert schema.load({"latitude": 37.7749, "longitude": -122.4194})
    
    # Invalid latitude (> 90)
    with pytest.raises(ValidationError):
        schema.load({"latitude": 95.0, "longitude": 0.0})

    # Invalid longitude (> 180)
    with pytest.raises(ValidationError):
        schema.load({"latitude": 0.0, "longitude": 185.0})
