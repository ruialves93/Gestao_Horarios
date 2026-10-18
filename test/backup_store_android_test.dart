import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqlite3/sqlite3.dart' as native;
import 'package:gestao_horarios/services/backup_store.dart';

/// Uses the real sqflite channel path with Android's restriction on row-returning
/// PRAGMAs. Desktop FFI accepts execute(PRAGMA busy_timeout) and misses this bug.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.tekartik.sqflite');
  late Directory directory;
  native.Database? connection;
  late BackupStore store;
  int transactionId = 0;
  int timeoutQueries = 0;
  setUp(() async {
    directory =
        await Directory.systemTemp.createTemp('horarios_android_sqlite_');
    store = BackupStore(path: p.join(directory.path, 'control.db'));
    databaseFactory = databaseFactorySqflitePlugin;
    timeoutQueries = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = (call.arguments as Map?) ?? {};
      switch (call.method) {
        case 'openDatabase':
          connection = native.sqlite3.open(args['path'] as String);
          return {'id': 1};
        case 'execute':
          final sql = args['sql'] as String;
          if (sql.toUpperCase().startsWith('PRAGMA BUSY_TIMEOUT')) {
            throw PlatformException(
                code: 'sqlite_error',
                message:
                    'Queries can be performed using SQLiteDatabase query or rawQuery methods only.');
          }
          connection!.execute(sql, (args['arguments'] as List?) ?? []);
          return args['inTransaction'] == true
              ? {'transactionId': ++transactionId}
              : null;
        case 'query':
          final sql = args['sql'] as String;
          if (sql.toUpperCase().startsWith('PRAGMA BUSY_TIMEOUT'))
            timeoutQueries++;
          final result =
              connection!.select(sql, (args['arguments'] as List?) ?? []);
          return {
            'columns': result.columnNames,
            'rows': result.map((row) => row.values.toList()).toList()
          };
        case 'insert':
          connection!.execute(
              args['sql'] as String, (args['arguments'] as List?) ?? []);
          return connection!.lastInsertRowId;
        case 'closeDatabase':
          connection?.dispose();
          connection = null;
          return null;
        default:
          throw UnsupportedError(
              'Unexpected SQLite channel call: ${call.method}');
      }
    });
  });
  tearDown(() async {
    await store.close();
    connection?.dispose();
    connection = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });
  test('Android opens backup settings using a query for busy_timeout',
      () async {
    final state = await store.read();
    expect(state.ready, isFalse);
    expect(timeoutQueries, 1);
    expect(
        connection!.select('PRAGMA busy_timeout').first.values.single, 60000);
  });
  test('Android can save and reload automatic copy settings', () async {
    final date = DateTime.utc(2026, 10, 18, 12);
    await store.locked((txn, _) => store.save(
        txn,
        BackupSettings(
            email: 'test@example.com',
            ready: true,
            automatic: true,
            lastSuccess: date)));
    await store.close();
    final state = await store.read();
    expect(state.email, 'test@example.com');
    expect(state.automatic, isTrue);
    expect(state.lastSuccess, date);
    expect(timeoutQueries, 2);
  });
}
