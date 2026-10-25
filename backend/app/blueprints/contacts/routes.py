from flask import Blueprint, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from marshmallow import ValidationError

from app.schemas.contact_schemas import ContactCreateSchema, ContactUpdateSchema
from app.services.contact_service import ContactService
from app.utils.responses import success_response, error_response

contacts_bp = Blueprint('contacts', __name__, url_prefix='/api/v1/contacts')


@contacts_bp.route('', methods=['GET'])
@jwt_required()
def list_contacts():
    user_id = int(get_jwt_identity())
    contacts = ContactService.list_contacts(user_id)
    return success_response(data={"contacts": [c.to_dict() for c in contacts]})


@contacts_bp.route('', methods=['POST'])
@jwt_required()
def create_contact():
    user_id = int(get_jwt_identity())
    schema = ContactCreateSchema()
    try:
        data = schema.load(request.get_json() or {})
    except ValidationError as err:
        return error_response("Validation error", errors=err.messages, status_code=422)

    contact = ContactService.create_contact(user_id, data)
    return success_response(
        data={"contact": contact.to_dict()},
        message="Emergency contact created successfully",
        status_code=201
    )


@contacts_bp.route('/<int:contact_id>', methods=['GET'])
@jwt_required()
def get_contact(contact_id):
    user_id = int(get_jwt_identity())
    try:
        contact = ContactService.get_contact(user_id, contact_id)
    except ValueError as err:
        return error_response(str(err), status_code=404)

    return success_response(data={"contact": contact.to_dict()})


@contacts_bp.route('/<int:contact_id>', methods=['PUT'])
@jwt_required()
def update_contact(contact_id):
    user_id = int(get_jwt_identity())
    schema = ContactUpdateSchema()
    try:
        data = schema.load(request.get_json() or {})
    except ValidationError as err:
        return error_response("Validation error", errors=err.messages, status_code=422)

    try:
        contact = ContactService.update_contact(user_id, contact_id, data)
    except ValueError as err:
        return error_response(str(err), status_code=404)

    return success_response(data={"contact": contact.to_dict()}, message="Emergency contact updated")


@contacts_bp.route('/<int:contact_id>', methods=['DELETE'])
@jwt_required()
def delete_contact(contact_id):
    user_id = int(get_jwt_identity())
    try:
        ContactService.delete_contact(user_id, contact_id)
    except ValueError as err:
        return error_response(str(err), status_code=404)

    return success_response(message="Emergency contact deleted successfully")
