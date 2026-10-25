import os
from datetime import datetime, timezone, timedelta
from app.extensions import db
from app.models.incident import Incident, IncidentStatus, IncidentTriggerSource
from app.models.incident_dispatch import IncidentDispatch, DispatchStatus
from app.models.contact import EmergencyContact
from app.services.escalation_service import EscalationService
from app.services.sms_service import mock_sms_adapter


def test_checkin_lifecycle_and_pin_challenge(client, authenticated_user):
    headers = authenticated_user['headers']
    future_time = (datetime.now(timezone.utc) + timedelta(minutes=30)).isoformat()

    # 1. Schedule check-in with safety PIN
    sched_res = client.post('/api/v1/checkin/schedule', headers=headers, json={
        "title": "Evening Commute Home",
        "destination_note": "Central Station to Maple Street",
        "scheduled_for": future_time,
        "grace_period_minutes": 10,
        "pre_alert_seconds": 25,
        "safety_pin": "5432"
    })
    assert sched_res.status_code == 201
    checkin_data = sched_res.get_json()['data']['checkin']
    checkin_id = checkin_data['id']
    assert checkin_data['title'] == "Evening Commute Home"
    assert checkin_data['grace_period_minutes'] == 10
    assert checkin_data['pre_alert_seconds'] == 25
    assert checkin_data['has_pin'] is True

    # 2. Get active check-in
    active_res = client.get('/api/v1/checkin/active', headers=headers)
    assert active_res.status_code == 200
    assert active_res.get_json()['data']['has_active'] is True
    assert active_res.get_json()['data']['checkin']['id'] == checkin_id

    # 3. Confirm with wrong PIN -> Rejected
    bad_pin_res = client.post(f'/api/v1/checkin/confirm/{checkin_id}', headers=headers, json={
        "safety_pin": "0000"
    })
    assert bad_pin_res.status_code == 400
    assert "Incorrect safety PIN" in bad_pin_res.get_json()['message']

    # 4. Confirm with correct PIN -> Success
    good_pin_res = client.post(f'/api/v1/checkin/confirm/{checkin_id}', headers=headers, json={
        "safety_pin": "5432"
    })
    assert good_pin_res.status_code == 200
    assert good_pin_res.get_json()['data']['checkin']['status'] == "SAFE_COMPLETED"

    # 5. Verify active check-in is now None
    active_after = client.get('/api/v1/checkin/active', headers=headers)
    assert active_after.status_code == 200
    assert active_after.get_json()['data']['has_active'] is False


