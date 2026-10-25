"""
LifeGuard 360 - Automatic Database to Firebase Event Synchronizer

Listens to SQLAlchemy session commit lifecycle and automatically replicates
all committed entity insertions, updates, and deletions to Firebase.
"""

import logging
from sqlalchemy import event
from app.extensions import db
from app.services.firebase_service import FirebaseService

logger = logging.getLogger('LifeGuardFirebase')

_MODEL_TO_SYNC_MAP = {
    'User': FirebaseService.sync_user,
    'EmergencyContact': FirebaseService.sync_contact,
    'CheckIn': FirebaseService.sync_checkin,
    'Incident': FirebaseService.sync_incident,
    'IncidentDispatch': FirebaseService.sync_dispatch,
    'SensorTelemetry': FirebaseService.sync_telemetry,
    'RiskAssessment': FirebaseService.sync_risk_assessment,
    'AuditLog': FirebaseService.sync_audit_log,
}


def register_firebase_event_listeners(app):
    """Binds SQLAlchemy commit lifecycle to Firebase replication."""

    @event.listens_for(db.session, 'before_commit')
    def before_commit_capture(session):
        pending = []

        # 1. New records
        for obj in list(session.new):
            cls_name = obj.__class__.__name__
            if cls_name in _MODEL_TO_SYNC_MAP:
                pending.append(('save', cls_name, obj))

        # 2. Updated records
        for obj in list(session.dirty):
            cls_name = obj.__class__.__name__
            if cls_name in _MODEL_TO_SYNC_MAP:
                pending.append(('save', cls_name, obj))

        # 3. Deleted records (capture ID before deletion commit)
        for obj in list(session.deleted):
            cls_name = obj.__class__.__name__
            if cls_name == 'EmergencyContact':
                pending.append(('delete_contact', cls_name, getattr(obj, 'id', None)))

        session.info['pending_firebase_sync'] = pending

    @event.listens_for(db.session, 'after_commit')
    def after_commit_dispatch(session):
        pending = session.info.pop('pending_firebase_sync', [])
        for action, cls_name, target in pending:
            try:
                if action == 'save':
                    sync_func = _MODEL_TO_SYNC_MAP.get(cls_name)
                    if sync_func:
                        sync_func(target)
                elif action == 'delete_contact' and target is not None:
                    FirebaseService.delete_contact(target)
            except Exception as e:
                logger.warning(f"Error during Firebase automatic replication for {cls_name}: {e}")

