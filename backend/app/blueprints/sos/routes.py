from flask import Blueprint, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from marshmallow import ValidationError

from app.schemas.sos_schemas import SOSTriggerSchema, SOSSyncSchema, SOSCancelSchema
from app.services.sos_service import SOSService
from app.utils.responses import success_response, error_response

sos_bp = Blueprint('sos', __name__, url_prefix='/api/v1/sos')


@sos_bp.route('/trigger', methods=['POST'])
@jwt_required()
def trigger_sos():
    """
    Immediate emergency trigger.
    Bypasses automated risk engine and initiates multi-tier dispatch immediately.
    Guarantees idempotency via client_incident_uuid.
    """
    user_id = int(get_jwt_identity())
    schema = SOSTriggerSchema()
    try:
        data = schema.load(request.get_json() or {})
    except ValidationError as err:
        return error_response("Validation error", errors=err.messages, status_code=422)

    incident, is_new = SOSService.trigger_sos(user_id, data)
    status_code = 201 if is_new else 200
    msg = "Emergency SOS initiated immediately. Dispatches triggered." if is_new else "Emergency SOS acknowledged (idempotent replay)."

    return success_response(
        data={
            "incident": incident.to_dict(include_dispatches=True),
            "is_new_incident": is_new,
            "bypass_risk_verified": True
        },
        message=msg,
        status_code=status_code
    )


@sos_bp.route('/sync', methods=['POST'])
@jwt_required()
def sync_offline():
    """
    Idempotent bulk synchronization of offline-queued incidents.
    Retrying the same incidents will not duplicate incidents or spam responders.
    """
    user_id = int(get_jwt_identity())
    schema = SOSSyncSchema()
    try:
        data = schema.load(request.get_json() or {})
    except ValidationError as err:
        return error_response("Validation error", errors=err.messages, status_code=422)

    results = SOSService.sync_offline_incidents(user_id, data['incidents'])
    return success_response(
        data={"synced_incidents": results},
        message=f"Synchronized {len(results)} emergency incidents successfully"
    )


@sos_bp.route('/cancel', methods=['POST'])
@jwt_required()
def cancel_sos():
    """
    Cancels an active emergency incident and flags it as a false alarm.
    """
    user_id = int(get_jwt_identity())
    schema = SOSCancelSchema()
    try:
        data = schema.load(request.get_json() or {})
    except ValidationError as err:
        return error_response("Validation error", errors=err.messages, status_code=422)

    try:
        incident = SOSService.cancel_sos(
            user_id=user_id,
            incident_id=data.get('incident_id'),
            client_uuid=data.get('client_incident_uuid'),
            reason=data.get('reason')
        )
    except ValueError as err:
        return error_response(str(err), status_code=404)

    return success_response(
        data={"incident": incident.to_dict(include_dispatches=True)},
        message="Emergency incident cancelled and recorded as false alarm. Note: Already delivered carrier notifications cannot be recalled."
    )


@sos_bp.route('/incident/<int:incident_id>', methods=['GET'])
@jwt_required()
def get_incident(incident_id):
    user_id = int(get_jwt_identity())
    try:
        incident = SOSService.get_incident(user_id, incident_id)
    except ValueError as err:
        return error_response(str(err), status_code=404)

    return success_response(data={"incident": incident.to_dict(include_dispatches=True)})


@sos_bp.route('/dispatch/<int:dispatch_id>/acknowledge', methods=['POST'])
def acknowledge_dispatch(dispatch_id):
    """
    Public or contact-authenticated endpoint to acknowledge an emergency dispatch.
    Secured by unguessable acknowledgment token or active user session.
    """
    from app.services.escalation_service import EscalationService
    token = request.args.get('token') or (request.get_json() or {}).get('token')
    
    # Try getting jwt identity if token not provided
    user_id = None
    try:
        from flask_jwt_extended import get_jwt_identity, verify_jwt_in_request
        verify_jwt_in_request(optional=True)
        identity = get_jwt_identity()
        if identity:
            user_id = int(identity)
    except Exception:
        pass

    try:
        dispatch = EscalationService.acknowledge_dispatch(dispatch_id, token=token, user_id=user_id)
    except ValueError as err:
        return error_response(str(err), status_code=404)
    except PermissionError as err:
        return error_response(str(err), status_code=403)

    return success_response(
        data={"dispatch": dispatch.to_dict()},
        message="Emergency dispatch acknowledgment recorded"
    )


