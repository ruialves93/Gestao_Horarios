import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_horarios/screens/drive_backup_dialog.dart';
import 'package:gestao_horarios/services/database_helper.dart';
import 'package:gestao_horarios/services/drive_service.dart';

class ChoiceService extends Fake implements DriveService {
  int keepCalls = 0;
  int restoreCalls = 0;
  PreparedBackup? prepared;
  @override
  String? get emailContaAtiva => 'conta@example.com';
  @override
  Future<void> manterDadosAtuais() async {
    keepCalls++;
  }

  @override
  Future<List<RemoteBackup>> procurarCopias() async =>
      [const RemoteBackup('id', 'gestao_horarios_backup_v3.db', null, null)];
  @override
  Future<PreparedBackup> prepararRestauro(RemoteBackup file) async {
    final dir = await Directory.systemTemp.createTemp('horarios_choice_');
    return prepared = PreparedBackup(
        file,
        dir,
        '${dir.path}/backup.db',
        const BackupSummary(10, '2026-09-07', '2026-09-20'),
        'conta@example.com');
  }

  @override
  Future<BackupSummary> resumoLocal() async =>
      const BackupSummary(30, '2026-09-07', '2026-10-16');
  @override
  Future<bool> restaurarCopia(PreparedBackup backup) async {
    restoreCalls++;
    return true;
  }
}

void main() {
  late ChoiceService service;
  setUp(() {
    service = ChoiceService();
  });
  tearDown(() async {
    await service.prepared?.dispose();
  });
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => escolherDadosGoogle(context, service),
                    child: const Text('Abrir'))))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> selectBackup(WidgetTester tester) async {
    await tester.tap(find.text('Procurar no Drive'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('gestao_horarios_backup_v3.db'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('keeping local data requires no restoration and fits a phone',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('Manter dados atuais'));
    await tester.pumpAndSettle();
    expect(service.keepCalls, 1);
    expect(service.restoreCalls, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'selecting an old cloud backup only previews it; cancelling is safe',
      (tester) async {
    await open(tester);
    await selectBackup(tester);
    expect(find.text('Carregar esta cópia?'), findsOneWidget);
    expect(find.text('10 registos'), findsOneWidget);
    expect(find.textContaining('16/10/2026'), findsOneWidget);
    expect(find.textContaining('pode não conter'), findsOneWidget);
    expect(service.restoreCalls, 0);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(service.restoreCalls, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('restoring only happens after explicit confirmation',
      (tester) async {
    await open(tester);
    await selectBackup(tester);
    await tester.tap(find.text('Carregar na aplicação'));
    await tester.pumpAndSettle();
    expect(service.restoreCalls, 1);
    expect(tester.takeException(), isNull);
  });
}
