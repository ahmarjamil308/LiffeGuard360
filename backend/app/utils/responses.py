from datetime import datetime, timezone
from flask import jsonify


def success_response(data=None, message="Success", status_code=200, meta=None):
    """Return a unified standard success JSON response."""
    payload = {
        "success": True,
        "message": message,
        "data": data if data is not None else {},
        "meta": meta or {}
    }
    if "timestamp" not in payload["meta"]:
        payload["meta"]["timestamp"] = datetime.now(timezone.utc).isoformat()
    return jsonify(payload), status_code


def error_response(message="An error occurred", errors=None, status_code=400):
    """Return a unified standard error JSON response."""
    payload = {
        "success": False,
        "message": message,
        "errors": errors if errors is not None else [],
        "meta": {
            "timestamp": datetime.now(timezone.utc).isoformat()
        }
    }
    return jsonify(payload), status_code
