from app.extensions import db
from app.models.contact import EmergencyContact
from app.services.audit_service import AuditService


class ContactService:
    @staticmethod
    def list_contacts(user_id: int) -> list[EmergencyContact]:
        """Returns active contacts ordered by priority tier (Tier 1 Primary first)."""
        return EmergencyContact.query.filter_by(user_id=user_id, is_active=True)\
            .order_by(EmergencyContact.priority_tier.asc(), EmergencyContact.created_at.asc())\
            .all()

    @staticmethod
    def create_contact(user_id: int, data: dict) -> EmergencyContact:
        contact = EmergencyContact(
            user_id=user_id,
            name=data['name'].strip(),
            phone=data['phone'].strip(),
            email=data.get('email', '').strip() if data.get('email') else None,
            relationship=data.get('relationship', 'Family'),
            priority_tier=data.get('priority_tier', 1),
            notify_sms=data.get('notify_sms', True),
            notify_push=data.get('notify_push', True),
            notify_call=data.get('notify_call', False),
        )
        db.session.add(contact)
        db.session.commit()

        AuditService.log_event(
            user_id=user_id,
            event_type='CONTACT_CREATED',
            action_description=f"Added emergency contact: {contact.name} (Tier {contact.priority_tier})"
        )
        return contact

    @staticmethod
    def get_contact(user_id: int, contact_id: int) -> EmergencyContact:
        contact = EmergencyContact.query.filter_by(id=contact_id, user_id=user_id).first()
        if not contact:
            raise ValueError("Emergency contact not found.")
        return contact

    @staticmethod
    def update_contact(user_id: int, contact_id: int, data: dict) -> EmergencyContact:
        contact = ContactService.get_contact(user_id, contact_id)
        for field in ['name', 'phone', 'email', 'relationship', 'priority_tier', 'notify_sms', 'notify_push', 'notify_call']:
            if field in data and data[field] is not None:
                setattr(contact, field, data[field])
        
        db.session.commit()
        AuditService.log_event(
            user_id=user_id,
            event_type='CONTACT_UPDATED',
            action_description=f"Updated emergency contact: {contact.name}"
        )
        return contact

    @staticmethod
    def delete_contact(user_id: int, contact_id: int) -> bool:
        contact = ContactService.get_contact(user_id, contact_id)
        name = contact.name
        db.session.delete(contact)
        db.session.commit()

        AuditService.log_event(
            user_id=user_id,
            event_type='CONTACT_DELETED',
            action_description=f"Deleted emergency contact: {name}"
        )
        return True
