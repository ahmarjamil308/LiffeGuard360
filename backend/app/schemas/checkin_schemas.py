from marshmallow import Schema, fields, validate


class CheckInCreateSchema(Schema):
    title = fields.String(required=False, load_default='Routine Check-In', validate=validate.Length(max=150))
    destination_note = fields.String(allow_none=True, validate=validate.Length(max=255))
    scheduled_for = fields.DateTime(required=True)
    grace_period_minutes = fields.Integer(required=False, load_default=10, validate=validate.Range(min=1, max=60))
    pre_alert_seconds = fields.Integer(required=False, load_default=20, validate=validate.Range(min=10, max=45))
    safety_pin = fields.String(allow_none=True, validate=validate.Length(min=4, max=8))


class CheckInConfirmSchema(Schema):
    safety_pin = fields.String(allow_none=True)


class CheckInCancelSchema(Schema):
    safety_pin = fields.String(allow_none=True)


class CheckInExtendSchema(Schema):
    additional_minutes = fields.Integer(required=True, validate=validate.Range(min=1, max=1440))
    safety_pin = fields.String(allow_none=True)


class CheckInRecoverLockoutSchema(Schema):
    account_password = fields.String(required=True, validate=validate.Length(min=6, max=128))

