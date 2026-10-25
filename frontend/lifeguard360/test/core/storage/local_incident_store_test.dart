import 'package:flutter_test/flutter_test.dart';
import 'package:lifeguard360/core/constants/app_constants.dart';
import 'package:lifeguard360/core/storage/local_incident_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('LocalIncidentStore Specifications', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('enqueues incident with QUEUED_OFFLINE status', () async {
      final store = LocalIncidentStore();
      final incident = {
        'client_incident_uuid': 'uuid-1234-abcd',
        'trigger_source': 'MANUAL_BUTTON',
        'latitude': 37.7749,
        'longitude': -122.4194,
      };

      await store.enqueueIncident(incident);

      final all = await store.getAllIncidents();
      expect(all.length, equals(1));
      expect(all.first['client_incident_uuid'], equals('uuid-1234-abcd'));
      expect(all.first['status'], equals(AppConstants.statusQueuedOffline));
    });

    test('deduplicates incidents with identical client_incident_uuid', () async {
      final store = LocalIncidentStore();
      final incident1 = {
        'client_incident_uuid': 'uuid-dedup-1',
        'trigger_source': 'MANUAL_BUTTON',
        'latitude': 37.7749,
      };
      final incident2 = {
        'client_incident_uuid': 'uuid-dedup-1',
        'trigger_source': 'MANUAL_BUTTON',
        'latitude': 38.0000,
      };

      await store.enqueueIncident(incident1);
      await store.enqueueIncident(incident2);

      final all = await store.getAllIncidents();
      expect(all.length, equals(1));
      expect(all.first['latitude'], equals(38.0000));
    });

    test('marks incident as synced with server ID and updates status', () async {
      final store = LocalIncidentStore();
      await store.enqueueIncident({
        'client_incident_uuid': 'uuid-sync-test',
        'trigger_source': 'MANUAL_BUTTON',
      });

      var pending = await store.getPendingIncidents();
      expect(pending.length, equals(1));

      await store.markIncidentSynced('uuid-sync-test', 501);

      pending = await store.getPendingIncidents();
      expect(pending.isEmpty, isTrue);

      final all = await store.getAllIncidents();
      expect(all.first['status'], equals(AppConstants.statusSent));
      expect(all.first['server_incident_id'], equals(501));
    });

    test('updates status and clears incidents properly', () async {
      final store = LocalIncidentStore();
      await store.enqueueIncident({
        'client_incident_uuid': 'uuid-clear-test',
        'trigger_source': 'MANUAL_BUTTON',
      });

      await store.updateIncidentStatus('uuid-clear-test', AppConstants.incidentCancelled);

      var all = await store.getAllIncidents();
      expect(all.first['status'], equals(AppConstants.incidentCancelled));

      await store.clearIncidents();
      all = await store.getAllIncidents();
      expect(all.isEmpty, isTrue);
    });

    test('MockLocalIncidentStore conforms to identical behavioral contract', () async {
      final mock = MockLocalIncidentStore();
      await mock.enqueueIncident({
        'client_incident_uuid': 'mock-uuid-99',
        'trigger_source': 'MANUAL_BUTTON',
      });

      final pending = await mock.getPendingIncidents();
      expect(pending.length, equals(1));
      expect(pending.first['status'], equals(AppConstants.statusQueuedOffline));

      await mock.markIncidentSynced('mock-uuid-99', 990);
      expect((await mock.getPendingIncidents()).isEmpty, isTrue);

      final all = await mock.getAllIncidents();
      expect(all.first['server_incident_id'], equals(990));
      expect(all.first['status'], equals(AppConstants.statusSent));
    });
  });
}
