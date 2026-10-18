import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class BackupSettings {
  const BackupSettings(
      {this.email,
      this.ready = false,
      this.automatic = false,
      this.lastSuccess,
      this.lastError});
  final String? email;
  final bool ready;
  final bool automatic;
  final DateTime? lastSuccess;
  final String? lastError;

  bool due(DateTime now) =>
      ready &&
      automatic &&
      email != null &&
      (lastSuccess == null ||
          now.toUtc().difference(lastSuccess!.toUtc()) >=
              const Duration(hours: 24));

  Map<String, Object?> toJson() => {
        'email': email,
        'ready': ready,
        'automatic': automatic,
        'lastSuccess': lastSuccess?.toUtc().toIso8601String(),
        'lastError': lastError
      };
  factory BackupSettings.fromJson(Map<String, dynamic> json) => BackupSettings(
      email: json['email'] as String?,
      ready: json['ready'] == true,
      automatic: json['automatic'] == true,
      lastSuccess: DateTime.tryParse(json['lastSuccess']?.toString() ?? ''),
      lastError: json['lastError'] as String?);
}

/// Ficheiro separado: o restauro dos dados não altera a conta nem o agendamento.
/// A transação serializa envios, restauros e mudanças de conta entre isolates.
class BackupStore {
  BackupStore({this.path});
  static final instance = BackupStore();
  final String? path;
  Database? _db;
  Future<Database> get database async => _db ??= await openDatabase(
          path ?? p.join(await getDatabasesPath(), 'cloud_backup_control.db'),
          version: 1, onConfigure: (db) async {
        // Este PRAGMA devolve uma linha; o Android exige rawQuery.
        await db.rawQuery('PRAGMA busy_timeout = 60000');
      }, onCreate: (db, _) async {
        await db.execute(
            'CREATE TABLE settings (id INTEGER PRIMARY KEY, value TEXT NOT NULL)');
      });
  Future<T> locked<T>(
      Future<T> Function(Transaction txn, BackupSettings state) action) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query('settings', where: 'id = 1');
      final state = rows.isEmpty
          ? const BackupSettings()
          : BackupSettings.fromJson(jsonDecode(rows.first['value'] as String)
              as Map<String, dynamic>);
      return action(txn, state);
    }, exclusive: true);
  }

  Future<BackupSettings> read() => locked((_, state) async => state);
  Future<void> save(Transaction txn, BackupSettings state) async {
    await txn.insert('settings', {'id': 1, 'value': jsonEncode(state.toJson())},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
