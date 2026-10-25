import pytest
from app import create_app
from app.extensions import db
from app.models.user import User


@pytest.fixture(scope='session')
def app():
    """Create Flask application in testing mode."""
    _app = create_app('testing')
    with _app.app_context():
        yield _app


@pytest.fixture(scope='function')
def client(app):
    """Test client with isolated per-test database."""
    with app.app_context():
        db.create_all()
        yield app.test_client()
        db.session.remove()
        db.drop_all()


@pytest.fixture(scope='function')
def db_session(app):
    """Direct database session fixture with fresh tables."""
    with app.app_context():
        db.create_all()
        yield db.session
        db.session.remove()
        db.drop_all()


@pytest.fixture(scope='function')
def authenticated_user(client):
    """Registers and authenticates a user, returning user data and Bearer token."""
    user_payload = {
        "full_name": "Test Safety User",
        "email": "safety.user@lifeguard360.local",
        "phone": "+12025550199",
        "password": "SecurePassword123!",
        "blood_group": "O+",
        "default_emergency_number": "911"
    }
    res = client.post('/api/v1/auth/register', json=user_payload)
    data = res.get_json()['data']
    access_token = data['tokens']['access_token']
    return {
        "user": data['user'],
        "token": access_token,
        "headers": {"Authorization": f"Bearer {access_token}"}
    }
