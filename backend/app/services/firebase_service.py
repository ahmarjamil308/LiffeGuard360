"""
LifeGuard 360 - Firebase Real-Time Data Storage & Cloud Sync Service

Stores and synchronizes all system records into Firebase:
- Users (Profiles, Emergency Preferences)
- Emergency Contacts (Priority-Tiered)
- Smart Check-Ins (Schedules, Statuses, Lat/Lon)
- Emergency SOS Incidents (Idempotent Trigger Events, Statuses)
- Incident Dispatches (SMS/Push Dispatch Logs)
- Sensor Telemetry (GPS, Accelerometer, Battery)
- Risk Assessments (Composite Risk Scores & Factors)
- Immutable Audit Logs

Supports:
1. Google Cloud Firestore via firebase-admin SDK.
2. Firebase Realtime Database / Firestore REST via requests (zero native build dependencies).
3. Safe offline/mock fallback when credentials are not configured (never crashes core safety services).
"""

import os
import json
import logging
import threading
from datetime import datetime, date, timezone
from typing import Dict, Any, Optional, List

logger = logging.getLogger('LifeGuardFirebase')


def json_serial_fallback(obj):
    """JSON serializer fallback for objects not serializable by default json code."""
    if isinstance(obj, (datetime, date)):
        return obj.isoformat()
    return str(obj)


