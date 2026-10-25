from app.extensions import db
from app.models.audit_log import AuditLog


class AuditService:
    @staticmethod
    def log_event(event_type: str, action_description: str, user_id=None, metadata=None, ip_address=None, user_agent=None) -> AuditLog:
        """Create and persist an immutable audit log record."""
        log = AuditLog(
            user_id=user_id,
            event_type=event_type,
            action_description=action_description,
            event_metadata_json=metadata or {},
            ip_address=ip_address,
            user_agent=user_agent
        )
        db.session.add(log)
        try:
            db.session.commit()
        except Exception:
            db.session.rollback()
        return log
