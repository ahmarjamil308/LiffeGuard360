import uuid
from app.models.incident import Incident
from app.models.incident_dispatch import IncidentDispatch


def test_manual_sos_immediate_dispatch_and_risk_bypass(client, authenticated_user):
    headers = authenticated_user['headers']

    # Set up a Tier 1 contact first
    client.post('/api/v1/contacts', headers=headers, json={
        "name": "Emergency Contact",
        "phone": "+12025550188",
        "priority_tier": 1
    })

    # Trigger manual SOS with risk_score = 0.0 (Manual SOS MUST bypass risk verification!)
    payload = {
        "client_incident_uuid": str(uuid.uuid4()),
        "trigger_source": "MANUAL",
        "risk_score_at_trigger": 0.0,
        "latitude": 34.0522,
        "longitude": -118.2437,
        "accuracy": 12.5
    }
    res = client.post('/api/v1/sos/trigger', headers=headers, json=payload)
    assert res.status_code == 201
    body = res.get_json()['data']
    
    assert body['bypass_risk_verified'] is True
    assert body['is_new_incident'] is True
    assert body['incident']['status'] == "ACTIVE"
    assert len(body['incident']['dispatches']) >= 1
    assert body['incident']['dispatches'][0]['dispatch_status'] == "SENT"


def test_sos_idempotency_prevents_duplicate_incidents_and_dispatches(client, authenticated_user):
    headers = authenticated_user['headers']
    test_uuid = str(uuid.uuid4())

    payload = {
        "client_incident_uuid": test_uuid,
        "trigger_source": "MANUAL",
        "latitude": 40.7128,
        "longitude": -74.0060,
    }

    # First attempt: New incident created
    res1 = client.post('/api/v1/sos/trigger', headers=headers, json=payload)
    assert res1.status_code == 201
    incident_id1 = res1.get_json()['data']['incident']['id']

    # Second attempt with IDENTICAL client_incident_uuid (simulating network retry)
    res2 = client.post('/api/v1/sos/trigger', headers=headers, json=payload)
    assert res2.status_code == 200
    assert res2.get_json()['data']['is_new_incident'] is False
    assert res2.get_json()['data']['incident']['id'] == incident_id1

    # Database verification: Exactly 1 incident exists with this UUID
    incidents = Incident.query.filter_by(client_incident_uuid=test_uuid).all()
    assert len(incidents) == 1


def test_offline_sos_batch_sync_idempotency(client, authenticated_user):
    headers = authenticated_user['headers']
    uuid1 = str(uuid.uuid4())
    uuid2 = str(uuid.uuid4())

    batch_payload = {
        "incidents": [
            {
                "client_incident_uuid": uuid1,
                "trigger_source": "MANUAL",
                "latitude": 51.5074,
                "longitude": -0.1278,
                "triggered_at": "2026-10-21T14:00:00Z"
            },
            {
                "client_incident_uuid": uuid2,
                "trigger_source": "MANUAL",
                "latitude": 51.5080,
                "longitude": -0.1280,
                "triggered_at": "2026-10-21T14:05:00Z"
            }
        ]
    }

    # Initial sync
    sync_res1 = client.post('/api/v1/sos/sync', headers=headers, json=batch_payload)
    assert sync_res1.status_code == 200
    results1 = sync_res1.get_json()['data']['synced_incidents']
    assert len(results1) == 2
    assert results1[0]['is_duplicate_ignored'] is False
    assert results1[1]['is_duplicate_ignored'] is False

    # Retry sync with the same items -> Must ignore duplicates without error
    sync_res2 = client.post('/api/v1/sos/sync', headers=headers, json=batch_payload)
    assert sync_res2.status_code == 200
    results2 = sync_res2.get_json()['data']['synced_incidents']
    assert len(results2) == 2
    assert results2[0]['is_duplicate_ignored'] is True
    assert results2[1]['is_duplicate_ignored'] is True


def test_sos_cancellation_false_alarm(client, authenticated_user):
    headers = authenticated_user['headers']

    # Trigger SOS
    res = client.post('/api/v1/sos/trigger', headers=headers, json={
        "trigger_source": "MANUAL"
    })
    incident_id = res.get_json()['data']['incident']['id']

    # Cancel as false alarm
    cancel_res = client.post('/api/v1/sos/cancel', headers=headers, json={
        "incident_id": incident_id,
        "reason": "Accidental pocket trigger while bicycling"
    })
    assert cancel_res.status_code == 200
    inc = cancel_res.get_json()['data']['incident']
    assert inc['status'] == "CANCELLED_FALSE_ALARM"
    assert inc['false_alarm_reason'] == "Accidental pocket trigger while bicycling"


def test_concurrent_sos_trigger_idempotency(client, authenticated_user):
    import concurrent.futures

    headers = authenticated_user['headers']
    shared_uuid = str(uuid.uuid4())
    payload = {
        "client_incident_uuid": shared_uuid,
        "trigger_source": "MANUAL",
        "latitude": 37.7749,
        "longitude": -122.4194
    }

    # Execute 5 concurrent trigger requests simultaneously with identical client_incident_uuid
    def send_request():
        return client.post('/api/v1/sos/trigger', headers=headers, json=payload)

    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
        futures = [executor.submit(send_request) for _ in range(5)]
        responses = [f.result() for f in futures]

    # All responses must be successful (either 201 for the winner or 200 for idempotent replayers)
    status_codes = [r.status_code for r in responses]
    for sc in status_codes:
        assert sc in [200, 201]

    # Exactly one request must be marked as new
    new_flags = [r.get_json()['data']['is_new_incident'] for r in responses]
    assert new_flags.count(True) == 1
    assert new_flags.count(False) == 4

    # Assert database contains exactly one record for this UUID
    incidents = Incident.query.filter_by(client_incident_uuid=shared_uuid).all()
    assert len(incidents) == 1

