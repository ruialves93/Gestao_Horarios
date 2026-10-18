import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/backup_store.dart';
import '../services/database_helper.dart';
import '../services/drive_service.dart';

String _date(DateTime date) =>
    DateFormat('dd/MM/yyyy HH:mm').format(date.toLocal());
String _recordDate(String? date) => date == null
    ? 'sem registos'
    : DateTime.tryParse(date) == null
        ? date
        : DateFormat('dd/MM/yyyy').format(DateTime.parse(date));

Future<bool> escolherDadosGoogle(
        BuildContext context, DriveService service) async =>
    await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _AccountDataDialog(service: service)) ??
    false;

class _AccountDataDialog extends StatefulWidget {
  const _AccountDataDialog({required this.service});
  final DriveService service;
  @override
  State<_AccountDataDialog> createState() => _AccountDataDialogState();
}

class _AccountDataDialogState extends State<_AccountDataDialog> {
  bool _busy = false;
  String? _error;
  List<RemoteBackup>? _files;
  PreparedBackup? _prepared;
  BackupSummary? _local;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _search() => _run(() async {
        final files = await widget.service.procurarCopias();
        if (mounted) setState(() => _files = files);
      });
  Future<void> _prepare(RemoteBackup remote) => _run(() async {
        final prepared = await widget.service.prepararRestauro(remote);
        if (!mounted) {
          await prepared.dispose();
          return;
        }
        _prepared = prepared;
        final local = await widget.service.resumoLocal();
        if (mounted) setState(() => _local = local);
      });
  Future<void> _keep() => _run(() async {
        await widget.service.manterDadosAtuais();
        if (mounted) Navigator.of(context).pop(true);
      });
  Future<void> _restore() => _run(() async {
        final ok = await widget.service.restaurarCopia(_prepared!);
        if (!ok) {
          throw StateError(
              'Não foi possível restaurar. Os dados anteriores foram mantidos.');
        }
        if (mounted) Navigator.of(context).pop(true);
      });
  @override
  void dispose() {
    final prepared = _prepared;
    if (prepared != null) unawaited(prepared.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prepared = _prepared;
    final older = prepared?.summary.lastDate != null &&
        _local?.lastDate != null &&
        prepared!.summary.lastDate!.compareTo(_local!.lastDate!) < 0;
    return PopScope(
        canPop: !_busy,
        child: AlertDialog(
          title: Text(prepared != null
              ? 'Carregar esta cópia?'
              : 'Que dados pretende usar?'),
          content: SizedBox(
              width: double.maxFinite,
              child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * .6),
                  child: SingleChildScrollView(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(widget.service.emailContaAtiva ?? ''),
                        const SizedBox(height: 12),
                        if (_busy)
                          const Center(child: CircularProgressIndicator()),
                        if (_error != null) ...[
                          Text(_error!,
                              style: const TextStyle(color: Colors.red)),
                          const SizedBox(height: 12),
                        ],
                        if (prepared != null) ...[
                          Text(prepared.remote.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          Text('${prepared.summary.records} registos'),
                          Text(
                              'De ${_recordDate(prepared.summary.firstDate)} até ${_recordDate(prepared.summary.lastDate)}'),
                          const SizedBox(height: 12),
                          if (_local != null)
                            Text(
                                'Na aplicação: ${_local!.records} registos, até ${_recordDate(_local!.lastDate)}.'),
                          if (older || prepared.summary.records == 0)
                            const Padding(
                                padding: EdgeInsets.only(top: 12),
                                child: Text(
                                    'Atenção: esta cópia pode não conter os seus dados mais recentes.',
                                    style: TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.bold))),
                          const SizedBox(height: 12),
                          const Text(
                              'Carregar esta cópia substitui os dados atuais. Será preservada uma cópia local dos dados anteriores.'),
                        ] else if (_files != null) ...[
                          if (_files!.isEmpty)
                            const Text(
                                'Não foram encontradas cópias criadas por esta aplicação nesta conta.'),
                          ..._files!.map((file) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(file.name),
                              subtitle: Text(file.modified == null
                                  ? 'Data desconhecida'
                                  : _date(file.modified!)),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: _busy ? null : () => _prepare(file))),
                        ] else ...[
                          const Text(
                              'Pode manter a informação que já está na aplicação ou procurar uma cópia no Google Drive.'),
                          const SizedBox(height: 8),
                          const Text(
                              'Os envios ficam pausados até concluir esta escolha. Nenhum dado será substituído sem confirmação.'),
                        ],
                      ])))),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            if (prepared != null) ...[
              TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          await prepared.dispose();
                          if (mounted) {
                            setState(() {
                              _prepared = null;
                              _local = null;
                              _error = null;
                            });
                          }
                        },
                  child: const Text('Voltar')),
              FilledButton(
                  onPressed: _busy ? null : _restore,
                  child: const Text('Carregar na aplicação')),
            ] else ...[
              TextButton(
                  onPressed: _busy ? null : _keep,
                  child: const Text('Manter dados atuais')),
              FilledButton(
                  onPressed: _busy ? null : _search,
                  child: Text(_files == null
                      ? 'Procurar no Drive'
                      : 'Procurar novamente')),
            ],
          ],
        ));
  }
}

