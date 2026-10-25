from marshmallow import Schema, fields, validate, validates_schema, ValidationError, EXCLUDE
from app.schemas.auth_schemas import validate_phone


class ContactCreateSchema(Schema):
    class Meta:
        unknown = EXCLUDE

    name = fields.String(required=False, validate=validate.Length(min=2, max=120))
    contact_name = fields.String(required=False, validate=validate.Length(min=2, max=120))
    phone = fields.String(required=False, validate=validate_phone)
    phone_number = fields.String(required=False, validate=validate_phone)
    email = fields.Email(allow_none=True, validate=validate.Length(max=191))
    relationship = fields.String(required=False, load_default='Family', validate=validate.Length(max=50))
    priority_tier = fields.Integer(required=False, load_default=1, validate=validate.OneOf([1, 2, 3]))
    priority_order = fields.Integer(required=False, validate=validate.OneOf([1, 2, 3]))
    notify_sms = fields.Boolean(required=False, load_default=True)
    notify_push = fields.Boolean(required=False, load_default=True)
    notify_call = fields.Boolean(required=False, load_default=False)

    @validates_schema
    def normalize_fields(self, data, **kwargs):
        # Map contact_name -> name
        if not data.get('name') and data.get('contact_name'):
            data['name'] = data['contact_name']
        if not data.get('name'):
            raise ValidationError("Contact name is required.", field_name="name")

        # Map phone_number -> phone
        if not data.get('phone') and data.get('phone_number'):
            data['phone'] = data['phone_number']
        if not data.get('phone'):
            raise ValidationError("Phone number is required.", field_name="phone")

        # Map priority_order -> priority_tier
        if not data.get('priority_tier') and data.get('priority_order'):
            data['priority_tier'] = data['priority_order']


class ContactUpdateSchema(Schema):
    class Meta:
        unknown = EXCLUDE

    name = fields.String(allow_none=True, validate=validate.Length(min=2, max=120))
    contact_name = fields.String(allow_none=True, validate=validate.Length(min=2, max=120))
    phone = fields.String(allow_none=True, validate=validate_phone)
    phone_number = fields.String(allow_none=True, validate=validate_phone)
    email = fields.Email(allow_none=True, validate=validate.Length(max=191))
    relationship = fields.String(allow_none=True, validate=validate.Length(max=50))
    priority_tier = fields.Integer(allow_none=True, validate=validate.OneOf([1, 2, 3]))
    priority_order = fields.Integer(allow_none=True, validate=validate.OneOf([1, 2, 3]))
    notify_sms = fields.Boolean(allow_none=True)
    notify_push = fields.Boolean(allow_none=True)
    notify_call = fields.Boolean(allow_none=True)

    @validates_schema
    def normalize_fields(self, data, **kwargs):
        if not data.get('name') and data.get('contact_name'):
            data['name'] = data['contact_name']
        if not data.get('phone') and data.get('phone_number'):
            data['phone'] = data['phone_number']
        if not data.get('priority_tier') and data.get('priority_order'):
            data['priority_tier'] = data['priority_order']
