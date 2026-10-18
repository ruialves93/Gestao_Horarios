import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_horarios/services/database_helper.dart';
import 'package:sqflite/sqflite.dart';

class TestDatabase extends Fake implements Database {
  TestDatabase(this.path);
  @override
  final String path;
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql,
      [List<Object?>? arguments]) async => [{'journal_mode': 'delete'}];
  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action,
      {bool? exclusive}) => action(TestTransaction());
}

class TestTransaction extends Fake implements Transaction {
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql,
      [List<Object?>? arguments]) async => [{'count(*)': 2}];
}

class TestPicker extends FilePicker {
  String? destination;
  Uint8List? receivedBytes;
  @override
  Future<String?> saveFile({String? dialogTitle, String? fileName,
      String? initialDirectory, FileType type = FileType.any,
      List<String>? allowedExtensions, Uint8List? bytes,
      bool lockParentWindow = false}) async {
    receivedBytes = bytes;
    return destination;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late DatabaseHelper helper;
  late TestPicker picker;

  final contents = Uint8List.fromList([83, 81, 76, 105, 116, 101]);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('horarios_backup_');
    final databaseFile = File('${directory.path}/gestao_horarios.db');
    await databaseFile.writeAsBytes(contents);
    helper = DatabaseHelper.forTesting(TestDatabase(databaseFile.path));

    picker = TestPicker();
    FilePicker.platform = picker;
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;

    await directory.delete(recursive: true);
  });

  test('Android export accepts a content URI without rewriting the file', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    picker.destination = 'content://com.android.providers.documents/backup.db';
    expect(await helper.exportarEGuardarBaseDeDados(), isTrue);
    expect(picker.receivedBytes, contents);
  });

  test('desktop export writes the selected file', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    picker.destination = '${directory.path}/backup.db';
    expect(await helper.exportarEGuardarBaseDeDados(), isTrue);
    expect(await File(picker.destination!).readAsBytes(), contents);
    expect(picker.receivedBytes, isNull);
  });

  test('cancelling export creates no backup', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(await helper.exportarEGuardarBaseDeDados(), isFalse);
  });

  test('cloud snapshot reads the database actually opened by the app', () async {
    expect(await helper.lerCopiaSeguranca(), contents);
  });
}
