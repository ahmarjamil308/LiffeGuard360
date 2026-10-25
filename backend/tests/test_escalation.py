import uuid
from datetime import datetime, timezone, timedelta
from app.extensions import db
from app.models.incident import Incident, IncidentStatus, IncidentTriggerSource
from app.models.incident_dispatch import IncidentDispatch, DispatchStatus, DispatchChannel
from app.models.contact import EmergencyContact
from app.models.checkin import CheckIn, CheckInStatus
from app.services.escalation_service import EscalationService
from app.services.sms_service import mock_sms_adapter
from app.services.notification_service import mock_push_adapter


def test_transactional_outbox_processing(db_session):
    mock_sms_adapter.reset()

    # Create test incident and queued dispatch
    inc = Incident(
        client_incident_uuid=str(uuid.uuid4()),
        user_id=1,
        trigger_source=IncidentTriggerSource.MANUAL,
        status=IncidentStatus.ACTIVE
    )
    db_session.add(inc)
    db_session.flush()

    contact = EmergencyContact(user_id=1, name="Primary", phone="+15551234567", priority_tier=1)
    db_session.add(contact)
    db_session.flush()

    dispatch = IncidentDispatch(
        incident_id=inc.id,
        contact_id=contact.id,
        tier=1,
        channel=DispatchChannel.SMS,
        dispatch_status=DispatchStatus.QUEUED,
        message_body="EMERGENCY DISTRESS TEST"
    )
    db_session.add(dispatch)
    db_session.commit()

    # Process outbox
    stats = EscalationService.process_pending_dispatches()
    assert stats['sent'] == 1
    assert stats['failed'] == 0

    # Verify adapter received message with idempotency key
    assert len(mock_sms_adapter.sent_messages) == 1
    assert mock_sms_adapter.sent_messages[0]['to_phone'] == "+15551234567"
    assert "dispatch_" in mock_sms_adapter.sent_messages[0]['idempotency_key']

    # Verify dispatch status in DB is SENT, not DELIVERED
    updated_dispatch = db.session.get(IncidentDispatch, dispatch.id)
    assert updated_dispatch.dispatch_status == DispatchStatus.SENT
    assert updated_dispatch.gateway_message_id is not None
    assert updated_dispatch.sent_at is not None


def test_delivery_receipt_and_acknowledgment(db_session):
    mock_sms_adapter.reset()

    inc = Incident(client_incident_uuid=str(uuid.uuid4()), user_id=1, status=IncidentStatus.ACTIVE)
    db_session.add(inc)
    db_session.flush()

    dispatch = IncidentDispatch(
        incident_id=inc.id,
        tier=1,
        channel=DispatchChannel.SMS,
        dispatch_status=DispatchStatus.QUEUED,
        message_body="TEST"
    )
    db_session.add(dispatch)
    db_session.commit()

    # Process outbox -> SENT
    EscalationService.process_pending_dispatches()
    updated = db.session.get(IncidentDispatch, dispatch.id)
    assert updated.dispatch_status == DispatchStatus.SENT
    gw_id = updated.gateway_message_id

    # Carrier delivery receipt received -> DELIVERED
    success = EscalationService.record_delivery_receipt(gw_id)
    assert success is True
    assert db.session.get(IncidentDispatch, dispatch.id).dispatch_status == DispatchStatus.DELIVERED

    # Contact acknowledges alert with valid token -> ACKNOWLEDGED
    acked = EscalationService.acknowledge_dispatch(dispatch.id, token=dispatch.acknowledgment_token)
    assert acked.dispatch_status == DispatchStatus.ACKNOWLEDGED
    assert acked.acknowledged_at is not None


