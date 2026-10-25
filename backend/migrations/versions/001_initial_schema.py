"""001_initial_schema

Revision ID: 001_initial_schema
Revises: 
Create Date: 2026-10-21 15:28:00.000000

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '001_initial_schema'
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    # 1. users
    op.create_table(
        'users',
        sa.Column('id', sa.BigInteger().with_variant(sa.Integer, "sqlite"), primary_key=True, autoincrement=True),
        sa.Column('uuid', sa.String(36), nullable=False, unique=True),
        sa.Column('full_name', sa.String(120), nullable=False),
        sa.Column('email', sa.String(191), nullable=False, unique=True),
        sa.Column('phone', sa.String(30), nullable=False, unique=True),
        sa.Column('password_hash', sa.String(255), nullable=False),
        sa.Column('blood_group', sa.String(10), nullable=True),
        sa.Column('allergies', sa.Text(), nullable=True),
        sa.Column('medical_notes', sa.Text(), nullable=True),
        sa.Column('emergency_notes', sa.Text(), nullable=True),
        sa.Column('default_emergency_number', sa.String(20), nullable=False, server_default='911'),
        sa.Column('checkin_grace_period_minutes', sa.Integer(), nullable=False, server_default='10'),
        sa.Column('pre_alert_countdown_seconds', sa.Integer(), nullable=False, server_default='20'),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )
    op.create_index('idx_users_email', 'users', ['email'])
    op.create_index('idx_users_phone', 'users', ['phone'])

    # 2. emergency_contacts
    op.create_table(
        'emergency_contacts',
        sa.Column('id', sa.BigInteger().with_variant(sa.Integer, "sqlite"), primary_key=True, autoincrement=True),
        sa.Column('user_id', sa.BigInteger().with_variant(sa.Integer, "sqlite"), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('name', sa.String(120), nullable=False),
        sa.Column('phone', sa.String(30), nullable=False),
        sa.Column('email', sa.String(191), nullable=True),
        sa.Column('relationship', sa.String(50), nullable=False, server_default='Family'),
        sa.Column('priority_tier', sa.Integer(), nullable=False, server_default='1'),
        sa.Column('notify_sms', sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column('notify_push', sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column('notify_call', sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )
    op.create_index('idx_contacts_user_tier', 'emergency_contacts', ['user_id', 'priority_tier', 'is_active'])

    # 3. check_ins
    op.create_table(
        'check_ins',
        sa.Column('id', sa.BigInteger().with_variant(sa.Integer, "sqlite"), primary_key=True, autoincrement=True),
        sa.Column('user_id', sa.BigInteger().with_variant(sa.Integer, "sqlite"), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('title', sa.String(150), nullable=False, server_default='Routine Check-In'),
        sa.Column('destination_note', sa.String(255), nullable=True),
        sa.Column('scheduled_for', sa.DateTime(), nullable=False),
        sa.Column('grace_period_minutes', sa.Integer(), nullable=False, server_default='10'),
        sa.Column('pre_alert_seconds', sa.Integer(), nullable=False, server_default='20'),
        sa.Column('status', sa.String(30), nullable=False, server_default='SCHEDULED'),
        sa.Column('safety_pin_hash', sa.String(255), nullable=True),
        sa.Column('checked_in_at', sa.DateTime(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )
    op.create_index('idx_checkins_user_status', 'check_ins', ['user_id', 'status'])
    op.create_index('idx_checkins_schedule', 'check_ins', ['scheduled_for', 'status'])

    # 4. incidents
    op.create_table(
        'incidents',
        sa.Column('id', sa.BigInteger().with_variant(sa.Integer, "sqlite"), primary_key=True, autoincrement=True),
        sa.Column('client_incident_uuid', sa.String(36), nullable=False, unique=True),
        sa.Column('user_id', sa.BigInteger().with_variant(sa.Integer, "sqlite"), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('trigger_source', sa.String(30), nullable=False, server_default='MANUAL'),
        sa.Column('risk_score_at_trigger', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('status', sa.String(30), nullable=False, server_default='ACTIVE'),
        sa.Column('trigger_latitude', sa.Float(), nullable=True),
        sa.Column('trigger_longitude', sa.Float(), nullable=True),
        sa.Column('location_accuracy', sa.Float(), nullable=True),
        sa.Column('false_alarm_reason', sa.String(255), nullable=True),
        sa.Column('triggered_at', sa.DateTime(), nullable=False),
        sa.Column('resolved_at', sa.DateTime(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )
    op.create_index('idx_incidents_user_status', 'incidents', ['user_id', 'status'])
    op.create_index('idx_incidents_uuid', 'incidents', ['client_incident_uuid'])

    # 5. incident_dispatches
    op.create_table(
        'incident_dispatches',
        sa.Column('id', sa.BigInteger().with_variant(sa.Integer, "sqlite"), primary_key=True, autoincrement=True),
        sa.Column('incident_id', sa.BigInteger().with_variant(sa.Integer, "sqlite"), sa.ForeignKey('incidents.id', ondelete='CASCADE'), nullable=False),
        sa.Column('contact_id', sa.BigInteger().with_variant(sa.Integer, "sqlite"), sa.ForeignKey('emergency_contacts.id', ondelete='SET NULL'), nullable=True),
        sa.Column('tier', sa.Integer(), nullable=False, server_default='1'),
        sa.Column('channel', sa.String(20), nullable=False, server_default='PUSH'),
        sa.Column('dispatch_status', sa.String(30), nullable=False, server_default='QUEUED'),
        sa.Column('message_body', sa.Text(), nullable=False),
        sa.Column('gateway_message_id', sa.String(100), nullable=True),
        sa.Column('sent_at', sa.DateTime(), nullable=True),
        sa.Column('acknowledged_at', sa.DateTime(), nullable=True),
        sa.Column('failure_reason', sa.String(255), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )
    op.create_index('idx_dispatches_incident_tier', 'incident_dispatches', ['incident_id', 'tier', 'dispatch_status'])

    # 6. sensor_telemetry
    op.create_table(
        'sensor_telemetry',
        sa.Column('id', sa.BigInteger().with_variant(sa.Integer, "sqlite"), primary_key=True, autoincrement=True),
        sa.Column('user_id', sa.BigInteger().with_variant(sa.Integer, "sqlite"), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('incident_id', sa.BigInteger().with_variant(sa.Integer, "sqlite"), sa.ForeignKey('incidents.id', ondelete='SET NULL'), nullable=True),
        sa.Column('latitude', sa.Float(), nullable=True),
        sa.Column('longitude', sa.Float(), nullable=True),
        sa.Column('speed', sa.Float(), nullable=True),
        sa.Column('altitude', sa.Float(), nullable=True),
        sa.Column('accuracy', sa.Float(), nullable=True),
        sa.Column('accel_rms', sa.Float(), nullable=True),
        sa.Column('motion_variance', sa.Float(), nullable=True),
        sa.Column('battery_percentage', sa.Integer(), nullable=True),
        sa.Column('is_charging', sa.Boolean(), nullable=True),
        sa.Column('telemetry_status', sa.String(20), nullable=False, server_default='NORMAL'),
        sa.Column('recorded_at', sa.DateTime(), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )
    op.create_index('idx_telemetry_user_time', 'sensor_telemetry', ['user_id', 'recorded_at'])

    # 7. risk_assessments
    op.create_table(
        'risk_assessments',
        sa.Column('id', sa.BigInteger().with_variant(sa.Integer, "sqlite"), primary_key=True, autoincrement=True),
        sa.Column('user_id', sa.BigInteger().with_variant(sa.Integer, "sqlite"), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('composite_score', sa.Integer(), nullable=False),
        sa.Column('risk_level', sa.String(20), nullable=False),
        sa.Column('checkin_score', sa.Integer(), nullable=False),
        sa.Column('impact_score', sa.Integer(), nullable=False),
        sa.Column('battery_score', sa.Integer(), nullable=False),
        sa.Column('transit_score', sa.Integer(), nullable=False),
        sa.Column('factors_json', sa.JSON(), nullable=False),
        sa.Column('explanation_text', sa.Text(), nullable=False),
        sa.Column('disclaimer', sa.Text(), nullable=False),
        sa.Column('evaluated_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )
    op.create_index('idx_risk_user_time', 'risk_assessments', ['user_id', 'evaluated_at'])

    # 8. audit_logs
    op.create_table(
        'audit_logs',
        sa.Column('id', sa.BigInteger().with_variant(sa.Integer, "sqlite"), primary_key=True, autoincrement=True),
        sa.Column('user_id', sa.BigInteger().with_variant(sa.Integer, "sqlite"), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('event_type', sa.String(80), nullable=False),
        sa.Column('action_description', sa.String(255), nullable=False),
        sa.Column('ip_address', sa.String(45), nullable=True),
        sa.Column('user_agent', sa.String(255), nullable=True),
        sa.Column('event_metadata_json', sa.JSON(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )
    op.create_index('idx_audit_user_type', 'audit_logs', ['user_id', 'event_type'])


def downgrade():
    op.drop_table('audit_logs')
    op.drop_table('risk_assessments')
    op.drop_table('sensor_telemetry')
    op.drop_table('incident_dispatches')
    op.drop_table('incidents')
    op.drop_table('check_ins')
    op.drop_table('emergency_contacts')
    op.drop_table('users')