@sos_bp.route('/dispatch/<int:dispatch_id>/retry', methods=['POST'])
@jwt_required()
def retry_dispatch(dispatch_id):
    """
    Manually retries a failed dispatch, recovering it back into the QUEUED outbox.
    """
    user_id = int(get_jwt_identity())
    from app.services.escalation_service import EscalationService
    try:
        dispatch = EscalationService.retry_failed_dispatch(dispatch_id, user_id=user_id)
    except ValueError as err:
        return error_response(str(err), status_code=400)
    except PermissionError as err:
        return error_response(str(err), status_code=403)

    return success_response(
        data={"dispatch": dispatch.to_dict()},
        message="Failed dispatch re-queued to outbox for retry"
    )


@sos_bp.route('/respond/<token>', methods=['GET'])
def view_emergency_response(token):
    """
    Public responder portal viewing endpoint.
    Records that the responder opened the link, but explicitly does NOT mark acknowledgment
    until they take an active confirmation action.
    """
    from app.services.escalation_service import EscalationService
    dispatch = EscalationService.record_link_viewed(token)
    if not dispatch:
        return error_response("Invalid or expired response token", status_code=404)

    incident = dispatch.incident
    return success_response(
        data={
            "dispatch": {
                "id": dispatch.id,
                "tier": dispatch.tier,
                "channel": dispatch.channel,
                "dispatch_status": dispatch.dispatch_status,
                "message_body": dispatch.message_body,
                "sent_at": dispatch.sent_at.isoformat() if dispatch.sent_at else None,
                "viewed_at": dispatch.viewed_at.isoformat() if dispatch.viewed_at else None,
                "acknowledged_at": dispatch.acknowledged_at.isoformat() if dispatch.acknowledged_at else None,
                "contact_name": dispatch.contact.name if dispatch.contact else "Emergency Contact",
            },
            "incident": {
                "id": incident.id,
                "trigger_source": incident.trigger_source,
                "latitude": incident.trigger_latitude,
                "longitude": incident.trigger_longitude,
                "status": incident.status,
                "created_at": incident.created_at.isoformat() if incident.created_at else None,
            },
            "requires_explicit_acknowledgment": True,
            "acknowledgment_endpoint": f"/api/v1/sos/dispatch/{dispatch.id}/acknowledge?token={token}"
        },
        message="Emergency response details viewed. Explicit acknowledgment required to confirm assistance."
    )


@sos_bp.route('/webhook/twilio', methods=['POST'])
def twilio_dlr_webhook():
    """
    Carrier Delivery Receipt (DLR) status callback from Twilio.
    Maps carrier status (delivered, undelivered, failed, unknown) to substantiate delivery truth.
    Secured by optional TWILIO_WEBHOOK_SECRET token validation.
    """
    from flask import current_app
    webhook_secret = current_app.config.get('TWILIO_WEBHOOK_SECRET')
    if webhook_secret:
        auth_header = request.headers.get('X-Twilio-Signature') or request.args.get('secret')
        if auth_header != webhook_secret:
            return error_response("Unauthorized Twilio webhook request", status_code=401)

    from app.services.escalation_service import EscalationService
    sid = request.form.get('MessageSid') or (request.get_json() or {}).get('MessageSid')
    status = request.form.get('MessageStatus') or (request.get_json() or {}).get('MessageStatus')
    error_code = request.form.get('ErrorCode') or (request.get_json() or {}).get('ErrorCode')

    if not sid or not status:
        return error_response("Missing MessageSid or MessageStatus in webhook payload", status_code=400)

    updated = EscalationService.handle_twilio_status_callback(
        gateway_message_id=sid,
        message_status=status,
        error_code=error_code
    )
    if not updated:
        return error_response("Dispatch message SID not found", status_code=404)

    return success_response(message=f"Carrier delivery receipt for {sid} updated to {status}")


@sos_bp.route('/dispatch/process', methods=['POST'])
@jwt_required()
def process_dispatches():
    """
    Triggers transactional outbox processor to deliver pending/retriable dispatches.
    """
    from app.services.escalation_service import EscalationService
    stats = EscalationService.process_pending_dispatches()
    return success_response(
        data={"stats": stats},
        message=f"Processed {stats['processed']} dispatches ({stats['sent']} sent, {stats['failed']} failed)"
    )


@sos_bp.route('/incident/<int:incident_id>/escalate', methods=['POST'])
@jwt_required()
def escalate_incident(incident_id):
    """
    Manual or automated escalation to next priority tier.
    """
    user_id = int(get_jwt_identity())
    from app.services.escalation_service import EscalationService
    data = request.get_json() or {}
    target_tier = data.get('target_tier', 2)

    try:
        new_dispatches = EscalationService.escalate_incident_tier(incident_id, target_tier, user_id=user_id)
    except PermissionError as err:
        return error_response(str(err), status_code=403)

    return success_response(
        data={"new_dispatches": [d.to_dict() for d in new_dispatches]},
        message=f"Incident escalated to Tier {target_tier}"
    )
