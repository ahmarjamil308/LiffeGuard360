import os
from datetime import timedelta
from dotenv import load_dotenv

# Load environment variables from .env if present
basedir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
dotenv_path = os.path.join(basedir, '.env')
if os.path.exists(dotenv_path):
    load_dotenv(dotenv_path)


class BaseConfig:
    """Base application configuration with security defaults."""
    SECRET_KEY = os.getenv('SECRET_KEY', 'default_dev_secret_key_change_in_prod')
    JWT_SECRET_KEY = os.getenv('JWT_SECRET_KEY', 'default_jwt_secret_key_change_in_prod')
    
    JWT_ACCESS_TOKEN_EXPIRES = timedelta(
        minutes=int(os.getenv('JWT_ACCESS_TOKEN_EXPIRES_MINUTES', 60))
    )
    JWT_REFRESH_TOKEN_EXPIRES = timedelta(
        days=int(os.getenv('JWT_REFRESH_TOKEN_EXPIRES_DAYS', 30))
    )

    SQLALCHEMY_TRACK_MODIFICATIONS = False
    
    # Safety Check-in and Escalation Defaults
    DEFAULT_CHECKIN_GRACE_PERIOD_MINUTES = int(os.getenv('DEFAULT_CHECKIN_GRACE_PERIOD_MINUTES', 10))
    DEFAULT_PRE_ALERT_COUNTDOWN_SECONDS = int(os.getenv('DEFAULT_PRE_ALERT_COUNTDOWN_SECONDS', 20))
    MIN_CHECKIN_GRACE_PERIOD_MINUTES = int(os.getenv('MIN_CHECKIN_GRACE_PERIOD_MINUTES', 1))
    MAX_CHECKIN_GRACE_PERIOD_MINUTES = int(os.getenv('MAX_CHECKIN_GRACE_PERIOD_MINUTES', 60))
    MIN_PRE_ALERT_COUNTDOWN_SECONDS = 10
    MAX_PRE_ALERT_COUNTDOWN_SECONDS = 45

    # Country & Emergency defaults
    DEFAULT_COUNTRY_CODE = os.getenv('DEFAULT_COUNTRY_CODE', 'US')
    DEFAULT_EMERGENCY_NUMBER = os.getenv('DEFAULT_EMERGENCY_NUMBER', '911')

    # External provider flags
    FIREBASE_ENABLED = os.getenv('FIREBASE_ENABLED', 'False').lower() in ('true', '1', 't')
    FIREBASE_CREDENTIALS_PATH = os.getenv('FIREBASE_CREDENTIALS_PATH', None)
    FIREBASE_PROJECT_ID = os.getenv('FIREBASE_PROJECT_ID', '')
    FIREBASE_DATABASE_URL = os.getenv('FIREBASE_DATABASE_URL', '')
    FIREBASE_SYNC_MODE = os.getenv('FIREBASE_SYNC_MODE', 'AUTO')
    SMS_PROVIDER = os.getenv('SMS_PROVIDER', 'MOCK')
    TWILIO_ACCOUNT_SID = os.getenv('TWILIO_ACCOUNT_SID', '')
    TWILIO_AUTH_TOKEN = os.getenv('TWILIO_AUTH_TOKEN', '')
    TWILIO_PHONE_NUMBER = os.getenv('TWILIO_PHONE_NUMBER', '')


class DevelopmentConfig(BaseConfig):
    """Development configuration using MySQL persistent storage."""
    DEBUG = True
    SQLALCHEMY_DATABASE_URI = os.getenv(
        'DATABASE_URL',
        'mysql+pymysql://lifeguard_user:your_secure_password@localhost:3306/lifeguard360'
    )


class TestingConfig(BaseConfig):
    """Isolated in-memory testing configuration."""
    TESTING = True
    DEBUG = False
    # Use SQLite in-memory database with StaticPool for thread-safe isolated testing
    SQLALCHEMY_DATABASE_URI = 'sqlite:///:memory:'
    from sqlalchemy.pool import StaticPool
    SQLALCHEMY_ENGINE_OPTIONS = {
        'connect_args': {'check_same_thread': False},
        'poolclass': StaticPool
    }
    JWT_ACCESS_TOKEN_EXPIRES = timedelta(minutes=5)
    SMS_PROVIDER = 'MOCK'
    FIREBASE_ENABLED = False


class ProductionConfig(BaseConfig):
    """Production configuration with strict checks."""
    DEBUG = False
    TESTING = False
    SQLALCHEMY_DATABASE_URI = os.getenv('DATABASE_URL')


config_by_name = {
    'development': DevelopmentConfig,
    'testing': TestingConfig,
    'production': ProductionConfig,
    'default': DevelopmentConfig,
}
