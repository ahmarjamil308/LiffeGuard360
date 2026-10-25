from flask import Blueprint, jsonify
from app.services.firebase_service import FirebaseService
from app.utils.responses import success_response, error_response

firebase_bp = Blueprint('firebase_bp', __name__, url_prefix='/api/v1/firebase')


@firebase_bp.route('/status', methods=['GET'])
def get_firebase_status():
    """Returns real-time status of the Firebase cloud connection."""
    status = FirebaseService.get_status()
    return success_response(
        data=status,
        message=f"Firebase connection status: {status['mode']}"
    )


@firebase_bp.route('/sync-all', methods=['POST'])
def trigger_full_sync():
    """Exports all relational records (users, contacts, incidents, telemetry, logs) to Firebase."""
    try:
        result = FirebaseService.sync_all_database_records()
        return success_response(
            data=result,
            message=f"Successfully synced {result['total_synced']} records to Firebase"
        )
    except Exception as e:
        return error_response(
            message=f"Failed to execute Firebase full sync: {str(e)}",
            status_code=500
        )

