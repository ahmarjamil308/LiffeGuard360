import os
from flask import Flask
from marshmallow import ValidationError

from app.config import config_by_name
from app.extensions import db, migrate, jwt, cors
from app.utils.responses import error_response, success_response


def create_app(config_name=None):
    """Application factory for LifeGuard 360 backend."""
    if config_name is None:
        config_name = os.getenv('FLASK_ENV', 'development')

    app = Flask(__name__)
    app.config.from_object(config_by_name.get(config_name, config_by_name['default']))

    # Initialize extensions
    db.init_app(app)
    migrate.init_app(app, db)
    jwt.init_app(app)
    cors.init_app(
        app,
        resources={r"/api/*": {
            "origins": "*",
            "methods": ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
            "allow_headers": ["Content-Type", "Authorization", "X-Requested-With"]
        }}
    )

    # JWT Error Handlers
    @jwt.unauthorized_loader
    def unauthorized_callback(callback):
        return error_response("Missing or invalid authorization token", status_code=401)

    @jwt.expired_token_loader
    def expired_token_callback(jwt_header, jwt_payload):
        return error_response("Authorization token has expired", status_code=401)

    @jwt.invalid_token_loader
    def invalid_token_callback(callback):
        return error_response("Invalid authorization token", status_code=401)

    # General Error Handlers
    @app.errorhandler(ValidationError)
    def handle_validation_error(e):
        return error_response("Validation error", errors=e.messages, status_code=422)

    @app.errorhandler(404)
    def handle_not_found(e):
        return error_response("Resource not found", status_code=404)

    @app.errorhandler(500)
    def handle_internal_error(e):
        return error_response("An internal server error occurred", status_code=500)

    # Root & Health Check Endpoints
    @app.route('/', methods=['GET'])
    def root():
        return success_response(
            data={
                "service": "LifeGuard 360 Backend API",
                "version": "1.0.0",
                "health": "/api/health",
                "api_base": "/api/v1"
            },
            message="LifeGuard 360 API server is running"
        )

    @app.route('/api/health', methods=['GET'])
    def health_check():
        return success_response(
            data={
                "status": "healthy",
                "service": "LifeGuard 360 Backend",
                "version": "1.0.0"
            },
            message="LifeGuard 360 API is operational"
        )

    # Initialize Firebase Cloud Data Sync
    from app.services.firebase_service import FirebaseService
    from app.services.firebase_listener import register_firebase_event_listeners
    FirebaseService.init_app(app)
    register_firebase_event_listeners(app)

    # Register Blueprints
    from app.blueprints.auth import auth_bp
    from app.blueprints.contacts import contacts_bp
    from app.blueprints.checkin import checkin_bp
    from app.blueprints.sos import sos_bp
    from app.blueprints.risk import risk_bp
    from app.blueprints.logs import logs_bp
    from app.blueprints.firebase import firebase_bp

    app.register_blueprint(auth_bp)
    app.register_blueprint(contacts_bp)
    app.register_blueprint(checkin_bp)
    app.register_blueprint(sos_bp)
    app.register_blueprint(risk_bp)
    app.register_blueprint(logs_bp)
    app.register_blueprint(firebase_bp)

    # CLI Commands for Background Workers & Cron
    @app.cli.command('escalate-checkins')
    def escalate_checkins_command():
        """Single-shot evaluation of overdue check-ins and outbox dispatches (for cron)."""
        from app.services.escalation_service import EscalationService
        escalated = EscalationService.check_and_escalate_overdue_checkins()
        stats = EscalationService.process_pending_dispatches()
        print(f"Escalation complete: {len(escalated)} overdue check-in(s) escalated, {stats['sent']} dispatch(es) sent.")

    @app.cli.command('sync-firebase')
    def sync_firebase_command():
        """Exports all local database records (users, contacts, incidents, logs) to Firebase."""
        result = FirebaseService.sync_all_database_records()
        print(f"Firebase sync complete: {result['total_synced']} record(s) synced in {result['mode']} mode.")
        for col, count in result['synced_counts'].items():
            print(f"  - {col}: {count}")

    return app
