import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:gestao_horarios/services/backup_store.dart';
import 'package:gestao_horarios/services/backup_scheduler.dart';
import 'package:gestao_horarios/services/database_helper.dart';
import 'package:gestao_horarios/services/drive_service.dart';

class TestAccount extends Fake implements GoogleSignInAccount {
  TestAccount(this.email);
  @override
  final String email;
  @override
  Future<Map<String, String>> get authHeaders async =>
      {'Authorization': 'Bearer test'};
}

class TestGoogle extends Fake implements GoogleSignIn {
  TestGoogle(this.active);
  GoogleSignInAccount? active;
  @override
  GoogleSignInAccount? get currentUser => active;
  @override
  Future<GoogleSignInAccount?> signIn() async => active;
  @override
  Future<GoogleSignInAccount?> signInSilently(
          {bool suppressErrors = true, bool reAuthenticate = false}) async =>
      active;
  @override
  Future<GoogleSignInAccount?> signOut() async {
    active = null;
    return null;
  }
}

class TestScheduler extends BackupScheduler {
  int registrations = 0;
  int cancellations = 0;
  @override
  bool get supported => true;
  @override
  Future<void> schedule() async {
    registrations++;
  }

  @override
  Future<void> cancel() async {
    cancellations++;
  }
}

Future<Database> createData(String path, List<String> dates) =>
    openDatabase(path, version: 3, onCreate: (db, _) async {
      await db.execute(
          'CREATE TABLE perfil (id INTEGER PRIMARY KEY, nomeTrabalhador TEXT, salarioBase REAL)');
      await db.insert(
          'perfil', {'id': 1, 'nomeTrabalhador': 'Teste', 'salarioBase': 1000});
      await db.execute(
          'CREATE TABLE registos (id INTEGER PRIMARY KEY, data TEXT UNIQUE, tipoDia TEXT, horasEfetivas REAL, horasContratadas REAL)');
      for (final date in dates) {
        await db.insert('registos', {
          'data': date,
          'tipoDia': 'Trabalho',
          'horasEfetivas': 8,
          'horasContratadas': 8
        });
      }
    });
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  mobile.databaseFactory = databaseFactoryFfi;
  late Directory directory;
  late DatabaseHelper data;
  late BackupStore store;
  late TestScheduler scheduler;
  late TestGoogle google;
  late DriveService service;
  late DateTime now;
  int uploads = 0;
  bool failUpload = false;
  List<int> downloaded = [];
  const remote =
      RemoteBackup('remote-id', 'gestao_horarios_backup_v3.db', null, null);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('horarios_cloud_test_');
    data = DatabaseHelper.forTesting(await createData(
        p.join(directory.path, 'current.db'), ['2026-10-15', '2026-10-16']));
    store = BackupStore(path: p.join(directory.path, 'control.db'));
    scheduler = TestScheduler();
    google = TestGoogle(TestAccount('account@example.com'));
    now = DateTime.utc(2026, 10, 18, 12);
    uploads = 0;
    failUpload = false;
    downloaded = [];
    service = DriveService(
        googleSignIn: google,
        database: data,
        store: store,
        scheduler: scheduler,
        now: () => now,
        clientFactory: (_) => MockClient((request) async {
              if (request.url.queryParameters['alt'] == 'media')
                return http.Response.bytes(downloaded, 200,
                    headers: {'content-type': 'application/octet-stream'});
              if (request.url.path.contains('/upload/')) {
                if (failUpload)
                  return http.Response('{"error":{"message":"offline"}}', 503);
                uploads++;
                return http.Response('{"id":"created-id"}', 200,
                    headers: {'content-type': 'application/json'});
              }
              return http.Response('{"files":[]}', 200,
                  headers: {'content-type': 'application/json'});
            }));
    expect(await service.iniciarSessao((_) {}), isTrue);
  });
  tearDown(() async {
    await data.fechar();
    await store.close();
    await directory.delete(recursive: true);
  });
  test('connecting pauses uploads until the user chooses data', () async {
    expect((await store.read()).ready, isFalse);
    expect(await service.fazerUploadBackup(), isFalse);
    expect(uploads, 0);
    expect((await data.resumoAtual()).lastDate, '2026-10-16');
  });
  test('keeping local data neither uploads nor restores a cloud file',
      () async {
    await service.manterDadosAtuais();
    expect((await store.read()).ready, isTrue);
    expect((await store.read()).automatic, isFalse);
    expect(uploads, 0);
    expect((await data.resumoAtual()).records, 2);
  });
  test('automatic uploads wait exactly 24h after a successful copy and persist',
      () async {
    await service.manterDadosAtuais();
    await service.definirAutomatico(true);
    expect(uploads, 1);
    now = now.add(const Duration(hours: 23, minutes: 59));
    expect(await service.enviarSeNecessario(), isTrue);
    expect(uploads, 1);
    now = now.add(const Duration(minutes: 1));
    await Future.wait(
        [service.enviarSeNecessario(), service.enviarSeNecessario()]);
    expect(uploads, 2);
    await store.close();
    final reopened = BackupStore(path: p.join(directory.path, 'control.db'));
    final state = await reopened.read();
    expect(state.automatic, isTrue);
    expect(state.lastSuccess, now);
    await reopened.close();
  });
  test('manual upload works with automatic backups switched off', () async {
    await service.manterDadosAtuais();
    expect(await service.fazerUploadBackup(), isTrue);
    expect(uploads, 1);
    expect((await store.read()).automatic, isFalse);
    expect((await store.read()).lastSuccess, now);
  });
  test('failed upload preserves last success and remains due for retry',
      () async {
    await service.manterDadosAtuais();
    await service.definirAutomatico(true);
    final first = now;
    now = now.add(const Duration(hours: 24));
    failUpload = true;
    expect(await service.enviarSeNecessario(), isFalse);
    final state = await store.read();
    expect(state.lastSuccess, first);
    expect(state.lastError, isNotNull);
    expect(state.due(now), isTrue);
    failUpload = false;
    expect(await service.enviarSeNecessario(), isTrue);
    expect((await store.read()).lastError, isNull);
    expect(uploads, 2);
  });
  test('another Google account cannot receive the scheduled backup', () async {
    await service.manterDadosAtuais();
    await service.definirAutomatico(true);
    google.active = TestAccount('other@example.com');
    now = now.add(const Duration(hours: 24));
    expect(await service.enviarSeNecessario(), isFalse);
    expect(uploads, 1);
  });
  test('turning automatic copies off and signing out prevents further uploads',
      () async {
    await service.manterDadosAtuais();
    await service.definirAutomatico(true);
    await service.definirAutomatico(false);
    now = now.add(const Duration(hours: 48));
    expect(await service.enviarSeNecessario(), isTrue);
    expect(uploads, 1);
    await service.terminarSessao();
    expect((await store.read()).ready, isFalse);
    expect((await store.read()).automatic, isFalse);
    expect(scheduler.cancellations, greaterThan(0));
  });
  test('corrupt cloud file cannot alter current records', () async {
    downloaded = [1, 2, 3];
    await expectLater(service.prepararRestauro(remote), throwsA(anything));
    expect((await data.resumoAtual()).lastDate, '2026-10-16');
    expect((await data.resumoAtual()).records, 2);
  });
  test(
      'restoration is staged, validated and keeps a recoverable local database',
      () async {
    final cloudPath = p.join(directory.path, 'old-cloud.db');
    final cloud = await createData(cloudPath, ['2026-09-20']);
    await cloud.close();
    downloaded = await File(cloudPath).readAsBytes();
    final prepared = await service.prepararRestauro(remote);
    expect(prepared.summary.records, 1);
    expect(prepared.summary.lastDate, '2026-09-20');
    expect((await data.resumoAtual()).lastDate, '2026-10-16');
    expect(await service.restaurarCopia(prepared), isTrue);
    expect((await data.resumoAtual()).lastDate, '2026-09-20');
    final safety = directory
        .listSync()
        .whereType<File>()
        .singleWhere((f) => f.path.contains('.before-restore-'));
    expect((await DatabaseHelper.inspecionarCopia(safety.path)).lastDate,
        '2026-10-16');
    final restored = await data.database;
    final columns = await restored.rawQuery('PRAGMA table_info(registos)');
    expect(columns.map((r) => r['name']), contains('acaoFolgaTrabalhada'));
    expect((await store.read()).ready, isTrue);
    await prepared.dispose();
  });
  test('an insertion error rolls back all restored rows', () async {
    final path = p.join(directory.path, 'blocked-source.db');
    final source = await createData(path, ['2026-09-20']);
    await source.close();
    final current = await data.database;
    await current.execute(
        "CREATE TRIGGER reject_restore BEFORE INSERT ON registos BEGIN SELECT RAISE(ABORT, 'test rollback'); END");
    expect(await data.restaurarBaseDeDados(path), isFalse);
    expect((await data.resumoAtual()).records, 2);
    expect((await data.resumoAtual()).lastDate, '2026-10-16');
  });
  test('a SQLite database belonging to another application is rejected',
      () async {
    final other = await openDatabase(p.join(directory.path, 'unrelated.db'),
        version: 1,
        onCreate: (db, _) async =>
            db.execute('CREATE TABLE unrelated(id INTEGER)'));
    final path = other.path;
    await other.close();
    expect(await data.restaurarBaseDeDados(path), isFalse);
    expect((await data.resumoAtual()).lastDate, '2026-10-16');
  });
}