class DriveBackupDialog extends StatefulWidget {
  const DriveBackupDialog(
      {super.key, required this.service, required this.onUpdated});
  final DriveService service;
  final Future<void> Function() onUpdated;
  @override
  State<DriveBackupDialog> createState() => _DriveBackupDialogState();
}

class _DriveBackupDialogState extends State<DriveBackupDialog> {
  BackupSettings? _settings;
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final settings = await widget.service.store.read();
      if (mounted) {
        setState(() {
          _settings = settings;
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _busy = false;
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) await _refresh();
    }
  }

  void _feedback(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _choose() async {
    await widget.service.pausarParaEscolherDados();
    if (!mounted) return;
    await escolherDadosGoogle(context, widget.service);
    await widget.onUpdated();
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final settings = _settings;
    final ready =
        settings?.ready == true && settings?.email == service.emailContaAtiva;
    return PopScope(
        canPop: !_busy,
        child: AlertDialog(
          title: const Text('Cópias no Google Drive'),
          content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(service.estaAutenticado
                        ? service.emailContaAtiva!
                        : 'Sem conta ligada'),
                    if (_busy)
                      const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator())),
                    if (_error != null)
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    if (!service.estaAutenticado)
                      Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: FilledButton.icon(
                              icon: const Icon(Icons.login),
                              label: const Text('Ligar à conta Google'),
                              onPressed: _busy
                                  ? null
                                  : () => _run(() async {
                                        if (await service.iniciarSessao(
                                            _feedback)) {
                                          await _choose();
                                        }
                                      })))
                    else ...[
                      const SizedBox(height: 12),
                      if (!ready)
                        const Text(
                            'Escolha os dados da conta para permitir os envios.'),
                      SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Cópia automática a cada 24 horas'),
                          subtitle: const Text(
                              'O Android pode adiar o envio por falta de ligação ou poupança de bateria.'),
                          value: ready && settings?.automatic == true,
                          onChanged: _busy ||
                                  !ready ||
                                  !service.scheduler.supported
                              ? null
                              : (value) =>
                                  _run(() => service.definirAutomatico(value))),
                      if (!service.scheduler.supported)
                        const Text(
                            'Agendamento em segundo plano disponível no Android.'),
                      Text(settings?.lastSuccess == null
                          ? 'Ainda não há envios confirmados nesta conta.'
                          : 'Último envio: ${_date(settings!.lastSuccess!)}'),
                      if (settings?.lastError != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(settings!.lastError!,
                                style: const TextStyle(color: Colors.red))),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                          icon: const Icon(Icons.cloud_upload),
                          label: const Text('Enviar cópia agora'),
                          onPressed: _busy || !ready
                              ? null
                              : () => _run(() async {
                                    await service.fazerUploadBackup(
                                        onFeedback: _feedback);
                                  })),
                      TextButton.icon(
                          icon: const Icon(Icons.cloud_download),
                          label: const Text('Escolher dados / procurar cópia'),
                          onPressed: _busy ? null : () => _run(_choose)),
                      TextButton.icon(
                          icon: const Icon(Icons.logout),
                          label: const Text('Desligar conta'),
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                    await service.terminarSessao();
                                    await widget.onUpdated();
                                  })),
                    ],
                  ]))),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('Fechar'))
          ],
        ));
  }
}
