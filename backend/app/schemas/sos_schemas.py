from datetime import datetime, timezone
from marshmallow import Schema, fields, validate, validates_schema, EXCLUDE


class SOSTriggerSchema(Schema):
    class Meta:
        unknown = EXCLUDE

    client_incident_uuid = fields.String(allow_none=True)
    trigger_source = fields.String(
        required=False,
        load_default='MANUAL',
        validate=validate.OneOf(['MANUAL', 'MANUAL_BUTTON', 'AUTOMATED_RISK', 'OVERDUE_CHECKIN', 'SEVERE_FALL'])
    )
    risk_score_at_trigger = fields.Float(required=False, load_default=0.0, validate=validate.Range(min=0.0, max=100.0))
    latitude = fields.Float(allow_none=True, validate=validate.Range(min=-90.0, max=90.0))
    longitude = fields.Float(allow_none=True, validate=validate.Range(min=-180.0, max=180.0))
    accuracy = fields.Float(allow_none=True, validate=validate.Range(min=0.0))
    accuracy_meters = fields.Float(allow_none=True)
    triggered_at = fields.DateTime(allow_none=True)

    @validates_schema
    def normalize_trigger(self, data, **kwargs):
        if data.get('trigger_source') == 'MANUAL_BUTTON':
            data['trigger_source'] = 'MANUAL'
        if data.get('accuracy') is None and data.get('accuracy_meters') is not None:
            data['accuracy'] = data['accuracy_meters']


class SOSSyncItemSchema(Schema):
    class Meta:
        unknown = EXCLUDE

    client_incident_uuid = fields.String(required=True)
    trigger_source = fields.String(
        required=False,
        load_default='MANUAL',
        validate=validate.OneOf(['MANUAL', 'MANUAL_BUTTON', 'AUTOMATED_RISK', 'OVERDUE_CHECKIN', 'SEVERE_FALL'])
    )
    risk_score_at_trigger = fields.Float(required=False, load_default=0.0, validate=validate.Range(min=0.0, max=100.0))
    latitude = fields.Float(allow_none=True, validate=validate.Range(min=-90.0, max=90.0))
    longitude = fields.Float(allow_none=True, validate=validate.Range(min=-180.0, max=180.0))
    accuracy = fields.Float(allow_none=True, validate=validate.Range(min=0.0))
    accuracy_meters = fields.Float(allow_none=True)
    triggered_at = fields.DateTime(allow_none=True)
    created_at = fields.DateTime(allow_none=True)

    @validates_schema
    def normalize_sync_item(self, data, **kwargs):
        if data.get('trigger_source') == 'MANUAL_BUTTON':
            data['trigger_source'] = 'MANUAL'
        if data.get('accuracy') is None and data.get('accuracy_meters') is not None:
            data['accuracy'] = data['accuracy_meters']
        if not data.get('triggered_at'):
            data['triggered_at'] = data.get('created_at') or datetime.now(timezone.utc)


class SOSSyncSchema(Schema):
    class Meta:
        unknown = EXCLUDE

    incidents = fields.List(fields.Nested(SOSSyncItemSchema), required=True, validate=validate.Length(min=1))


class SOSCancelSchema(Schema):
    class Meta:
        unknown = EXCLUDE

    incident_id = fields.Integer(allow_none=True)
    client_incident_uuid = fields.String(allow_none=True)
    safety_pin = fields.String(allow_none=True)
    pin = fields.String(allow_none=True)
    reason = fields.String(allow_none=True, validate=validate.Length(max=255))

    @validates_schema
    def normalize_cancel(self, data, **kwargs):
        if not data.get('safety_pin') and data.get('pin'):
            data['safety_pin'] = data['pin']
