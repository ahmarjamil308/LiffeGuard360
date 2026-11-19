import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:uuid/uuid.dart';

/// Central SQLite Database Service for LifeGuard 360 offline resilience and synchronization.
/// Supports Mobile (Android/iOS), Desktop (Windows/macOS/Linux via FFI), Web (via FFI Web & in-memory fallback), and Unit Tests.
class DatabaseService {
  static DatabaseService? _instance;
  static Database? _db;
  static const String _databaseName = 'lifeguard360_offline.db';
  static const int _databaseVersion = 1;
  static const Uuid _uuid = Uuid();

  // In-memory fallback storage for Web or environments without native SQLite binaries
  static bool _useFallback = false;
  final List<Map<String, dynamic>> _fallbackContacts = [];
  final List<Map<String, dynamic>> _fallbackCheckIns = [];
  final List<Map<String, dynamic>> _fallbackIncidents = [];
  final List<Map<String, dynamic>> _fallbackLogs = [];
  final List<Map<String, dynamic>> _fallbackMonitoring = [];

  DatabaseService._();

  static DatabaseService get instance {
    _instance ??= DatabaseService._();
    return _instance!;
  }

  /// Sets an explicit database instance (useful for unit testing with in-memory SQLite).
  static void setMockDatabase(Database? db) {
    _db = db;
    _useFallback = false;
  }

  /// Generates a unique client-side UUID for offline record tracking.
  static String generateUuid() => _uuid.v4();

  /// Returns the open database instance, initializing if necessary.
  Future<Database?> get database async {
    if (_useFallback) return null;
    if (_db != null && _db!.isOpen) {
      return _db!;
    }
    try {
      _db = await _initDatabase();
      return _db;
    } catch (e) {
      debugPrint('[DatabaseService] Native SQLite initialization failed ($e). Operating in memory-safe fallback mode.');
      _useFallback = true;
      return null;
    }
  }

