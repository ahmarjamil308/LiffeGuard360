import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lifeguard360/core/database/database_service.dart';
import 'package:lifeguard360/features/contacts/models/emergency_contact_model.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DatabaseService Offline Storage & Lifecycle Tests', () {
    late Database testDb;
    late DatabaseService dbService;

    setUp(() async {
      // Use in-memory SQLite database for rapid isolated unit testing
      testDb = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE contacts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                server_id INTEGER,
                client_uuid TEXT UNIQUE NOT NULL,
                user_id TEXT,
                name TEXT NOT NULL,
                phone TEXT NOT NULL,
                email TEXT,
                relationship TEXT NOT NULL DEFAULT 'Family',
                priority_tier INTEGER NOT NULL DEFAULT 1,
                notify_sms INTEGER NOT NULL DEFAULT 1,
                notify_push INTEGER NOT NULL DEFAULT 1,
                notify_call INTEGER NOT NULL DEFAULT 0,
                is_active INTEGER NOT NULL DEFAULT 1,
                sync_status TEXT NOT NULL DEFAULT 'synced',
                sync_operation TEXT NOT NULL DEFAULT 'NONE',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE check_ins (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                server_id INTEGER,
                client_uuid TEXT UNIQUE NOT NULL,
                user_id TEXT,
                title TEXT NOT NULL,
                destination_note TEXT,
                scheduled_for TEXT NOT NULL,
                grace_period_minutes INTEGER NOT NULL DEFAULT 10,
                pre_alert_seconds INTEGER NOT NULL DEFAULT 20,
                status TEXT NOT NULL DEFAULT 'SCHEDULED',
                has_pin INTEGER NOT NULL DEFAULT 0,
                safety_pin TEXT,
                checked_in_at TEXT,
                additional_minutes INTEGER,
                sync_status TEXT NOT NULL DEFAULT 'synced',
                sync_operation TEXT NOT NULL DEFAULT 'NONE',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE incidents (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                server_id INTEGER,
                client_incident_uuid TEXT UNIQUE NOT NULL,
                user_id TEXT,
                trigger_source TEXT NOT NULL DEFAULT 'MANUAL_BUTTON',
                status TEXT NOT NULL DEFAULT 'ACTIVE',
                latitude REAL,
                longitude REAL,
                accuracy_meters REAL,
                risk_score_at_trigger REAL,
                local_notes TEXT,
                dispatches_json TEXT,
                sync_status TEXT NOT NULL DEFAULT 'synced',
                created_at TEXT NOT NULL,
                resolved_at TEXT
              )
            ''');
            await db.execute('''
              CREATE TABLE activity_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                server_id INTEGER,
                client_uuid TEXT UNIQUE NOT NULL,
                user_id TEXT,
                event_type TEXT NOT NULL,
                action TEXT NOT NULL,
                category TEXT NOT NULL,
                details TEXT,
                timestamp TEXT NOT NULL,
                sync_status TEXT NOT NULL DEFAULT 'synced'
              )
            ''');
          },
        ),
      );

      DatabaseService.setMockDatabase(testDb);
      dbService = DatabaseService.instance;
    });

    tearDown(() async {
      await testDb.close();
      DatabaseService.setMockDatabase(null);
    });

    test('1. Saves emergency contact locally with pending sync status when offline', () async {
      final contactRow = {
        'client_uuid': 'uuid_contact_001',
        'user_id': '1',
        'name': 'John Doe',
        'phone': '+14155551234',
        'email': 'john@example.com',
        'relationship': 'Brother',
        'priority_tier': 1,
        'notify_sms': 1,
        'notify_push': 1,
        'sync_status': 'pending',
        'sync_operation': 'CREATE',
      };

      await dbService.saveContact(contactRow);
      final contacts = await dbService.getContacts(userId: '1');

      expect(contacts.length, equals(1));
      expect(contacts.first['name'], equals('John Doe'));
      expect(contacts.first['sync_status'], equals('pending'));
      expect(contacts.first['sync_operation'], equals('CREATE'));
    });

    test('2. Marks contact as synced with server ID upon successful cloud push', () async {
      final contactRow = {
        'client_uuid': 'uuid_contact_002',
        'user_id': '1',
        'name': 'Jane Doe',
        'phone': '+14155555678',
        'relationship': 'Sister',
        'priority_tier': 1,
        'sync_status': 'pending',
        'sync_operation': 'CREATE',
      };

      await dbService.saveContact(contactRow);
      await dbService.markContactSynced('uuid_contact_002', 105);

      final contacts = await dbService.getContacts(userId: '1');
      expect(contacts.first['server_id'], equals(105));
      expect(contacts.first['sync_status'], equals('synced'));
      expect(contacts.first['sync_operation'], equals('NONE'));
    });

    test('3. Handles offline deletion via soft delete flag and purges upon confirmation', () async {
      final contactRow = {
        'server_id': 105,
        'client_uuid': 'uuid_contact_003',
        'user_id': '1',
        'name': 'Doctor Smith',
        'phone': '+14155559999',
        'relationship': 'Doctor',
        'priority_tier': 3,
        'sync_status': 'synced',
        'sync_operation': 'NONE',
      };

      await dbService.saveContact(contactRow);
      // Soft-delete locally while offline
      await dbService.deleteContactLocally('uuid_contact_003');

      // Filtered getContacts does not return soft-deleted contact to user UI
      final visibleContacts = await dbService.getContacts(userId: '1');
      expect(visibleContacts.isEmpty, isTrue);

      // Pending sync queries include it for cloud sync
      final pending = await dbService.getPendingContacts();
      expect(pending.length, equals(1));
      expect(pending.first['sync_operation'], equals('DELETE'));

      // After cloud confirmation, purge removes it completely
      await dbService.purgeDeletedContact('uuid_contact_003');
      final afterPurge = await dbService.getPendingContacts();
      expect(afterPurge.isEmpty, isTrue);
    });

    test('4. Does not overwrite newer local edits with older server data', () async {
      // 1. User edited locally while offline
      await dbService.saveContact({
        'server_id': 200,
        'client_uuid': 'uuid_200',
        'user_id': '1',
        'name': 'Mom Updated Phone',
        'phone': '+14159990000',
        'sync_status': 'pending',
        'sync_operation': 'UPDATE',
      });

      // 2. Server fetch arrives with older name
      await dbService.saveServerContacts([
        {
          'id': 200,
          'client_uuid': 'uuid_200',
          'name': 'Mom Old Name',
          'phone': '+14151112222',
        }
      ], userId: '1');

      final contacts = await dbService.getContacts(userId: '1');
      expect(contacts.first['name'], equals('Mom Updated Phone'));
      expect(contacts.first['phone'], equals('+14159990000'));
    });

    test('5. Check-in records save and retrieve from local SQLite storage', () async {
      final checkInMap = {
        'server_id': 10,
        'client_uuid': 'checkin_uuid_10',
        'user_id': '1',
        'title': 'Evening Walk',
        'destination_note': 'City Park Loop',
        'scheduled_for': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
        'grace_period_minutes': 10,
        'pre_alert_seconds': 20,
        'status': 'SCHEDULED',
        'sync_status': 'synced',
      };

      await dbService.saveCheckIn(checkInMap);
      final active = await dbService.getActiveCheckIn(userId: '1');

      expect(active, isNotNull);
      expect(active!['title'], equals('Evening Walk'));
      expect(active['status'], equals('SCHEDULED'));
    });

    test('6. Emergency SOS incident saves offline and tracks sync state', () async {
      final incident = {
        'client_incident_uuid': 'incident_sos_999',
        'user_id': '1',
        'trigger_source': 'MANUAL_BUTTON',
        'status': 'QUEUED_OFFLINE',
        'latitude': 37.7749,
        'longitude': -122.4194,
        'accuracy_meters': 5.0,
        'sync_status': 'pending',
      };

      await dbService.saveIncident(incident);
      final pending = await dbService.getPendingIncidents();

      expect(pending.length, equals(1));
      expect(pending.first['client_incident_uuid'], equals('incident_sos_999'));

      await dbService.markIncidentSynced('incident_sos_999', 55);
      final pendingAfterSync = await dbService.getPendingIncidents();
      expect(pendingAfterSync.isEmpty, isTrue);
    });

    test('7. Activity audit logs record events and query by category', () async {
      await dbService.logActivity(
        eventType: 'TEST_EVENT_SOS',
        action: 'Manual SOS triggered',
        category: 'SOS',
        userId: '1',
      );
      await dbService.logActivity(
        eventType: 'TEST_EVENT_SYSTEM',
        action: 'Heartbeat cycle',
        category: 'SYSTEM',
        userId: '1',
      );

      final sosLogs = await dbService.getActivityLogs(userId: '1', category: 'SOS');
      expect(sosLogs.length, equals(1));
      expect(sosLogs.first['event_type'], equals('TEST_EVENT_SOS'));

      final allLogs = await dbService.getActivityLogs(userId: '1', category: 'ALL');
      expect(allLogs.length, equals(2));
    });

    test('8. EmergencyContactModel converts to and from SQLite map reliably', () {
      final original = EmergencyContactModel(
        id: 77,
        clientUuid: 'test_uuid_77',
        contactName: 'Alice Walker',
        phoneNumber: '+19876543210',
        relationship: 'Friend',
        priorityOrder: 2,
        syncStatus: 'pending',
        syncOperation: 'CREATE',
      );

      final sqliteMap = original.toSqliteMap(userId: '10');
      final restored = EmergencyContactModel.fromSqlite(sqliteMap);

      expect(restored.id, equals(77));
      expect(restored.clientUuid, equals('test_uuid_77'));
      expect(restored.contactName, equals('Alice Walker'));
      expect(restored.phoneNumber, equals('+19876543210'));
      expect(restored.relationship, equals('Friend'));
      expect(restored.priorityOrder, equals(2));
      expect(restored.syncStatus, equals('pending'));
      expect(restored.syncOperation, equals('CREATE'));
      expect(restored.isPendingSync, isTrue);
    });
  });
}

