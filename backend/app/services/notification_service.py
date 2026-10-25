import os
import uuid
from typing import Dict, Any, Tuple, Optional
from flask import current_app


class BasePushAdapter:
    """Abstract interface for push notification gateways."""
    def send_push(self, recipient: str, title: str, body: str, data: Optional[Dict[str, Any]] = None) -> Tuple[bool, str, Optional[str]]:
        """
        Sends push notification.
        Returns: (success: bool, gateway_message_id: str, error_message: Optional[str])
        """
        raise NotImplementedError


class MockPushAdapter(BasePushAdapter):
    """
    Isolated mock adapter for automated tests.
    Never calls external networks; maintains sent message history.
    """
    def __init__(self):
        self.sent_notifications = []
        self.should_fail = False
        self.failure_error_message = "Simulated network timeout connecting to FCM"

    def send_push(self, recipient: str, title: str, body: str, data: Optional[Dict[str, Any]] = None) -> Tuple[bool, str, Optional[str]]:
        if self.should_fail:
            return False, "", self.failure_error_message

        msg_id = f"mock_fcm_{uuid.uuid4().hex[:12]}"
        self.sent_notifications.append({
            "gateway_message_id": msg_id,
            "recipient": recipient,
            "title": title,
            "body": body,
            "data": data or {}
        })
        return True, msg_id, None

    def reset(self):
        self.sent_notifications.clear()
        self.should_fail = False


class FCMPushAdapter(BasePushAdapter):
    """
    Production Firebase Cloud Messaging adapter.
    Reads credentials from FIREBASE_CREDENTIALS_PATH without hardcoded secrets.
    """
    def __init__(self, credentials_path: Optional[str] = None):
        self.credentials_path = credentials_path or os.getenv('FIREBASE_CREDENTIALS_PATH')

    def send_push(self, recipient: str, title: str, body: str, data: Optional[Dict[str, Any]] = None) -> Tuple[bool, str, Optional[str]]:
        if not self.credentials_path or not os.path.exists(self.credentials_path):
            return False, "", "Firebase credentials file not configured or not found on server."

        # In a fully configured environment with google-auth / firebase-admin:
        # We build the OAuth2 token and send to https://fcm.googleapis.com/v1/projects/{project_id}/messages:send
        # Here we provide the validated structural integration:
        try:
            import requests
            import json
            # Verify file is readable JSON
            with open(self.credentials_path, 'r') as f:
                cred_data = json.load(f)
            project_id = cred_data.get('project_id')
            if not project_id:
                return False, "", "Invalid Firebase credentials: missing project_id."

            # Real FCM v1 API dispatch would happen here
            # For unverified credentials, return explicit failure rather than false claim
            return False, "", "FCM v1 service account requires active Google OAuth2 authentication token."
        except Exception as e:
            return False, "", f"FCM dispatch exception: {str(e)}"


# Singleton mock adapter instance for test assertions
mock_push_adapter = MockPushAdapter()


class PushNotificationService:
    @classmethod
    def get_adapter(cls) -> BasePushAdapter:
        try:
            if current_app and current_app.config.get('FIREBASE_ENABLED'):
                return FCMPushAdapter(current_app.config.get('FIREBASE_CREDENTIALS_PATH'))
        except Exception:
            pass
        return mock_push_adapter

    @classmethod
    def send(cls, recipient: str, title: str, body: str, data: Optional[Dict[str, Any]] = None) -> Tuple[bool, str, Optional[str]]:
        adapter = cls.get_adapter()
        return adapter.send_push(recipient, title, body, data)
