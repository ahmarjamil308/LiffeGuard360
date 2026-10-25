import re
from marshmallow import Schema, fields, validate, validates, validates_schema, ValidationError, EXCLUDE


def validate_phone(value):
    # E.164-compatible or standard 7-15 digit phone validation
    pattern = r'^\+?[0-9]{7,15}$'
    if not re.match(pattern, str(value).strip()):
        raise ValidationError("Invalid phone number format. Must contain 7 to 15 digits, optional leading '+'.")


class RegisterSchema(Schema):
    class Meta:
        unknown = EXCLUDE

    full_name = fields.String(required=True, validate=validate.Length(min=2, max=120))
    email = fields.Email(required=True, validate=validate.Length(max=191))
    phone = fields.String(required=False, validate=validate_phone)
    phone_number = fields.String(required=False, validate=validate_phone)
    password = fields.String(required=True, validate=validate.Length(min=8, max=128))
    emergency_pin = fields.String(required=False, allow_none=True)
    blood_group = fields.String(allow_none=True, validate=validate.OneOf(
        ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', None, '']
    ))
    default_emergency_number = fields.String(allow_none=True, validate=validate.Length(min=2, max=20))

    @validates_schema
    def validate_phone_present(self, data, **kwargs):
        if not data.get('phone') and not data.get('phone_number'):
            raise ValidationError("Phone number is required.", field_name="phone")
        if not data.get('phone') and data.get('phone_number'):
            data['phone'] = data['phone_number']


class LoginSchema(Schema):
    class Meta:
        unknown = EXCLUDE

    email = fields.String(required=False)
    email_or_phone = fields.String(required=False, validate=validate.Length(min=3, max=191))
    password = fields.String(required=True, validate=validate.Length(min=1, max=128))

    @validates_schema
    def validate_identifier_present(self, data, **kwargs):
        if not data.get('email_or_phone') and not data.get('email'):
            raise ValidationError("Email or phone number is required.", field_name="email_or_phone")
        if not data.get('email_or_phone') and data.get('email'):
            data['email_or_phone'] = data['email']


class ProfileUpdateSchema(Schema):
    class Meta:
        unknown = EXCLUDE

    full_name = fields.String(allow_none=True, validate=validate.Length(min=2, max=120))
    blood_group = fields.String(allow_none=True, validate=validate.OneOf(
        ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', None, '']
    ))
    allergies = fields.String(allow_none=True)
    medical_notes = fields.String(allow_none=True)
    emergency_notes = fields.String(allow_none=True)
    default_emergency_number = fields.String(allow_none=True, validate=validate.Length(min=2, max=20))
    checkin_grace_period_minutes = fields.Integer(allow_none=True, validate=validate.Range(min=1, max=60))
    pre_alert_countdown_seconds = fields.Integer(allow_none=True, validate=validate.Range(min=10, max=45))
