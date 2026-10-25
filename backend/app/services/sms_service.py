import os
import uuid
from typing import Tuple, Optional, Dict, Any, List
from flask import current_app


class BaseSMSAdapter:
    """Abstract interface for SMS telecommunication gateways."""
    def send_sms(self, to_phone: str, body: str, idempotency_key: Optional[str] = None) -> Tuple[bool, str, Optional[str]]:
        """
        Sends SMS text message.
        Returns: (success: bool, gateway_message_id: str, error_message: Optional[str])
        """
        raise NotImplementedError


class MockSMSAdapter(BaseSMSAdapter):
    """
    Isolated mock SMS adapter for automated tests.
    Does not require paid Twilio account; tracks sent messages and idempotency keys.
    """
    def __init__(self):
        self.sent_messages: List[Dict[str, Any]] = []
        self.seen_idempotency_keys = set()
        self.should_fail = False
        self.failure_error_message = "Simulated SMS Carrier Gateway Rejection (503 Service Unavailable)"

    def send_sms(self, to_phone: str, body: str, idempotency_key: Optional[str] = None) -> Tuple[bool, str, Optional[str]]:
        if self.should_fail:
            return False, "", self.failure_error_message

        # Idempotency check: if key already processed, return previous msg_id without duplicating send
        if idempotency_key and idempotency_key in self.seen_idempotency_keys:
            return True, f"idempotent_replayed_{idempotency_key}", None

        msg_id = f"mock_sms_{uuid.uuid4().hex[:12]}"
        self.sent_messages.append({
            "gateway_message_id": msg_id,
            "to_phone": to_phone,
            "body": body,
            "idempotency_key": idempotency_key
        })
        if idempotency_key:
            self.seen_idempotency_keys.add(idempotency_key)

        return True, msg_id, None

    def reset(self):
        self.sent_messages.clear()
        self.seen_idempotency_keys.clear()
        self.should_fail = False


class TwilioSMSAdapter(BaseSMSAdapter):
    """
    Production Twilio SMS adapter.
    Reads credentials from environment variables without hardcoded secrets.
    """
    def __init__(self, account_sid: Optional[str] = None, auth_token: Optional[str] = None, from_phone: Optional[str] = None):
        self.account_sid = account_sid or os.getenv('TWILIO_ACCOUNT_SID', '')
        self.auth_token = auth_token or os.getenv('TWILIO_AUTH_TOKEN', '')
        self.from_phone = from_phone or os.getenv('TWILIO_PHONE_NUMBER', '')

    def send_sms(self, to_phone: str, body: str, idempotency_key: Optional[str] = None) -> Tuple[bool, str, Optional[str]]:
        if not self.account_sid or not self.auth_token or not self.from_phone:
            return False, "", "Twilio SMS credentials (ACCOUNT_SID, AUTH_TOKEN, PHONE_NUMBER) not configured in environment."

        try:
            import requests
            url = f"https://api.twilio.com/2010-04-01/Accounts/{self.account_sid}/Messages.json"
            payload = {
                "From": self.from_phone,
                "To": to_phone,
                "Body": body
            }
            # Twilio REST API uses HTTP Basic Auth with AccountSid and AuthToken
            response = requests.post(
                url,
                data=payload,
                auth=(self.account_sid, self.auth_token),
                timeout=10
            )

            if response.status_code in (200, 201):
                resp_json = response.json()
                msg_sid = resp_json.get('sid', f"twilio_{uuid.uuid4().hex[:8]}")
                return True, msg_sid, None
            else:
                err_text = f"Twilio API Error ({response.status_code}): {response.text}"
                return False, "", err_text
        except Exception as e:
            return False, "", f"Twilio dispatch exception: {str(e)}"


# Singleton mock adapter instance for test assertions
mock_sms_adapter = MockSMSAdapter()


class SMSService:
    @classmethod
    def get_adapter(cls) -> BaseSMSAdapter:
        try:
            provider = current_app.config.get('SMS_PROVIDER', 'MOCK').upper() if current_app else 'MOCK'
            if provider == 'TWILIO':
                return TwilioSMSAdapter(
                    account_sid=current_app.config.get('TWILIO_ACCOUNT_SID'),
                    auth_token=current_app.config.get('TWILIO_AUTH_TOKEN'),
                    from_phone=current_app.config.get('TWILIO_PHONE_NUMBER')
                )
        except Exception:
            pass
        return mock_sms_adapter

    @classmethod
    def send(cls, to_phone: str, body: str, idempotency_key: Optional[str] = None) -> Tuple[bool, str, Optional[str]]:
        adapter = cls.get_adapter()
        return adapter.send_sms(to_phone, body, idempotency_key)