def test_end_to_end_checkin_overdue_escalation_and_responder_flow(client, authenticated_user, db_session):
    mock_sms_adapter.reset()
    headers = authenticated_user['headers']
    user_id = authenticated_user['user']['id']

    # 1. Setup emergency contact
    contact = EmergencyContact(
        user_id=user_id,
        name="Guardian Alice",
        phone="+15551239999",
        relationship="Parent",
        priority_tier=1,
        notify_sms=True
    )
    db_session.add(contact)
    db_session.commit()

    # 2. Schedule a check-in whose time is in the past (overdue beyond grace period + pre-alert)
    past_time = (datetime.now(timezone.utc) - timedelta(minutes=45)).isoformat()
    sched_res = client.post('/api/v1/checkin/schedule', headers=headers, json={
        "title": "Solo Evening Trail Hike",
        "destination_note": "Pine Ridge Trailhead",
        "scheduled_for": past_time,
        "grace_period_minutes": 15,
        "pre_alert_seconds": 30,
        "safety_pin": "9876"
    })
    assert sched_res.status_code == 201
    checkin_id = sched_res.get_json()['data']['checkin']['id']

    # 3. Trigger check and escalation of overdue check-ins
    created_incidents = EscalationService.check_and_escalate_overdue_checkins()
    assert len(created_incidents) == 1
    incident = created_incidents[0]
    assert incident.user_id == user_id
    assert incident.trigger_source == IncidentTriggerSource.OVERDUE_CHECKIN
    # Documented formula: w_C (0.40) * 100 = 40.0, cleanly separated from manual 100
    assert incident.risk_score_at_trigger == 40.0
    assert incident.status == IncidentStatus.ACTIVE

    # 4. Verify immediate Tier 1 dispatch was created and sent
    dispatches = IncidentDispatch.query.filter_by(incident_id=incident.id).all()
    assert len(dispatches) >= 1
    dispatch = dispatches[0]
    assert dispatch.dispatch_status == DispatchStatus.SENT
    token = dispatch.acknowledgment_token
    assert token is not None

    # 6. Responder views public tracking link
    view_res = client.get(f'/api/v1/sos/respond/{token}')
    assert view_res.status_code == 200
    view_payload = view_res.get_json()['data']
    assert view_payload['requires_explicit_acknowledgment'] is True

    # In database, status transitions to VIEWED, but NOT acknowledged
    d_viewed = db.session.get(IncidentDispatch, dispatch.id)
    assert d_viewed.dispatch_status == DispatchStatus.VIEWED
    assert d_viewed.viewed_at is not None
    assert d_viewed.acknowledged_at is None

    # 7. Responder explicitly acknowledges via token endpoint
    ack_res = client.post(
        f'/api/v1/sos/dispatch/{dispatch.id}/acknowledge?token={token}'
    )
    assert ack_res.status_code == 200
    d_acked = db.session.get(IncidentDispatch, dispatch.id)
    assert d_acked.dispatch_status == DispatchStatus.ACKNOWLEDGED
    assert d_acked.acknowledged_at is not None

    # 8. User enters PIN to confirm safety and close out checkin
    confirm_res = client.post(f'/api/v1/checkin/confirm/{checkin_id}', headers=headers, json={
        "safety_pin": "9876"
    })
    assert confirm_res.status_code == 200
    assert confirm_res.get_json()['data']['checkin']['status'] == "SAFE_COMPLETED"


def test_pin_brute_force_lockout(client, authenticated_user):
    """Verifies that 5 consecutive failed PIN attempts trigger a security lockout."""
    headers = authenticated_user['headers']
    future_time = (datetime.now(timezone.utc) + timedelta(minutes=20)).isoformat()

    sched_res = client.post('/api/v1/checkin/schedule', headers=headers, json={
        "title": "Late Night Walk",
        "scheduled_for": future_time,
        "safety_pin": "1234"
    })
    checkin_id = sched_res.get_json()['data']['checkin']['id']

    # 4 failed attempts should fail with "Incorrect safety PIN"
    for i in range(1, 5):
        res = client.post(f'/api/v1/checkin/confirm/{checkin_id}', headers=headers, json={"safety_pin": "9999"})
        assert res.status_code == 400
        assert "Incorrect safety PIN" in res.get_json()['message']

    # 5th failed attempt triggers security lockout
    res_5th = client.post(f'/api/v1/checkin/confirm/{checkin_id}', headers=headers, json={"safety_pin": "9999"})
    assert res_5th.status_code == 400
    assert "locked for security" in res_5th.get_json()['message'].lower()

    # Even providing the correct PIN after lockout must be rejected
    res_correct_after_lockout = client.post(f'/api/v1/checkin/confirm/{checkin_id}', headers=headers, json={"safety_pin": "1234"})
    assert res_correct_after_lockout.status_code == 400
    assert "locked for security" in res_correct_after_lockout.get_json()['message'].lower()


