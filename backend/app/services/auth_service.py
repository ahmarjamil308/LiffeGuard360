from flask_jwt_extended import create_access_token, create_refresh_token
from app.extensions import db
from app.models.user import User
from app.services.audit_service import AuditService


class AuthService:
    @staticmethod
    def register_user(data: dict) -> tuple[User, str, str]:
        """Registers a new user and returns (user, access_token, refresh_token)."""
        email = data['email'].strip().lower()
        phone = data['phone'].strip()

        if User.query.filter_by(email=email).first():
            raise ValueError("An account with this email address already exists.")
        if User.query.filter_by(phone=phone).first():
            raise ValueError("An account with this phone number already exists.")

        user = User(
            full_name=data['full_name'].strip(),
            email=email,
            phone=phone,
            blood_group=data.get('blood_group'),
            default_emergency_number=data.get('default_emergency_number', '911'),
        )
        user.set_password(data['password'])
        db.session.add(user)
        db.session.commit()

        # Audit log
        AuditService.log_event(
            user_id=user.id,
            event_type='USER_REGISTERED',
            action_description=f"New user registered: {user.email}"
        )

        identity = str(user.id)
        access_token = create_access_token(identity=identity)
        refresh_token = create_refresh_token(identity=identity)
        return user, access_token, refresh_token

    @staticmethod
    def authenticate_user(email_or_phone: str, password: str) -> tuple[User, str, str]:
        """Authenticates user via email or phone and returns (user, access_token, refresh_token)."""
        identifier = email_or_phone.strip()
        user = User.query.filter(
            (User.email == identifier.lower()) | (User.phone == identifier)
        ).first()

        if not user or not user.verify_password(password):
            AuditService.log_event(
                user_id=user.id if user else None,
                event_type='AUTH_FAILED',
                action_description=f"Failed login attempt for identifier: {identifier}"
            )
            raise ValueError("Invalid email/phone or password.")

        if not user.is_active:
            raise ValueError("User account is deactivated. Please contact support.")

        AuditService.log_event(
            user_id=user.id,
            event_type='AUTH_SUCCESS',
            action_description=f"User successfully logged in: {user.email}"
        )

        identity = str(user.id)
        access_token = create_access_token(identity=identity)
        refresh_token = create_refresh_token(identity=identity)
        return user, access_token, refresh_token

    @staticmethod
    def get_profile(user_id: int) -> User:
        user = db.session.get(User, user_id)
        if not user:
            raise ValueError("User not found.")
        return user

    @staticmethod
    def update_profile(user_id: int, data: dict) -> User:
        user = db.session.get(User, user_id)
        if not user:
            raise ValueError("User not found.")

        for field in [
            'full_name', 'blood_group', 'allergies', 'medical_notes',
            'emergency_notes', 'default_emergency_number',
            'checkin_grace_period_minutes', 'pre_alert_countdown_seconds'
        ]:
            if field in data and data[field] is not None:
                setattr(user, field, data[field])

        db.session.commit()
        AuditService.log_event(
            user_id=user.id,
            event_type='PROFILE_UPDATED',
            action_description="User emergency profile updated"
        )
        return user
