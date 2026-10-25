from datetime import datetime, timezone
from app.services.firebase_service import FirebaseService
from app.models.user import User
from app.models.contact import EmergencyContact
from app.models.checkin import CheckIn, CheckInStatus
from app.models.incident import Incident, IncidentTriggerSource, IncidentStatus


def test_sanitize_payload_removes_sensitive_hashes():
    """Verify passwords and PIN hashes are stripped before syncing to cloud."""
    user_data = {
        "id": 1,
        "uuid": "test-uuid-123",
        "full_name": "Test User",
        "email": "test@lifeguard360.local",
        "password_hash": "scrypt:32768:8:1$secret_hash",
        "created_at": datetime.now(timezone.utc),
    }
    clean = FirebaseService.sanitize_payload('users', user_data)
    assert 'password_hash' not in clean
    assert clean['email'] == "test@lifeguard360.local"
    assert 'synced_to_firebase_at' in clean
    assert isinstance(clean['created_at'], str)

    checkin_data = {
        "id": 10,
        "title": "Evening Walk",
        "safety_pin_hash": "scrypt:pin_hash",
        "status": "SCHEDULED"
    }
    clean_checkin = FirebaseService.sanitize_payload('check_ins', checkin_data)
    assert 'safety_pin_hash' not in clean_checkin
    assert clean_checkin['status'] == "SCHEDULED"


def test_firebase_service_mock_store_and_status(app):
    """Verify storing records in mock/offline mode updates statistics and store."""
    FirebaseService._mock_storage.clear()
    FirebaseService._stats["synced_count"] = 0

    success = FirebaseService.store_record('test_collection', 'doc_1', {
        'title': 'Emergency Alert',
        'level': 'CRITICAL'
    })
    assert success is True
    assert 'test_collection' in FirebaseService._mock_storage
    assert 'doc_1' in FirebaseService._mock_storage['test_collection']
    assert FirebaseService._mock_storage['test_collection']['doc_1']['level'] == 'CRITICAL'

    status = FirebaseService.get_status()
    assert status['mode'] in ['MOCK', 'FIRESTORE', 'REST_RTDB']
    assert status['stats']['synced_count'] >= 1


def test_firebase_status_api_endpoint(client):
    """Verify GET /api/v1/firebase/status returns JSON diagnostic info."""
    res = client.get('/api/v1/firebase/status')
    assert res.status_code == 200
    json_data = res.get_json()
    assert json_data['success'] is True
    assert 'mode' in json_data['data']
    assert 'stats' in json_data['data']


def test_firebase_automatic_commit_sync(client, db_session):
    """Verify that committing a user and contact automatically invokes Firebase sync."""
    FirebaseService._mock_storage.clear()

    # Register user via API (which commits to DB)
    payload = {
        "full_name": "Firebase Test User",
        "email": "firebase.sync@lifeguard360.local",
        "phone": "+1999888777",
        "password": "Password123!",
    }
    res = client.post('/api/v1/auth/register', json=payload)
    assert res.status_code == 201

    # In mock mode, the user should now exist in Firebase mock storage
    assert 'users' in FirebaseService._mock_storage
    stored_users = FirebaseService._mock_storage['users']
    assert len(stored_users) >= 1

    # Verify no password hash is stored in Firebase
    for uid, udata in stored_users.items():
        assert 'password_hash' not in udata
        assert udata['email'] == "firebase.sync@lifeguard360.local"


def test_firebase_sync_all_endpoint(client, authenticated_user):
    """Verify POST /api/v1/firebase/sync-all exports existing database entities."""
    res = client.post('/api/v1/firebase/sync-all')
    assert res.status_code == 200
    json_data = res.get_json()
    assert json_data['success'] is True
    assert 'synced_counts' in json_data['data']
    assert json_data['data']['synced_counts']['users'] >= 1