def test_provider_failure_and_retry_backoff(db_session):
    mock_sms_adapter.reset()
    mock_sms_adapter.should_fail = True

    inc = Incident(client_incident_uuid=str(uuid.uuid4()), user_id=1, status=IncidentStatus.ACTIVE)
    db_session.add(inc)
    db_session.flush()

    dispatch = IncidentDispatch(
        incident_id=inc.id,
        tier=1,
        channel=DispatchChannel.SMS,
        dispatch_status=DispatchStatus.QUEUED,
        message_body="TEST RETRY"
    )
    db_session.add(dispatch)
    db_session.commit()

    # Attempt 1: Fails
    stats1 = EscalationService.process_pending_dispatches()
    assert stats1['failed'] == 1
    d1 = db.session.get(IncidentDispatch, dispatch.id)
    assert d1.retry_count == 1
    assert d1.dispatch_status == DispatchStatus.QUEUED  # Still queued for retry

    # Attempt 2: Fails
    EscalationService.process_pending_dispatches()
    d2 = db.session.get(IncidentDispatch, dispatch.id)
    assert d2.retry_count == 2
    assert d2.dispatch_status == DispatchStatus.QUEUED

    # Attempt 3: Fails and exhausts MAX_RETRIES (3) -> FAILED
    EscalationService.process_pending_dispatches()
    d3 = db.session.get(IncidentDispatch, dispatch.id)
    assert d3.retry_count == 3
    assert d3.dispatch_status == DispatchStatus.FAILED
    assert "Simulated SMS Carrier Gateway Rejection" in d3.failure_reason

    mock_sms_adapter.should_fail = False


def test_cancellation_race_condition_prevents_dispatch(db_session):
    mock_sms_adapter.reset()

    inc = Incident(client_incident_uuid=str(uuid.uuid4()), user_id=1, status=IncidentStatus.ACTIVE)
    db_session.add(inc)
    db_session.flush()

    dispatch = IncidentDispatch(
        incident_id=inc.id,
        tier=1,
        channel=DispatchChannel.SMS,
        dispatch_status=DispatchStatus.QUEUED,
        message_body="DO NOT SEND IF CANCELLED"
    )
    db_session.add(dispatch)
    db_session.commit()

    # User cancels emergency false alarm before background dispatcher runs
    inc.status = IncidentStatus.CANCELLED_FALSE_ALARM
    db_session.commit()

    # Dispatcher runs
    stats = EscalationService.process_pending_dispatches()
    assert stats['cancelled_race'] == 1
    assert stats['sent'] == 0
    assert len(mock_sms_adapter.sent_messages) == 0

    # Dispatch marked FAILED with explanation
    d = db.session.get(IncidentDispatch, dispatch.id)
    assert d.dispatch_status == DispatchStatus.FAILED
    assert "Cancelled by user as false alarm" in d.failure_reason


def test_overdue_checkin_auto_escalation(db_session):
    past_time = datetime.now(timezone.utc) - timedelta(minutes=30)
    
    # Check-in scheduled 30 mins ago, grace period 10 mins, pre-alert 20s
    # Current time is past both grace and pre-alert -> OVERDUE_ESCALATED
    checkin = CheckIn(
        user_id=1,
        title="Late Walk",
        scheduled_for=past_time,
        grace_period_minutes=10,
        pre_alert_seconds=20,
        status=CheckInStatus.SCHEDULED
    )
    db_session.add(checkin)
    db_session.commit()

    # Run auto-escalator
    created_incidents = EscalationService.check_and_escalate_overdue_checkins()
    assert len(created_incidents) == 1
    inc = created_incidents[0]
    assert inc.trigger_source == IncidentTriggerSource.OVERDUE_CHECKIN
    # ARCHITECTURAL SEPARATION: Risk formula genuinely yields 40.0 (w_C=0.40 * 100), not artificially overwritten to 100.0
    assert inc.risk_score_at_trigger == 40.0
    assert inc.status == IncidentStatus.ACTIVE

    # Check-in status in DB updated to OVERDUE_ESCALATED
    updated_c = db.session.get(CheckIn, checkin.id)
    assert updated_c.status == CheckInStatus.OVERDUE_ESCALATED


def test_multi_tier_escalation(db_session):
    inc = Incident(client_incident_uuid=str(uuid.uuid4()), user_id=1, status=IncidentStatus.ACTIVE)
    db_session.add(inc)

    # Setup Tier 2 secondary contact
    sec_contact = EmergencyContact(user_id=1, name="Secondary Guardian", phone="+15559998888", priority_tier=2)
    db_session.add(sec_contact)
    db_session.commit()

    # Escalate to Tier 2
    new_dispatches = EscalationService.escalate_incident_tier(inc.id, target_tier=2, user_id=1)
    assert len(new_dispatches) == 1
    assert new_dispatches[0].tier == 2
    assert new_dispatches[0].contact_id == sec_contact.id
    assert new_dispatches[0].dispatch_status == DispatchStatus.QUEUED


