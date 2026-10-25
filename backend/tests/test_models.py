import uuid
from datetime import datetime, timezone, timedelta
from app.models.user import User
from app.models.contact import EmergencyContact
from app.models.checkin import CheckIn, CheckInStatus
from app.models.incident import Incident, IncidentTriggerSource, IncidentStatus
from app.models.audit_log import AuditLog


def test_user_creation_and_password_hashing(db_session):
    user = User(
        full_name="Alice Smith",
        email="alice@lifeguard360.local",
        phone="+15551234567",
        blood_group="A+"
    )
    user.set_password("MySuperSecret99!")
    db_session.add(user)
    db_session.commit()

    assert user.id is not None
    assert user.uuid is not None
    assert user.verify_password("MySuperSecret99!") is True
    assert user.verify_password("WrongPassword") is False
    assert user.password_hash != "MySuperSecret99!"


def test_contact_priority_tiers(db_session):
    user = User(full_name="Bob", email="bob@test.com", phone="+15559876543")
    user.set_password("Password123!")
    db_session.add(user)
    db_session.commit()

    c1 = EmergencyContact(user_id=user.id, name="Mom", phone="+15551111111", priority_tier=1)
    c2 = EmergencyContact(user_id=user.id, name="Doc", phone="+15552222222", priority_tier=3)
    c3 = EmergencyContact(user_id=user.id, name="Bro", phone="+15553333333", priority_tier=2)
    db_session.add_all([c1, c2, c3])
    db_session.commit()

    ordered = EmergencyContact.query.filter_by(user_id=user.id).order_by(EmergencyContact.priority_tier.asc()).all()
    assert [c.name for c in ordered] == ["Mom", "Bro", "Doc"]


def test_checkin_state_machine_evaluation(db_session):
    now = datetime.now(timezone.utc)
    checkin = CheckIn(
        user_id=1,
        title="Walk Home",
        scheduled_for=now,
        grace_period_minutes=10,
        pre_alert_seconds=20,
        status=CheckInStatus.SCHEDULED
    )
    
    # 5 minutes before scheduled target
    assert checkin.calculate_current_state(now=now - timedelta(minutes=5)) == CheckInStatus.SCHEDULED
    # 5 minutes into grace period
    assert checkin.calculate_current_state(now=now + timedelta(minutes=5)) == CheckInStatus.IN_GRACE_PERIOD
    # 10 minutes + 10 seconds (in pre-alert window)
    assert checkin.calculate_current_state(now=now + timedelta(minutes=10, seconds=10)) == CheckInStatus.OVERDUE_PRE_ALERT
    # 10 minutes + 30 seconds (past pre-alert window)
    assert checkin.calculate_current_state(now=now + timedelta(minutes=10, seconds=30)) == CheckInStatus.OVERDUE_ESCALATED


def test_incident_client_uuid_uniqueness(db_session):
    fixed_uuid = str(uuid.uuid4())
    inc1 = Incident(
        client_incident_uuid=fixed_uuid,
        user_id=1,
        trigger_source=IncidentTriggerSource.MANUAL,
        status=IncidentStatus.ACTIVE
    )
    db_session.add(inc1)
    db_session.commit()

    # Second incident with duplicate client UUID should be rejected by uniqueness constraint
    inc2 = Incident(
        client_incident_uuid=fixed_uuid,
        user_id=1,
        trigger_source=IncidentTriggerSource.MANUAL,
        status=IncidentStatus.ACTIVE
    )
    db_session.add(inc2)
    import pytest
    from sqlalchemy.exc import IntegrityError
    with pytest.raises(IntegrityError):
        db_session.commit()
    db_session.rollback()