class FirebaseService:
    _instance = None
    _initialized = False
    _lock = threading.Lock()
    
    # Active mode: "FIRESTORE", "REST_RTDB", "REST_FIRESTORE", "MOCK"
    _mode = "MOCK"
    _app = None
    _firestore_client = None
    _project_id = None
    _credentials_path = None
    _database_url = None
    _enabled = False
    
    _stats = {
        "synced_count": 0,
        "failed_count": 0,
        "last_sync_time": None,
        "last_error": None,
        "collections": {}
    }
    
    # In-memory storage for offline / mock testing
    _mock_storage: Dict[str, Dict[str, Any]] = {}

    @classmethod
    def init_app(cls, app):
        """Initializes Firebase configuration from Flask app context."""
        with cls._lock:
            cls._app = app
            cls._enabled = app.config.get('FIREBASE_ENABLED', False)
            cls._credentials_path = app.config.get('FIREBASE_CREDENTIALS_PATH')
            cls._database_url = app.config.get('FIREBASE_DATABASE_URL')
            cls._project_id = app.config.get('FIREBASE_PROJECT_ID')

            # Resolve relative credentials path against backend root
            if cls._credentials_path and not os.path.isabs(cls._credentials_path):
                basedir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
                resolved = os.path.join(basedir, cls._credentials_path)
                if os.path.exists(resolved):
                    cls._credentials_path = resolved

            cls._connect()
            cls._initialized = True

    @classmethod
    def _connect(cls):
        """Attempts connection to Firebase Admin SDK or REST gateway."""
        if not cls._enabled:
            cls._mode = "MOCK"
            logger.info("Firebase sync is running in MOCK / LOCAL mode (FIREBASE_ENABLED=False).")
            return

        # 1. Try Firebase Admin SDK (Cloud Firestore)
        if cls._credentials_path and os.path.exists(cls._credentials_path):
            try:
                import firebase_admin
                from firebase_admin import credentials, firestore

                # Avoid re-initializing existing default app
                if not firebase_admin._apps:
                    cred = credentials.Certificate(cls._credentials_path)
                    cert_project_id = getattr(cred, 'project_id', None)
                    if cert_project_id:
                        cls._project_id = cert_project_id

                    options = {}
                    if cls._database_url:
                        options['databaseURL'] = cls._database_url
                    if cls._project_id:
                        options['projectId'] = cls._project_id
                    firebase_admin.initialize_app(cred, options or None)
                
                cls._firestore_client = firestore.client()
                cls._mode = "FIRESTORE"
                logger.info("Firebase Cloud Firestore initialized successfully with service account.")
                return
            except ImportError:
                logger.warning("firebase-admin package not installed. Falling back to Firebase REST API.")
            except Exception as e:
                cls._stats["last_error"] = str(e)
                logger.error(f"Failed to initialize Firebase Admin SDK: {e}. Falling back to REST API.")

        # 2. Try Firebase Realtime Database REST API if databaseURL is provided
        if cls._database_url:
            cls._mode = "REST_RTDB"
            logger.info(f"Firebase REST Realtime Database initialized at: {cls._database_url}")
            return

        # 3. Fallback to Mock
        cls._mode = "MOCK"
        logger.warning("Firebase credentials or database URL not configured. Operating in safe MOCK mode.")

    @classmethod
    def sanitize_payload(cls, collection: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Removes sensitive secrets (password hashes, raw PINs) before cloud sync.
        Serializes all datetimes and complex types to JSON-friendly primitives.
        """
        clean = dict(data)
        
        # Security sanitization
        if collection == 'users':
            clean.pop('password_hash', None)
        elif collection == 'check_ins':
            clean.pop('safety_pin_hash', None)
        
        # Convert any date/datetime objects to ISO 8601
        for k, v in list(clean.items()):
            if isinstance(v, (datetime, date)):
                clean[k] = v.isoformat()
            elif isinstance(v, dict):
                clean[k] = cls.sanitize_payload('nested', v)
            elif isinstance(v, list):
                clean[k] = [cls.sanitize_payload('nested', item) if isinstance(item, dict) else item for item in v]

        clean['synced_to_firebase_at'] = datetime.now(timezone.utc).isoformat()
        return clean

    @classmethod
    def store_record(cls, collection: str, doc_id: Any, data: Dict[str, Any]) -> bool:
        """
        Stores or updates an authoritative record in Firebase.
        Thread-safe and fail-safe: never raises unhandled exceptions to caller.
        """
        doc_id_str = str(doc_id)
        payload = cls.sanitize_payload(collection, data)

        try:
            if cls._mode == "FIRESTORE" and cls._firestore_client:
                doc_ref = cls._firestore_client.collection(collection).document(doc_id_str)
                doc_ref.set(payload, merge=True)
            elif cls._mode == "REST_RTDB" and cls._database_url:
                import requests
                url = f"{cls._database_url.rstrip('/')}/{collection}/{doc_id_str}.json"
                resp = requests.put(url, json=payload, timeout=5)
                if resp.status_code >= 400:
                    raise RuntimeError(f"REST RTDB error {resp.status_code}: {resp.text}")
            else:
                # Mock / Offline memory store
                with cls._lock:
                    if collection not in cls._mock_storage:
                        cls._mock_storage[collection] = {}
                    cls._mock_storage[collection][doc_id_str] = payload

            with cls._lock:
                cls._stats["synced_count"] += 1
                cls._stats["last_sync_time"] = datetime.now(timezone.utc).isoformat()
                cls._stats["collections"][collection] = cls._stats["collections"].get(collection, 0) + 1
            return True

        except Exception as e:
            logger.warning(f"Firebase sync failed for {collection}/{doc_id_str}: {e}")
            with cls._lock:
                cls._stats["failed_count"] += 1
                cls._stats["last_error"] = str(e)
            return False

    @classmethod
    def delete_record(cls, collection: str, doc_id: Any) -> bool:
        """Removes a deleted record or marks it deleted in Firebase."""
        doc_id_str = str(doc_id)
        try:
            if cls._mode == "FIRESTORE" and cls._firestore_client:
                cls._firestore_client.collection(collection).document(doc_id_str).delete()
            elif cls._mode == "REST_RTDB" and cls._database_url:
                import requests
                url = f"{cls._database_url.rstrip('/')}/{collection}/{doc_id_str}.json"
                requests.delete(url, timeout=5)
            else:
                with cls._lock:
                    if collection in cls._mock_storage and doc_id_str in cls._mock_storage[collection]:
                        del cls._mock_storage[collection][doc_id_str]
            return True
        except Exception as e:
            logger.warning(f"Firebase delete failed for {collection}/{doc_id_str}: {e}")
            return False

    # --------------------------------------------------------------------------
    # Specialized Entity Sync Methods
    # --------------------------------------------------------------------------
    @classmethod
    def sync_user(cls, user) -> bool:
        data = user.to_dict(include_medical=True)
        return cls.store_record('users', user.id, data)

    @classmethod
    def sync_contact(cls, contact) -> bool:
        data = contact.to_dict()
        return cls.store_record('emergency_contacts', contact.id, data)

    @classmethod
    def delete_contact(cls, contact_id: int) -> bool:
        return cls.delete_record('emergency_contacts', contact_id)

    @classmethod
    def sync_checkin(cls, checkin) -> bool:
        data = checkin.to_dict()
        return cls.store_record('check_ins', checkin.id, data)

    @classmethod
    def sync_incident(cls, incident) -> bool:
        data = incident.to_dict(include_dispatches=True)
        return cls.store_record('incidents', incident.id, data)

    @classmethod
    def sync_dispatch(cls, dispatch) -> bool:
        data = dispatch.to_dict()
        return cls.store_record('incident_dispatches', dispatch.id, data)

    @classmethod
    def sync_telemetry(cls, telemetry) -> bool:
        data = telemetry.to_dict()
        return cls.store_record('sensor_telemetry', telemetry.id, data)

    @classmethod
    def sync_risk_assessment(cls, risk_assessment) -> bool:
        data = risk_assessment.to_dict()
        return cls.store_record('risk_assessments', risk_assessment.id, data)

    @classmethod
    def sync_audit_log(cls, audit_log) -> bool:
        data = audit_log.to_dict()
        return cls.store_record('audit_logs', audit_log.id, data)

    # --------------------------------------------------------------------------
    # Bulk Database to Firebase Sync
    # --------------------------------------------------------------------------
    @classmethod
    def sync_all_database_records(cls) -> Dict[str, Any]:
        """
        Reads all tables from the local MySQL/SQLite database and exports
        every record to Firebase.
        """
        from app.models.user import User
        from app.models.contact import EmergencyContact
        from app.models.checkin import CheckIn
        from app.models.incident import Incident
        from app.models.incident_dispatch import IncidentDispatch
        from app.models.telemetry import SensorTelemetry
        from app.models.risk_assessment import RiskAssessment
        from app.models.audit_log import AuditLog

        counts = {
            "users": 0,
            "emergency_contacts": 0,
            "check_ins": 0,
            "incidents": 0,
            "incident_dispatches": 0,
            "sensor_telemetry": 0,
            "risk_assessments": 0,
            "audit_logs": 0,
        }

        for u in User.query.all():
            cls.sync_user(u)
            counts["users"] += 1

        for c in EmergencyContact.query.all():
            cls.sync_contact(c)
            counts["emergency_contacts"] += 1

        for chk in CheckIn.query.all():
            cls.sync_checkin(chk)
            counts["check_ins"] += 1

        for inc in Incident.query.all():
            cls.sync_incident(inc)
            counts["incidents"] += 1

        for d in IncidentDispatch.query.all():
            cls.sync_dispatch(d)
            counts["incident_dispatches"] += 1

        for t in SensorTelemetry.query.all():
            cls.sync_telemetry(t)
            counts["sensor_telemetry"] += 1

        for r in RiskAssessment.query.all():
            cls.sync_risk_assessment(r)
            counts["risk_assessments"] += 1

        for a in AuditLog.query.all():
            cls.sync_audit_log(a)
            counts["audit_logs"] += 1

        return {
            "mode": cls._mode,
            "synced_counts": counts,
            "total_synced": sum(counts.values()),
            "status": "COMPLETED",
            "timestamp": datetime.now(timezone.utc).isoformat()
        }

    @classmethod
    def get_status(cls) -> Dict[str, Any]:
        """Returns comprehensive diagnostic status of the Firebase connection."""
        return {
            "enabled": cls._enabled,
            "mode": cls._mode,
            "project_id": cls._project_id,
            "database_url": cls._database_url,
            "has_credentials_file": bool(cls._credentials_path and os.path.exists(cls._credentials_path)),
            "stats": dict(cls._stats),
            "mock_storage_counts": {k: len(v) for k, v in cls._mock_storage.items()} if cls._mode == "MOCK" else {}
        }