def test_retry_recovery_of_failed_dispatch(db_session):
    mock_sms_adapter.reset()

    inc = Incident(client_incident_uuid=str(uuid.uuid4()), user_id=1, status=IncidentStatus.ACTIVE)
    db_session.add(inc)
    db_session.flush()

    dispatch = IncidentDispatch(
        incident_id=inc.id,
        tier=1,
        channel=DispatchChannel.SMS,
        dispatch_status=DispatchStatus.FAILED,
        message_body="EMERGENCY DISTRESS RETRY TEST",
        retry_count=3,
        failure_reason="Carrier timeout"
    )
    db_session.add(dispatch)
    db_session.commit()

    # Recover failed dispatch
    recovered = EscalationService.retry_failed_dispatch(dispatch.id, user_id=1)
    assert recovered.dispatch_status == DispatchStatus.QUEUED
    assert recovered.retry_count == 0
    assert recovered.failure_reason is None

    # Process outbox again -> Now successfully sent
    stats = EscalationService.process_pending_dispatches()
    assert stats['sent'] == 1
    assert db.session.get(IncidentDispatch, dispatch.id).dispatch_status == DispatchStatus.SENT


def test_unauthorized_acknowledgment_rejected(db_session):
    import pytest
    inc = Incident(client_incident_uuid=str(uuid.uuid4()), user_id=1, status=IncidentStatus.ACTIVE)
    db_session.add(inc)
    db_session.flush()

    dispatch = IncidentDispatch(
        incident_id=inc.id,
        tier=1,
        channel=DispatchChannel.SMS,
        dispatch_status=DispatchStatus.SENT,
        message_body="TEST AUTH"
    )
    db_session.add(dispatch)
    db_session.commit()

    # Attempt acknowledgment with bogus token -> Rejected
    with pytest.raises(PermissionError):
        EscalationService.acknowledge_dispatch(dispatch.id, token="invalid_random_token")

    # Attempt acknowledgment by unassociated user -> Rejected
    with pytest.raises(PermissionError):
        EscalationService.acknowledge_dispatch(dispatch.id, user_id=999)


def test_twilio_carrier_status_callback(db_session):
    inc = Incident(client_incident_uuid=str(uuid.uuid4()), user_id=1, status=IncidentStatus.ACTIVE)
    db_session.add(inc)
    db_session.flush()

    gw_sid = "SM_twilio_verified_sid_123"
    dispatch = IncidentDispatch(
        incident_id=inc.id,
        tier=1,
        channel=DispatchChannel.SMS,
        dispatch_status=DispatchStatus.SENT,
        gateway_message_id=gw_sid,
        message_body="TEST TWILIO DLR"
    )
    db_session.add(dispatch)
    db_session.commit()

    # Twilio reports 'delivered'
    updated = EscalationService.handle_twilio_status_callback(gw_sid, "delivered")
    assert updated is True
    assert db.session.get(IncidentDispatch, dispatch.id).dispatch_status == DispatchStatus.DELIVERED

    # Twilio reports 'undelivered' on another message
    gw_sid2 = "SM_twilio_failed_sid_456"
    dispatch2 = IncidentDispatch(
        incident_id=inc.id,
        tier=1,
        channel=DispatchChannel.SMS,
        dispatch_status=DispatchStatus.SENT,
        gateway_message_id=gw_sid2,
        message_body="TEST TWILIO FAIL"
    )
    db_session.add(dispatch2)
    db_session.commit()

    updated2 = EscalationService.handle_twilio_status_callback(gw_sid2, "undelivered", error_code="30008")
    assert updated2 is True
    d2 = db.session.get(IncidentDispatch, dispatch2.id)
    assert d2.dispatch_status == DispatchStatus.FAILED
    assert "UNDELIVERED" in d2.failure_reason