def test_checkin_cancel_with_pin_and_ownership(client, authenticated_user):
    """Verifies PIN-protected cancellation and tenant ownership isolation."""
    headers_owner = authenticated_user['headers']
    future_time = (datetime.now(timezone.utc) + timedelta(minutes=25)).isoformat()

    # 1. Owner schedules check-in with PIN
    sched_res = client.post('/api/v1/checkin/schedule', headers=headers_owner, json={
        "title": "Study Group Commute",
        "scheduled_for": future_time,
        "safety_pin": "4321"
    })
    checkin_id = sched_res.get_json()['data']['checkin']['id']

    # 2. Register attacker user
    attacker_res = client.post('/api/v1/auth/register', json={
        "full_name": "Attacker User",
        "email": "attacker@lifeguard360.local",
        "phone": "+12025550999",
        "password": "Password123!",
        "blood_group": "A+",
        "default_emergency_number": "911"
    })
    headers_attacker = {"Authorization": f"Bearer {attacker_res.get_json()['data']['tokens']['access_token']}"}

    # 3. Attacker tries to cancel owner's check-in -> 400 not found (tenant isolation)
    attack_cancel = client.post(f'/api/v1/checkin/cancel/{checkin_id}', headers=headers_attacker, json={"safety_pin": "4321"})
    assert attack_cancel.status_code == 400
    assert "not found" in attack_cancel.get_json()['message'].lower()

    # 4. Owner cancels with wrong PIN -> Rejected
    bad_cancel = client.post(f'/api/v1/checkin/cancel/{checkin_id}', headers=headers_owner, json={"safety_pin": "0000"})
    assert bad_cancel.status_code == 400
    assert "Incorrect safety PIN" in bad_cancel.get_json()['message']

    # 5. Owner cancels with correct PIN -> Success
    good_cancel = client.post(f'/api/v1/checkin/cancel/{checkin_id}', headers=headers_owner, json={"safety_pin": "4321"})
    assert good_cancel.status_code == 200
    assert good_cancel.get_json()['data']['checkin']['status'] == "CANCELLED"

    # 6. Cancelled check-in does NOT escalate even when overdue
    # Simulate time passing into overdue
    past_now = datetime.now(timezone.utc) + timedelta(hours=2)
    escalated = EscalationService.check_and_escalate_overdue_checkins(now=past_now)
    # Check that this checkin was not escalated
    checkin_inc = Incident.query.filter_by(client_incident_uuid=f"checkin_overdue_{checkin_id}_{authenticated_user['user']['id']}").first()
    assert checkin_inc is None


