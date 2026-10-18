import 'dart:io';
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';
import 'backup_store.dart';
import 'database_helper.dart';
import 'drive_service.dart';

@pragma('vm:entry-point')
void backupCallbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    if (task != BackupScheduler.taskName) return true;
    try {
      return await DriveService.instance.enviarSeNecessario();
    } finally {
      await DatabaseHelper.instance.fechar();
      await BackupStore.instance.close();
    }
  });
}

class BackupScheduler {
  static const taskName = 'gestao_horarios.drive.daily';
  static const uniqueName = 'gestao_horarios.drive.daily.unique';
  bool get supported => Platform.isAndroid;
  Future<void> initialize() async {
    if (supported) await Workmanager().initialize(backupCallbackDispatcher);
  }

  Future<void> schedule() async {
    if (!supported) return;
    // Verifica vencimentos e recupera falhas de rede; só envia após 24h de sucesso.
    await Workmanager().registerPeriodicTask(uniqueName, taskName,
        frequency: const Duration(hours: 1),
        initialDelay: const Duration(hours: 1),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        constraints: Constraints(networkType: NetworkType.connected),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(minutes: 15));
  }

  Future<void> cancel() async {
    if (supported) await Workmanager().cancelByUniqueName(uniqueName);
  }
}