def test_link_viewed_records_viewed_without_acknowledging(db_session):
    inc = Incident(client_incident_uuid=str(uuid.uuid4()), user_id=1, status=IncidentStatus.ACTIVE)
    db_session.add(inc)
    db_session.flush()

    dispatch = IncidentDispatch(
        incident_id=inc.id,
        tier=1,
        channel=DispatchChannel.SMS,
        dispatch_status=DispatchStatus.DELIVERED,
        gateway_message_id="SM_test_link_view",
        message_body="TEST ALERT"
    )
    db_session.add(dispatch)
    db_session.commit()

    # Step 1: Responder clicks and views link
    viewed_dispatch = EscalationService.record_link_viewed(dispatch.acknowledgment_token)
    assert viewed_dispatch is not None
    assert viewed_dispatch.dispatch_status == DispatchStatus.VIEWED
    assert viewed_dispatch.viewed_at is not None
    # Crucial semantic invariant: Viewing link does NOT acknowledge or assume responsibility!
    assert viewed_dispatch.acknowledged_at is None

    # Step 2: Responder actively confirms assistance by submitting acknowledgment
    acked_dispatch = EscalationService.acknowledge_dispatch(dispatch.id, token=dispatch.acknowledgment_token)
    assert acked_dispatch.dispatch_status == DispatchStatus.ACKNOWLEDGED
    assert acked_dispatch.acknowledged_at is not None


def test_unknown_carrier_status_maps_to_unknown(db_session):
    inc = Incident(client_incident_uuid=str(uuid.uuid4()), user_id=1, status=IncidentStatus.ACTIVE)
    db_session.add(inc)
    db_session.flush()

    gw_sid = "SM_twilio_ambiguous_789"
    dispatch = IncidentDispatch(
        incident_id=inc.id,
        tier=1,
        channel=DispatchChannel.SMS,
        dispatch_status=DispatchStatus.SENT,
        gateway_message_id=gw_sid,
        message_body="TEST AMBIGUOUS"
    )
    db_session.add(dispatch)
    db_session.commit()

    # Unrecognized carrier callback string (e.g. 'partially_delivered' or custom carrier code)
    updated = EscalationService.handle_twilio_status_callback(gw_sid, "partially_delivered")
    assert updated is True
    d = db.session.get(IncidentDispatch, dispatch.id)
    assert d.dispatch_status == DispatchStatus.UNKNOWN
    assert "Ambiguous carrier status" in d.failure_reason


def test_dlr_callback_does_not_revert_acknowledged_status(db_session):
    inc = Incident(client_incident_uuid=str(uuid.uuid4()), user_id=1, status=IncidentStatus.ACTIVE)
    db_session.add(inc)
    db_session.flush()

    gw_sid = "SM_twilio_already_acked"
    dispatch = IncidentDispatch(
        incident_id=inc.id,
        tier=1,
        channel=DispatchChannel.SMS,
        dispatch_status=DispatchStatus.ACKNOWLEDGED,
        gateway_message_id=gw_sid,
        message_body="TEST"
    )
    db_session.add(dispatch)
    db_session.commit()

    # Late arriving delivery callback
    updated = EscalationService.handle_twilio_status_callback(gw_sid, "delivered")
    assert updated is True
    # Invariant: Acknowledged status is not reverted backwards to DELIVERED
    assert db.session.get(IncidentDispatch, dispatch.id).dispatch_status == DispatchStatus.ACKNOWLEDGED


def test_fcm_push_marks_sent_without_claiming_handset_delivery(db_session):
    mock_push_adapter.reset()

    inc = Incident(client_incident_uuid=str(uuid.uuid4()), user_id=1, status=IncidentStatus.ACTIVE)
    db_session.add(inc)
    db_session.flush()

    dispatch = IncidentDispatch(
        incident_id=inc.id,
        tier=1,
        channel=DispatchChannel.PUSH,
        dispatch_status=DispatchStatus.QUEUED,
        message_body="PUSH NOTIFICATION TEST"
    )
    db_session.add(dispatch)
    db_session.commit()

    stats = EscalationService.process_pending_dispatches()
    assert stats['sent'] == 1

    d = db.session.get(IncidentDispatch, dispatch.id)
    # FCM API accepts push for delivery -> SENT (gateway accepted)
    assert d.dispatch_status == DispatchStatus.SENT
    # Invariant: FCM push send does NOT claim handset DELIVERED without device feedback
    assert d.dispatch_status != DispatchStatus.DELIVERED