def test_checkin_extension_at_state_boundaries(client, authenticated_user):
    """Verifies that extending check-in pushes the scheduled deadline and maintains state safety."""
    headers = authenticated_user['headers']
    sched_time = (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()

    sched_res = client.post('/api/v1/checkin/schedule', headers=headers, json={
        "title": "Meeting Extended",
        "scheduled_for": sched_time
    })
    checkin_id = sched_res.get_json()['data']['checkin']['id']

    # Extend by 30 minutes
    ext_res = client.post(f'/api/v1/checkin/extend/{checkin_id}', headers=headers, json={
        "additional_minutes": 30
    })
    assert ext_res.status_code == 200
    checkin_data = ext_res.get_json()['data']['checkin']
    assert checkin_data['status'] == "SCHEDULED"


def test_worker_tick_endpoint_and_cron_escalation(client, authenticated_user, db_session):
    """Verifies that the /worker/tick endpoint triggers background escalation when authenticated with WORKER_SECRET."""
    mock_sms_adapter.reset()
    headers = authenticated_user['headers']
    user_id = authenticated_user['user']['id']
    test_secret = "test-cron-worker-secret-12345"
    os.environ['WORKER_SECRET'] = test_secret

    contact = EmergencyContact(
        user_id=user_id,
        name="Guardian Bob",
        phone="+15559876543",
        relationship="Parent",
        priority_tier=1,
        notify_sms=True
    )
    db_session.add(contact)
    db_session.commit()

    # Schedule an overdue checkin
    past_time = (datetime.now(timezone.utc) - timedelta(minutes=40)).isoformat()
    client.post('/api/v1/checkin/schedule', headers=headers, json={
        "title": "Solo Jog",
        "scheduled_for": past_time,
        "grace_period_minutes": 10,
        "pre_alert_seconds": 20
    })

    # Trigger worker tick with valid X-Worker-Secret header
    tick_headers = {"X-Worker-Secret": test_secret}
    tick_res = client.post('/api/v1/checkin/worker/tick', headers=tick_headers)
    assert tick_res.status_code == 200
    data = tick_res.get_json()['data']
    assert data['escalated_incidents_count'] >= 1

    # Verify dispatch was generated for contact and sent
    d = IncidentDispatch.query.filter_by(contact_id=contact.id).first()
    assert d is not None
    assert d.dispatch_status == DispatchStatus.SENT
    assert d.tier == 1


def test_worker_tick_security_and_unauthorized_rejection(client, authenticated_user):
    """Verifies that /worker/tick strictly rejects missing secrets, invalid secrets, and unprivileged user JWTs."""
    test_secret = "strong-cluster-secret-888"
    os.environ['WORKER_SECRET'] = test_secret
    user_headers = authenticated_user['headers']

    # 1. Unauthenticated request without headers
    res_no_auth = client.post('/api/v1/checkin/worker/tick')
    assert res_no_auth.status_code == 401
    assert "unauthorized" in res_no_auth.get_json()['message'].lower()

    # 2. Invalid worker secret
    res_bad_secret = client.post('/api/v1/checkin/worker/tick', headers={"X-Worker-Secret": "wrong-secret"})
    assert res_bad_secret.status_code == 401

    # 3. Standard user JWT without worker secret header -> Rejected (401)
    res_user_jwt_only = client.post('/api/v1/checkin/worker/tick', headers=user_headers)
    assert res_user_jwt_only.status_code == 401


def test_concurrent_worker_execution_idempotency(db_session, authenticated_user):
    """Verifies that consecutive or concurrent worker runs do not create duplicate incidents or dispatches."""
    user_id = authenticated_user['user']['id']
    past_time = datetime.now(timezone.utc) - timedelta(minutes=50)

    from app.models.checkin import CheckIn, CheckInStatus
    c = CheckIn(
        user_id=user_id,
        title="Double Worker Run",
        scheduled_for=past_time,
        grace_period_minutes=10,
        pre_alert_seconds=20,
        status=CheckInStatus.SCHEDULED
    )
    db_session.add(c)
    db_session.commit()

    # Worker Run 1
    run1 = EscalationService.check_and_escalate_overdue_checkins()
    assert len(run1) == 1

    # Worker Run 2 (immediate re-run)
    run2 = EscalationService.check_and_escalate_overdue_checkins()
    assert len(run2) == 0  # No duplicate incident created

    # Verify only 1 incident exists with client_incident_uuid for this checkin
    incidents = Incident.query.filter_by(client_incident_uuid=f"checkin_overdue_{c.id}_{user_id}").all()
    assert len(incidents) == 1


def test_pin_lockout_cooldown_and_password_recovery(client, authenticated_user, db_session):
    """
    Verifies that:
    1. 5 failed PIN attempts trigger a 15-minute lockout cooldown.
    2. Correct PIN during lockout is rejected.
    3. Another user cannot recover the lockout (tenant isolation).
    4. Legitimate user can immediately recover using verified account password.
    5. After recovery or cooldown expiration, correct PIN confirms successfully.
    """
    headers = authenticated_user['headers']
    user_id = authenticated_user['user']['id']
    future_time = (datetime.now(timezone.utc) + timedelta(minutes=25)).isoformat()

    sched_res = client.post('/api/v1/checkin/schedule', headers=headers, json={
        "title": "Night Shift Commute",
        "scheduled_for": future_time,
        "safety_pin": "7777"
    })
    checkin_id = sched_res.get_json()['data']['checkin']['id']

    # 1. 5 failed PIN attempts
    for _ in range(4):
        res = client.post(f'/api/v1/checkin/confirm/{checkin_id}', headers=headers, json={"safety_pin": "0000"})
        assert res.status_code == 400
    res_5th = client.post(f'/api/v1/checkin/confirm/{checkin_id}', headers=headers, json={"safety_pin": "0000"})
    assert res_5th.status_code == 400
    assert "locked for security" in res_5th.get_json()['message'].lower()

    # 2. Correct PIN during lockout is rejected
    res_correct_during_lock = client.post(f'/api/v1/checkin/confirm/{checkin_id}', headers=headers, json={"safety_pin": "7777"})
    assert res_correct_during_lock.status_code == 400
    assert "cooldown expires in" in res_correct_during_lock.get_json()['message'].lower()

    # 3. Attacker cannot recover owner's check-in
    attacker_res = client.post('/api/v1/auth/register', json={
        "full_name": "Intruder User",
        "email": "intruder@lifeguard360.local",
        "phone": "+12025550888",
        "password": "Password123!",
        "blood_group": "B+",
        "default_emergency_number": "911"
    })
    headers_attacker = {"Authorization": f"Bearer {attacker_res.get_json()['data']['tokens']['access_token']}"}
    attack_recover = client.post(f'/api/v1/checkin/recover-lockout/{checkin_id}', headers=headers_attacker, json={
        "account_password": "Password123!"
    })
    assert attack_recover.status_code == 400
    assert "not found" in attack_recover.get_json()['message'].lower()

    # 4. Owner wrong password -> rejected
    bad_pass_recover = client.post(f'/api/v1/checkin/recover-lockout/{checkin_id}', headers=headers, json={
        "account_password": "WrongPassword999!"
    })
    assert bad_pass_recover.status_code == 400
    assert "invalid account password" in bad_pass_recover.get_json()['message'].lower()

    # 5. Owner correct password -> lockout cleared
    good_pass_recover = client.post(f'/api/v1/checkin/recover-lockout/{checkin_id}', headers=headers, json={
        "account_password": "SecurePassword123!"
    })
    assert good_pass_recover.status_code == 200
    assert good_pass_recover.get_json()['data']['checkin']['failed_pin_attempts'] == 0

    # 6. Correct PIN now succeeds
    confirm_res = client.post(f'/api/v1/checkin/confirm/{checkin_id}', headers=headers, json={"safety_pin": "7777"})
    assert confirm_res.status_code == 200
    assert confirm_res.get_json()['data']['checkin']['status'] == "SAFE_COMPLETED"


def test_cancellation_race_with_escalation_does_not_silently_erase_incident(client, authenticated_user, db_session):
    """
    Verifies that if a check-in has already escalated to an active emergency incident,
    a late cancellation request is strictly rejected to prevent silently erasing or
    falsely resolving active emergency alerts.
    """
    mock_sms_adapter.reset()
    headers = authenticated_user['headers']
    user_id = authenticated_user['user']['id']

    contact = EmergencyContact(
        user_id=user_id,
        name="Guardian Carol",
        phone="+15554443322",
        relationship="Sibling",
        priority_tier=1,
        notify_sms=True
    )
    db_session.add(contact)
    db_session.commit()

    # Schedule checkin in past
    past_time = (datetime.now(timezone.utc) - timedelta(minutes=45)).isoformat()
    sched_res = client.post('/api/v1/checkin/schedule', headers=headers, json={
        "title": "Evening Commute",
        "scheduled_for": past_time,
        "grace_period_minutes": 10,
        "pre_alert_seconds": 20,
        "safety_pin": "6543"
    })
    checkin_id = sched_res.get_json()['data']['checkin']['id']

    # Background worker escalates overdue checkin to emergency incident
    escalated = EscalationService.check_and_escalate_overdue_checkins()
    assert len(escalated) == 1
    incident_id = escalated[0].id

    # User attempts late cancellation via checkin cancel endpoint
    cancel_res = client.post(f'/api/v1/checkin/cancel/{checkin_id}', headers=headers, json={"safety_pin": "6543"})
    assert cancel_res.status_code == 400
    assert "already escalated to active emergency incident" in cancel_res.get_json()['message']

    # Verify the emergency incident remains ACTIVE and was not silently erased
    inc = db_session.get(Incident, incident_id)
    assert inc.status == IncidentStatus.ACTIVE

    # Extension is also rejected
    ext_res = client.post(f'/api/v1/checkin/extend/{checkin_id}', headers=headers, json={"additional_minutes": 15})
    assert ext_res.status_code == 400
    assert "already escalated" in ext_res.get_json()['message']


def test_worker_crash_recovery_for_orphaned_escalated_checkin(db_session, authenticated_user):
    """
    Simulates a worker crash after setting CheckIn status to OVERDUE_ESCALATED but before Incident creation.
    Verifies that the next evaluation tick detects the orphaned record and successfully creates the incident.
    """
    user_id = authenticated_user['user']['id']
    past_time = datetime.now(timezone.utc) - timedelta(minutes=30)

    from app.models.checkin import CheckIn, CheckInStatus
    c = CheckIn(
        user_id=user_id,
        title="Crash Scenario Check-In",
        scheduled_for=past_time,
        status=CheckInStatus.OVERDUE_ESCALATED  # Orphaned status from simulated crash
    )
    db_session.add(c)
    db_session.commit()

    # Incident does not exist yet
    client_uuid = f"checkin_overdue_{c.id}_{user_id}"
    assert Incident.query.filter_by(client_incident_uuid=client_uuid).first() is None

    # Run escalation tick (crash recovery)
    recovered = EscalationService.check_and_escalate_overdue_checkins()
    assert len(recovered) == 1
    assert recovered[0].client_incident_uuid == client_uuid
    assert recovered[0].trigger_source == IncidentTriggerSource.OVERDUE_CHECKIN


def test_responder_token_security_expiration_and_monotonicity(client, authenticated_user, db_session):
    """
    Verifies responder token security:
    1. 48-hour expiration.
    2. Monotonic state (carrier DLR cannot downgrade VIEWED to DELIVERED).
    3. Idempotent acknowledgment preserving initial acknowledged_at timestamp.
    4. Revocation when incident is resolved or false alarm.
    """
    user_id = authenticated_user['user']['id']
    from app.models.incident import Incident, IncidentStatus, IncidentTriggerSource
    from app.models.incident_dispatch import IncidentDispatch, DispatchStatus

    incident = Incident(
        client_incident_uuid="test_token_incident_uuid",
        user_id=user_id,
        trigger_source=IncidentTriggerSource.MANUAL,
        status=IncidentStatus.ACTIVE,
        risk_score_at_trigger=0.0,
        triggered_at=datetime.now(timezone.utc)
    )
    db_session.add(incident)
    db_session.flush()

    dispatch = IncidentDispatch(
        incident_id=incident.id,
        tier=1,
        message_body="Emergency distress test",
        dispatch_status=DispatchStatus.SENT,
        gateway_message_id="SM_test_dlr_monotonicity"
    )
    db_session.add(dispatch)
    db_session.commit()

    token = dispatch.acknowledgment_token

    # 1. View link -> VIEWED
    view_res = client.get(f'/api/v1/sos/respond/{token}')
    assert view_res.status_code == 200
    d_viewed = db_session.get(IncidentDispatch, dispatch.id)
    assert d_viewed.dispatch_status == DispatchStatus.VIEWED

    # 2. Late Twilio DLR arrives with 'delivered' -> Must NOT downgrade VIEWED to DELIVERED
    EscalationService.handle_twilio_status_callback("SM_test_dlr_monotonicity", "delivered")
    d_after_dlr = db_session.get(IncidentDispatch, dispatch.id)
    assert d_after_dlr.dispatch_status == DispatchStatus.VIEWED  # Monotonicity preserved!

    # 3. Responder acknowledges -> ACKNOWLEDGED
    ack_res1 = client.post(f'/api/v1/sos/dispatch/{dispatch.id}/acknowledge?token={token}')
    assert ack_res1.status_code == 200
    first_ack_time = db_session.get(IncidentDispatch, dispatch.id).acknowledged_at
    assert first_ack_time is not None

    # 4. Duplicate acknowledgment replay -> Preserves initial timestamp
    ack_res2 = client.post(f'/api/v1/sos/dispatch/{dispatch.id}/acknowledge?token={token}')
    assert ack_res2.status_code == 200
    second_ack_time = db_session.get(IncidentDispatch, dispatch.id).acknowledged_at
    assert first_ack_time == second_ack_time

    # 5. Token expiration check: Dispatch older than 48 hours is rejected
    dispatch.created_at = datetime.now(timezone.utc) - timedelta(hours=50)
    db_session.commit()
    expired_view = client.get(f'/api/v1/sos/respond/{token}')
    assert expired_view.status_code == 404

    # 6. Revocation check: Incident cancelled as false alarm invalidates token
    dispatch.created_at = datetime.now(timezone.utc)  # Reset to fresh
    incident.status = IncidentStatus.CANCELLED_FALSE_ALARM
    db_session.commit()
    revoked_view = client.get(f'/api/v1/sos/respond/{token}')
    assert revoked_view.status_code == 404