  /// Initializes the SQLite engine and opens the database.
  Future<Database> _initDatabase() async {
    if (kIsWeb) {
      try {
        databaseFactory = databaseFactoryFfiWeb;
        return await databaseFactory.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            version: _databaseVersion,
            onCreate: _onCreate,
            onUpgrade: _onUpgrade,
          ),
        );
      } catch (e) {
        _useFallback = true;
        rethrow;
      }
    } else {
      try {
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          sqfliteFfiInit();
          databaseFactory = databaseFactoryFfi;
        }
      } catch (_) {}

      final dbPath = await getDatabasesPath();
      final path = p.join(dbPath, _databaseName);

      return await openDatabase(
        path,
        version: _databaseVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    }
  }

  /// Creates local SQLite schema matching Firebase Cloud Firestore collections.
  Future<void> _onCreate(Database db, int version) async {
    // 1. Emergency Contacts Table
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

    // 2. Smart Check-Ins Table
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

    // 3. Emergency SOS Incidents Table
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

    // 4. Activity Audit Logs Table
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

    // 5. Sensor Telemetry & Monitoring Table
    await db.execute('''
      CREATE TABLE monitoring_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_uuid TEXT UNIQUE NOT NULL,
        user_id TEXT,
        latitude REAL,
        longitude REAL,
        speed REAL,
        accel_rms REAL,
        motion_variance REAL,
        battery_percentage INTEGER,
        is_charging INTEGER,
        telemetry_status TEXT,
        recorded_at TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'synced'
      )
    ''');

    // Indices for query performance
    await db.execute('CREATE INDEX idx_contacts_user ON contacts(user_id, sync_operation);');
    await db.execute('CREATE INDEX idx_checkins_user ON check_ins(user_id, status);');
    await db.execute('CREATE INDEX idx_incidents_uuid ON incidents(client_incident_uuid);');
    await db.execute('CREATE INDEX idx_logs_timestamp ON activity_logs(timestamp);');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Migration logic for future schema increments
  }

  // ===========================================================================
  // CONTACTS REPOSITORY
  // ===========================================================================

  /// Saves or updates a contact record locally.
  Future<int> saveContact(Map<String, dynamic> contact) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final map = Map<String, dynamic>.from(contact);
    map.putIfAbsent('client_uuid', () => generateUuid());
    map.putIfAbsent('created_at', () => now);
    map['updated_at'] = now;

    final db = await database;
    if (db == null) {
      final idx = _fallbackContacts.indexWhere((c) => c['client_uuid'] == map['client_uuid']);
      if (idx >= 0) {
        _fallbackContacts[idx] = map;
      } else {
        _fallbackContacts.add(map);
      }
      return 1;
    }

    return await db.insert(
      'contacts',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Bulk upserts server-fetched contacts into local database.
  Future<void> saveServerContacts(List<Map<String, dynamic>> serverContacts, {String? userId}) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final db = await database;

    if (db == null) {
      for (final contact in serverContacts) {
        final serverId = contact['id'] as int?;
        if (serverId == null) continue;
        final clientUuid = contact['client_uuid']?.toString() ?? 'server_$serverId';
        final idx = _fallbackContacts.indexWhere((c) => c['client_uuid'] == clientUuid || c['server_id'] == serverId);
        if (idx >= 0 && _fallbackContacts[idx]['sync_status'] == 'pending') continue;

        final row = {
          'server_id': serverId,
          'client_uuid': clientUuid,
          'user_id': userId ?? contact['user_id']?.toString(),
          'name': contact['name'] ?? contact['contact_name'] ?? '',
          'phone': contact['phone'] ?? contact['phone_number'] ?? '',
          'email': contact['email'],
          'relationship': contact['relationship'] ?? 'Family',
          'priority_tier': contact['priority_tier'] ?? contact['priority_order'] ?? 1,
          'notify_sms': (contact['notify_sms'] == true || contact['notify_sms'] == 1) ? 1 : 0,
          'notify_push': (contact['notify_push'] == true || contact['notify_push'] == 1) ? 1 : 0,
          'notify_call': (contact['notify_call'] == true || contact['notify_call'] == 1) ? 1 : 0,
          'is_active': (contact['is_active'] == true || contact['is_active'] == 1) ? 1 : 0,
          'sync_status': 'synced',
          'sync_operation': 'NONE',
          'created_at': contact['created_at']?.toString() ?? now,
          'updated_at': contact['updated_at']?.toString() ?? now,
        };

        if (idx >= 0) {
          _fallbackContacts[idx] = row;
        } else {
          _fallbackContacts.add(row);
        }
      }
      return;
    }

    final batch = db.batch();
    for (final contact in serverContacts) {
      final serverId = contact['id'] as int?;
      if (serverId == null) continue;

      final row = {
        'server_id': serverId,
        'client_uuid': contact['client_uuid']?.toString() ?? 'server_$serverId',
        'user_id': userId ?? contact['user_id']?.toString(),
        'name': contact['name'] ?? contact['contact_name'] ?? '',
        'phone': contact['phone'] ?? contact['phone_number'] ?? '',
        'email': contact['email'],
        'relationship': contact['relationship'] ?? 'Family',
        'priority_tier': contact['priority_tier'] ?? contact['priority_order'] ?? 1,
        'notify_sms': (contact['notify_sms'] == true || contact['notify_sms'] == 1) ? 1 : 0,
        'notify_push': (contact['notify_push'] == true || contact['notify_push'] == 1) ? 1 : 0,
        'notify_call': (contact['notify_call'] == true || contact['notify_call'] == 1) ? 1 : 0,
        'is_active': (contact['is_active'] == true || contact['is_active'] == 1) ? 1 : 0,
        'sync_status': 'synced',
        'sync_operation': 'NONE',
        'created_at': contact['created_at']?.toString() ?? now,
        'updated_at': contact['updated_at']?.toString() ?? now,
      };

      // Check if there is an unsynchronized local edit before overwriting
      final existing = await db.query(
        'contacts',
        where: 'server_id = ? OR client_uuid = ?',
        whereArgs: [serverId, row['client_uuid']],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        final localSyncStatus = existing.first['sync_status'] as String?;
        if (localSyncStatus == 'pending') continue;
      }

      batch.insert(
        'contacts',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  /// Fetches contacts for display, filtering out soft-deleted pending records.
  Future<List<Map<String, dynamic>>> getContacts({String? userId}) async {
    final db = await database;
    if (db == null) {
      return _fallbackContacts.where((c) {
        if (c['sync_operation'] == 'DELETE') return false;
        if (userId != null && userId.isNotEmpty && c['user_id'] != null && c['user_id'] != userId) return false;
        return true;
      }).toList()
        ..sort((a, b) {
          final tierA = a['priority_tier'] as int? ?? 1;
          final tierB = b['priority_tier'] as int? ?? 1;
          return tierA.compareTo(tierB);
        });
    }

    String whereClause = "sync_operation != 'DELETE'";
    List<dynamic> whereArgs = [];

    if (userId != null && userId.isNotEmpty) {
      whereClause += " AND (user_id = ? OR user_id IS NULL)";
      whereArgs.add(userId);
    }

    return await db.query(
      'contacts',
      where: whereClause,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'priority_tier ASC, name ASC',
    );
  }

  /// Returns all contacts with pending sync operations.
  Future<List<Map<String, dynamic>>> getPendingContacts() async {
    final db = await database;
    if (db == null) {
      return _fallbackContacts.where((c) => c['sync_status'] == 'pending').toList();
    }
    return await db.query(
      'contacts',
      where: "sync_status = 'pending'",
      orderBy: 'id ASC',
    );
  }

  /// Marks a contact as successfully synchronized with Firebase / backend.
  Future<void> markContactSynced(String clientUuid, int serverId) async {
    final db = await database;
    if (db == null) {
      final idx = _fallbackContacts.indexWhere((c) => c['client_uuid'] == clientUuid);
      if (idx >= 0) {
        _fallbackContacts[idx]['server_id'] = serverId;
        _fallbackContacts[idx]['sync_status'] = 'synced';
        _fallbackContacts[idx]['sync_operation'] = 'NONE';
      }
      return;
    }
    await db.update(
      'contacts',
      {
        'server_id': serverId,
        'sync_status': 'synced',
        'sync_operation': 'NONE',
      },
      where: 'client_uuid = ?',
      whereArgs: [clientUuid],
    );
  }

  /// Marks a contact sync attempt as failed.
  Future<void> markContactFailed(String clientUuid) async {
    final db = await database;
    if (db == null) {
      final idx = _fallbackContacts.indexWhere((c) => c['client_uuid'] == clientUuid);
      if (idx >= 0) {
        _fallbackContacts[idx]['sync_status'] = 'failed';
      }
      return;
    }
    await db.update(
      'contacts',
      {'sync_status': 'failed'},
      where: 'client_uuid = ?',
      whereArgs: [clientUuid],
    );
  }

  /// Soft deletes a contact locally (marks for sync) or immediately removes if never synced.
  Future<void> deleteContactLocally(String clientUuid) async {
    final db = await database;
    if (db == null) {
      final idx = _fallbackContacts.indexWhere((c) => c['client_uuid'] == clientUuid);
      if (idx >= 0) {
        if (_fallbackContacts[idx]['server_id'] == null) {
          _fallbackContacts.removeAt(idx);
        } else {
          _fallbackContacts[idx]['sync_status'] = 'pending';
          _fallbackContacts[idx]['sync_operation'] = 'DELETE';
        }
      }
      return;
    }

    final existing = await db.query(
      'contacts',
      where: 'client_uuid = ?',
      whereArgs: [clientUuid],
      limit: 1,
    );

    if (existing.isEmpty) return;

    final serverId = existing.first['server_id'];
    if (serverId == null) {
      await db.delete('contacts', where: 'client_uuid = ?', whereArgs: [clientUuid]);
    } else {
      await db.update(
        'contacts',
        {
          'sync_status': 'pending',
          'sync_operation': 'DELETE',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'client_uuid = ?',
        whereArgs: [clientUuid],
      );
    }
  }

  /// Permanently removes a deleted contact after backend/Firebase confirmed deletion.
  Future<void> purgeDeletedContact(String clientUuid) async {
    final db = await database;
    if (db == null) {
      _fallbackContacts.removeWhere((c) => c['client_uuid'] == clientUuid);
      return;
    }
    await db.delete('contacts', where: 'client_uuid = ?', whereArgs: [clientUuid]);
  }

  // ===========================================================================
  // CHECK-INS REPOSITORY
  // ===========================================================================

  /// Saves or updates a check-in record.
  Future<int> saveCheckIn(Map<String, dynamic> checkin) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final map = Map<String, dynamic>.from(checkin);
    map.putIfAbsent('client_uuid', () => generateUuid());
    map.putIfAbsent('created_at', () => now);
    map['updated_at'] = now;

    final db = await database;
    if (db == null) {
      final idx = _fallbackCheckIns.indexWhere((c) => c['client_uuid'] == map['client_uuid']);
      if (idx >= 0) {
        _fallbackCheckIns[idx] = map;
      } else {
        _fallbackCheckIns.add(map);
      }
      return 1;
    }

    return await db.insert(
      'check_ins',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Gets the currently active check-in.
  Future<Map<String, dynamic>?> getActiveCheckIn({String? userId}) async {
    final db = await database;
    if (db == null) {
      final active = _fallbackCheckIns.where((c) {
        final status = c['status']?.toString() ?? '';
        return status != 'SAFE_COMPLETED' && status != 'CANCELLED';
      }).toList();
      return active.isNotEmpty ? active.last : null;
    }

    String where = "status NOT IN ('SAFE_COMPLETED', 'CANCELLED')";
    List<dynamic> args = [];

    if (userId != null && userId.isNotEmpty) {
      where += " AND (user_id = ? OR user_id IS NULL)";
      args.add(userId);
    }

    final result = await db.query(
      'check_ins',
      where: where,
      whereArgs: args.isNotEmpty ? args : null,
      orderBy: 'scheduled_for DESC',
      limit: 1,
    );

    return result.isNotEmpty ? result.first : null;
  }

  /// Gets historical check-ins.
  Future<List<Map<String, dynamic>>> getCheckInHistory({String? userId, int limit = 20}) async {
    final db = await database;
    if (db == null) {
      return List.from(_fallbackCheckIns);
    }
    String? where;
    List<dynamic>? args;

    if (userId != null && userId.isNotEmpty) {
      where = "user_id = ? OR user_id IS NULL";
      args = [userId];
    }

    return await db.query(
      'check_ins',
      where: where,
      whereArgs: args,
      orderBy: 'scheduled_for DESC',
      limit: limit,
    );
  }

  /// Gets check-ins awaiting synchronization.
  Future<List<Map<String, dynamic>>> getPendingCheckIns() async {
    final db = await database;
    if (db == null) {
      return _fallbackCheckIns.where((c) => c['sync_status'] == 'pending').toList();
    }
    return await db.query(
      'check_ins',
      where: "sync_status = 'pending'",
      orderBy: 'id ASC',
    );
  }

  /// Marks a check-in as synced with the server.
  Future<void> markCheckInSynced(String clientUuid, int serverId, {String? status}) async {
    final db = await database;
    if (db == null) {
      final idx = _fallbackCheckIns.indexWhere((c) => c['client_uuid'] == clientUuid);
      if (idx >= 0) {
        _fallbackCheckIns[idx]['server_id'] = serverId;
        _fallbackCheckIns[idx]['sync_status'] = 'synced';
        _fallbackCheckIns[idx]['sync_operation'] = 'NONE';
        if (status != null) _fallbackCheckIns[idx]['status'] = status;
      }
      return;
    }
    final updates = <String, dynamic>{
      'server_id': serverId,
      'sync_status': 'synced',
      'sync_operation': 'NONE',
    };
    if (status != null) {
      updates['status'] = status;
    }
    await db.update(
      'check_ins',
      updates,
      where: 'client_uuid = ?',
      whereArgs: [clientUuid],
    );
  }

  // ===========================================================================
  // INCIDENTS REPOSITORY
  // ===========================================================================

  /// Persists an emergency incident locally.
  Future<int> saveIncident(Map<String, dynamic> incident) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final map = Map<String, dynamic>.from(incident);
    map.putIfAbsent('client_incident_uuid', () => generateUuid());
    map.putIfAbsent('created_at', () => now);
    map.putIfAbsent('sync_status', () => 'pending');

    final db = await database;
    if (db == null) {
      final idx = _fallbackIncidents.indexWhere((i) => i['client_incident_uuid'] == map['client_incident_uuid']);
      if (idx >= 0) {
        _fallbackIncidents[idx] = map;
      } else {
        _fallbackIncidents.add(map);
      }
      return 1;
    }

    return await db.insert(
      'incidents',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Fetches all stored incidents.
  Future<List<Map<String, dynamic>>> getAllIncidents({String? userId}) async {
    final db = await database;
    if (db == null) {
      return List.from(_fallbackIncidents);
    }
    String? where;
    List<dynamic>? args;

    if (userId != null && userId.isNotEmpty) {
      where = "user_id = ? OR user_id IS NULL";
      args = [userId];
    }

    return await db.query(
      'incidents',
      where: where,
      whereArgs: args,
      orderBy: 'created_at DESC',
    );
  }

  /// Fetches pending unsynchronized incidents.
  Future<List<Map<String, dynamic>>> getPendingIncidents() async {
    final db = await database;
    if (db == null) {
      return _fallbackIncidents.where((i) => i['sync_status'] == 'pending').toList();
    }
    return await db.query(
      'incidents',
      where: "sync_status = 'pending'",
      orderBy: 'created_at ASC',
    );
  }

  /// Marks an incident as synchronized.
  Future<void> markIncidentSynced(String clientIncidentUuid, int serverId) async {
    final db = await database;
    if (db == null) {
      final idx = _fallbackIncidents.indexWhere((i) => i['client_incident_uuid'] == clientIncidentUuid);
      if (idx >= 0) {
        _fallbackIncidents[idx]['server_id'] = serverId;
        _fallbackIncidents[idx]['sync_status'] = 'synced';
      }
      return;
    }
    await db.update(
      'incidents',
      {
        'server_id': serverId,
        'sync_status': 'synced',
      },
      where: 'client_incident_uuid = ?',
      whereArgs: [clientIncidentUuid],
    );
  }

  // ===========================================================================
  // ACTIVITY AUDIT LOGS REPOSITORY
  // ===========================================================================

  /// Logs a safety event into the immutable local audit log.
  Future<int> logActivity({
    required String eventType,
    required String action,
    required String category,
    String? details,
    String? userId,
    int? serverId,
    String syncStatus = 'synced',
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final row = {
      'server_id': serverId,
      'client_uuid': generateUuid(),
      'user_id': userId,
      'event_type': eventType,
      'action': action,
      'category': category,
      'details': details,
      'timestamp': now,
      'sync_status': syncStatus,
    };

    final db = await database;
    if (db == null) {
      _fallbackLogs.insert(0, row);
      return 1;
    }
    return await db.insert('activity_logs', row);
  }

  /// Fetches audit logs with optional category filter.
  Future<List<Map<String, dynamic>>> getActivityLogs({
    String? userId,
    String? category,
    int limit = 50,
  }) async {
    final db = await database;
    if (db == null) {
      return _fallbackLogs.where((l) {
        if (category != null && category != 'ALL' && l['category'] != category) return false;
        if (userId != null && userId.isNotEmpty && l['user_id'] != null && l['user_id'] != userId) return false;
        return true;
      }).take(limit).toList();
    }

    String? where;
    List<dynamic> args = [];

    if (category != null && category != 'ALL') {
      where = "category = ?";
      args.add(category);
    }

    if (userId != null && userId.isNotEmpty) {
      where = (where == null) ? "user_id = ? OR user_id IS NULL" : "$where AND (user_id = ? OR user_id IS NULL)";
      args.add(userId);
    }

    return await db.query(
      'activity_logs',
      where: where,
      whereArgs: args.isNotEmpty ? args : null,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
  }

  // ===========================================================================
  // MONITORING & SENSOR TELEMETRY REPOSITORY
  // ===========================================================================

  /// Caches a sensor telemetry reading offline.
  Future<int> saveMonitoringRecord(Map<String, dynamic> record) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final map = Map<String, dynamic>.from(record);
    map.putIfAbsent('client_uuid', () => generateUuid());
    map.putIfAbsent('recorded_at', () => now);
    map.putIfAbsent('sync_status', () => 'pending');

    final db = await database;
    if (db == null) {
      _fallbackMonitoring.add(map);
      return 1;
    }

    return await db.insert(
      'monitoring_records',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Clears all local tables (e.g., on explicit user sign out).
  Future<void> clearAllData() async {
    _fallbackContacts.clear();
    _fallbackCheckIns.clear();
    _fallbackIncidents.clear();
    _fallbackLogs.clear();
    _fallbackMonitoring.clear();

    final db = await database;
    if (db != null) {
      await db.delete('contacts');
      await db.delete('check_ins');
      await db.delete('incidents');
      await db.delete('activity_logs');
      await db.delete('monitoring_records');
    }
  }
}
