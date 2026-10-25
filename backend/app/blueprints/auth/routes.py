from flask import Blueprint, request
from flask_jwt_extended import jwt_required, get_jwt_identity, create_access_token
from marshmallow import ValidationError

from app.schemas.auth_schemas import RegisterSchema, LoginSchema, ProfileUpdateSchema
from app.services.auth_service import AuthService
from app.utils.responses import success_response, error_response

auth_bp = Blueprint('auth', __name__, url_prefix='/api/v1/auth')


@auth_bp.route('/register', methods=['POST'])
def register():
    raw_data = request.get_json() or {}
    # Support both 'phone' and 'phone_number' from mobile/web clients
    if 'phone_number' in raw_data and 'phone' not in raw_data:
        raw_data['phone'] = raw_data['phone_number']

    schema = RegisterSchema()
    try:
        data = schema.load(raw_data)
    except ValidationError as err:
        return error_response("Validation error", errors=err.messages, status_code=422)

    try:
        user, access_token, refresh_token = AuthService.register_user(data)
    except ValueError as err:
        return error_response(str(err), status_code=409)

    return success_response(
        data={
            "user": user.to_dict(),
            "token": access_token,
            "tokens": {
                "access_token": access_token,
                "refresh_token": refresh_token,
                "token_type": "Bearer"
            }
        },
        message="User registered successfully",
        status_code=201
    )


@auth_bp.route('/login', methods=['POST'])
def login():
    raw_data = request.get_json() or {}
    # Support both 'email' and 'email_or_phone' from mobile/web clients
    if 'email' in raw_data and 'email_or_phone' not in raw_data:
        raw_data['email_or_phone'] = raw_data['email']

    schema = LoginSchema()
    try:
        data = schema.load(raw_data)
    except ValidationError as err:
        return error_response("Validation error", errors=err.messages, status_code=422)

    try:
        user, access_token, refresh_token = AuthService.authenticate_user(
            data['email_or_phone'], data['password']
        )
    except ValueError as err:
        return error_response(str(err), status_code=401)

    return success_response(
        data={
            "user": user.to_dict(),
            "token": access_token,
            "tokens": {
                "access_token": access_token,
                "refresh_token": refresh_token,
                "token_type": "Bearer"
            }
        },
        message="Login successful"
    )


@auth_bp.route('/refresh', methods=['POST'])
@jwt_required(refresh=True)
def refresh():
    identity = get_jwt_identity()
    new_access_token = create_access_token(identity=identity)
    return success_response(
        data={"access_token": new_access_token, "token_type": "Bearer"},
        message="Access token refreshed successfully"
    )


@auth_bp.route('/profile', methods=['GET'])
@jwt_required()
def get_profile():
    user_id = int(get_jwt_identity())
    try:
        user = AuthService.get_profile(user_id)
    except ValueError as err:
        return error_response(str(err), status_code=404)

    return success_response(data={"user": user.to_dict()})


@auth_bp.route('/profile', methods=['PUT'])
@jwt_required()
def update_profile():
    user_id = int(get_jwt_identity())
    schema = ProfileUpdateSchema()
    try:
        data = schema.load(request.get_json() or {})
    except ValidationError as err:
        return error_response("Validation error", errors=err.messages, status_code=422)

    try:
        user = AuthService.update_profile(user_id, data)
    except ValueError as err:
        return error_response(str(err), status_code=400)

    return success_response(data={"user": user.to_dict()}, message="Profile updated successfully")
