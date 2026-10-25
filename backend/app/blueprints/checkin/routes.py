import os
import hmac
from flask import Blueprint, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from marshmallow import ValidationError

from app.schemas.checkin_schemas import (
    CheckInCreateSchema,
    CheckInConfirmSchema,
    CheckInCancelSchema,
    CheckInExtendSchema,
    CheckInRecoverLockoutSchema,
)
from app.services.checkin_service import CheckInService
from app.services.escalation_service import EscalationService
from app.utils.responses import success_response, error_response

checkin_bp = Blueprint('checkin', __name__, url_prefix='/api/v1/checkin')


@checkin_bp.route('/schedule', methods=['POST'])
@jwt_required()
def schedule_checkin():
    user_id = int(get_jwt_identity())
    schema = CheckInCreateSchema()
    try:
        data = schema.load(request.get_json() or {})
    except ValidationError as err:
        return error_response("Validation error", errors=err.messages, status_code=422)

    checkin = CheckInService.schedule_checkin(user_id, data)
    return success_response(
        data={"checkin": checkin.to_dict()},
        message="Smart check-in scheduled successfully",
        status_code=201
    )


@checkin_bp.route('/confirm/<int:checkin_id>', methods=['POST'])
@jwt_required()
def confirm_checkin(checkin_id):
    user_id = int(get_jwt_identity())
    schema = CheckInConfirmSchema()
    try:
        data = schema.load(request.get_json() or {})
    except ValidationError as err:
        return error_response("Validation error", errors=err.messages, status_code=422)

    try:
        checkin = CheckInService.confirm_checkin(user_id, checkin_id, data.get('safety_pin'))
    except ValueError as err:
        return error_response(str(err), status_code=400)

    return success_response(
        data={"checkin": checkin.to_dict()},
        message="Check-in confirmed. You are marked SAFE."
    )


@checkin_bp.route('/active', methods=['GET'])
@jwt_required()
def get_active():
    user_id = int(get_jwt_identity())
    checkin, status = CheckInService.get_active_checkin(user_id)
    if not checkin:
        return success_response(data={"has_active": False, "checkin": None})

    return success_response(data={
        "has_active": True,
        "evaluated_status": status,
        "checkin": checkin.to_dict()
    })


@checkin_bp.route('/cancel/<int:checkin_id>', methods=['POST'])
@jwt_required()
def cancel_checkin(checkin_id):
    user_id = int(get_jwt_identity())
    schema = CheckInCancelSchema()
    try:
        data = schema.load(request.get_json() or {})
    except ValidationError as err:
        return error_response("Validation error", errors=err.messages, status_code=422)

    try:
        checkin = CheckInService.cancel_checkin(user_id, checkin_id, data.get('safety_pin'))
    except ValueError as err:
        return error_response(str(err), status_code=400)

    return success_response(
        data={"checkin": checkin.to_dict()},
        message="Check-in timer cancelled."
    )


@checkin_bp.route('/extend/<int:checkin_id>', methods=['POST'])
@jwt_required()
def extend_checkin(checkin_id):
    user_id = int(get_jwt_identity())
    schema = CheckInExtendSchema()
    try:
        data = schema.load(request.get_json() or {})
    except ValidationError as err:
        return error_response("Validation error", errors=err.messages, status_code=422)

    try:
        checkin = CheckInService.extend_checkin(
            user_id,
            checkin_id,
            data['additional_minutes'],
            pin=data.get('safety_pin')
        )
    except ValueError as err:
        return error_response(str(err), status_code=400)

    return success_response(
        data={"checkin": checkin.to_dict()},
        message=f"Check-in extended by {data['additional_minutes']} minutes."
    )


@checkin_bp.route('/recover-lockout/<int:checkin_id>', methods=['POST'])
@jwt_required()
def recover_lockout(checkin_id):
    """
    Recovers a locked-out check-in using the user's primary account password.
    """
    user_id = int(get_jwt_identity())
    schema = CheckInRecoverLockoutSchema()
    try:
        data = schema.load(request.get_json() or {})
    except ValidationError as err:
        return error_response("Validation error", errors=err.messages, status_code=422)

    try:
        checkin = CheckInService.recover_lockout(user_id, checkin_id, data['account_password'])
    except ValueError as err:
        return error_response(str(err), status_code=400)

    return success_response(
        data={"checkin": checkin.to_dict()},
        message="Lockout cleared successfully. You may now confirm or cancel with your PIN."
    )


@checkin_bp.route('/worker/tick', methods=['POST'])
def trigger_worker_tick():
    """
    Background worker tick endpoint.
    Permits external schedulers (cron, Cloud Scheduler, supervisor) to trigger escalation and outbox processing.
    STRICT SECURITY:
    Must be protected by a configured WORKER_SECRET with constant-time comparison.
    Standard user JWTs and unauthenticated public callers are strictly rejected.
    """
    worker_secret = os.getenv('WORKER_SECRET')
    if not worker_secret:
        return error_response("Worker endpoint is not configured on this server.", status_code=503)

    auth_secret = request.headers.get('X-Worker-Secret') or request.args.get('secret')
    if not auth_secret or not hmac.compare_digest(auth_secret, worker_secret):
        return error_response("Unauthorized worker invocation: Invalid or missing worker secret.", status_code=401)

    escalated = EscalationService.check_and_escalate_overdue_checkins()
    outbox_stats = EscalationService.process_pending_dispatches()

    return success_response(
        data={
            "escalated_incidents_count": len(escalated),
            "outbox_stats": outbox_stats
        },
        message=f"Worker tick complete: {len(escalated)} overdue check-ins escalated, {outbox_stats['sent']} dispatches sent"
    )
