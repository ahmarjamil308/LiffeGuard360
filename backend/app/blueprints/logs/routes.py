from flask import Blueprint, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from app.models.audit_log import AuditLog
from app.utils.responses import success_response

logs_bp = Blueprint('logs', __name__, url_prefix='/api/v1/logs')


@logs_bp.route('', methods=['GET'])
@jwt_required()
def get_logs():
    user_id = int(get_jwt_identity())
    event_type = request.args.get('event_type')
    limit = min(int(request.args.get('limit', 50)), 100)
    offset = int(request.args.get('offset', 0))

    query = AuditLog.query.filter_by(user_id=user_id)
    if event_type:
        query = query.filter_by(event_type=event_type)

    total = query.count()
    logs = query.order_by(AuditLog.created_at.desc()).offset(offset).limit(limit).all()

    return success_response(
        data={
            "logs": [l.to_dict() for l in logs],
            "pagination": {
                "total": total,
                "limit": limit,
                "offset": offset
            }
        }
    )
