import 'dart:io';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'backup_scheduler.dart';
import 'backup_store.dart';
import 'database_helper.dart';

class GoogleAuthClient extends http.BaseClient {
  GoogleAuthClient(this._headers);
  final Map<String, String> _headers;
  final http.Client _client = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers.addAll(_headers);
    final response =
        await _client.send(request).timeout(const Duration(seconds: 30));
    return http.StreamedResponse(
        response.stream.timeout(const Duration(seconds: 30)),
        response.statusCode,
        headers: response.headers,
        request: response.request,
        contentLength: response.contentLength,
        reasonPhrase: response.reasonPhrase);
  }

  @override
  void close() {
    _client.close();
    super.close();
  }
}

class RemoteBackup {
  const RemoteBackup(this.id, this.name, this.modified, this.size);
  final String id;
  final String name;
  final DateTime? modified;
  final String? size;
}

class PreparedBackup {
  PreparedBackup(
      this.remote, this.directory, this.path, this.summary, this.email);
  final RemoteBackup remote;
  final Directory directory;
  final String path;
  final BackupSummary summary;
  final String email;
  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

class DriveService {
  DriveService(
      {GoogleSignIn? googleSignIn,
      DatabaseHelper? database,
      BackupStore? store,
      BackupScheduler? scheduler,
      http.Client Function(Map<String, String>)? clientFactory,
      DateTime Function()? now})
      : _googleSignIn = googleSignIn ??
            GoogleSignIn(scopes: [drive.DriveApi.driveFileScope]),
        _database = database ?? DatabaseHelper.instance,
        store = store ?? BackupStore.instance,
        scheduler = scheduler ?? BackupScheduler(),
        _clientFactory = clientFactory ?? GoogleAuthClient.new,
        _now = now ?? DateTime.now;
  static final instance = DriveService();
  static const backupName = 'gestao_horarios_backup_v3.db';
  final GoogleSignIn _googleSignIn;
  final DatabaseHelper _database;
  final BackupStore store;
  final BackupScheduler scheduler;
  final http.Client Function(Map<String, String>) _clientFactory;
  final DateTime Function() _now;

  bool get estaAutenticado => _googleSignIn.currentUser != null;
  String? get emailContaAtiva => _googleSignIn.currentUser?.email;
  Future<GoogleSignInAccount?> _account() async =>
      _googleSignIn.currentUser ??
      await _googleSignIn
          .signInSilently(suppressErrors: false)
          .timeout(const Duration(seconds: 20));
  Future<http.Client> _client(GoogleSignInAccount account) async =>
      _clientFactory(
          await account.authHeaders.timeout(const Duration(seconds: 20)));
  void _checkAccount(GoogleSignInAccount? account, BackupSettings state) {
    if (account == null || account.email != state.email) {
      throw StateError(
          'A conta Google mudou. Ligue novamente a conta antes de continuar.');
    }
  }

  Future<bool> iniciarSessao(void Function(String) feedback) async {
    try {
      // Pausa os envios antes de permitir uma mudança de conta ou de dados.
      await store.locked((txn, state) async {
        await store.save(txn,
            BackupSettings(email: state.email, lastSuccess: state.lastSuccess));
        await scheduler.cancel();
      });
      final account = await _googleSignIn.signIn();
      if (account == null) {
        feedback('Autenticação cancelada.');
        return false;
      }
      await store.locked((txn, state) async {
        await store.save(
            txn,
            BackupSettings(
                email: account.email,
                lastSuccess:
                    state.email == account.email ? state.lastSuccess : null));
      });
      return true;
    } on PlatformException catch (e) {
      feedback(e.message?.contains('10:') == true
          ? 'A ligação Google não está configurada para esta versão da aplicação (erro 10).'
          : 'Erro ao ligar a conta Google (${e.code}): ${e.message ?? ''}');
      return false;
    } catch (e) {
      feedback('Erro ao ligar a conta Google: $e');
      return false;
    }
  }

  Future<BackupSummary> resumoLocal() => _database.resumoAtual();

  Future<void> pausarParaEscolherDados() => store.locked((txn, state) async {
        final account = await _account();
        if (account == null) throw StateError('Ligue primeiro a conta Google.');
        await store.save(
            txn,
            BackupSettings(
                email: account.email,
                lastSuccess:
                    state.email == account.email ? state.lastSuccess : null));
        await scheduler.cancel();
      });

  Future<void> manterDadosAtuais() => store.locked((txn, state) async {
        final account = await _account();
        if (account == null) throw StateError('Ligue primeiro a conta Google.');
        await store.save(
            txn,
            BackupSettings(
                email: account.email,
                ready: true,
                lastSuccess:
                    state.email == account.email ? state.lastSuccess : null));
      });

  Future<void> terminarSessao() => store.locked((txn, state) async {
        await store.save(txn,
            BackupSettings(email: state.email, lastSuccess: state.lastSuccess));
        await scheduler.cancel();
        await _googleSignIn.signOut();
      });

  Future<bool> recuperarSessaoAoAbrir(void Function(String) feedback) async {
    try {
      return await _account() != null;
    } catch (e) {
      feedback('Não foi possível recuperar a sessão Google: $e');
      return false;
    }
  }

  Future<void> definirAutomatico(bool value) async {
    await store.locked((txn, state) async {
      _checkAccount(await _account(), state);
      if (!state.ready) {
        throw StateError('Escolha primeiro os dados que pretende manter.');
      }
      if (value && !scheduler.supported) {
        throw UnsupportedError(
            'As cópias em segundo plano estão disponíveis no Android.');
      }
      if (value) await scheduler.schedule();
      await store.save(
          txn,
          BackupSettings(
              email: state.email,
              ready: true,
              automatic: value,
              lastSuccess: state.lastSuccess,
              lastError: state.lastError));
      if (!value) await scheduler.cancel();
    });
    if (value) await enviarSeNecessario();
  }

  Future<void> recuperarAgendamento() async {
    await store.locked((_, state) async {
      if (state.automatic && state.ready && state.email == emailContaAtiva) {
        await scheduler.schedule();
      } else {
        await scheduler.cancel();
      }
    });
    await enviarSeNecessario();
  }

  Future<bool> enviarSeNecessario() => fazerUploadBackup(automatic: true);

  Future<bool> fazerUploadBackup(
          {void Function(String)? onFeedback, bool automatic = false}) =>
      store.locked((txn, state) async {
        if (automatic && !state.due(_now())) return true;
        http.Client? client;
        try {
          if (!state.ready) {
            throw StateError(
                'Escolha primeiro se quer manter os dados locais ou carregar uma cópia do Drive.');
          }
          final account = await _account();
          _checkAccount(account, state);
          onFeedback?.call('A enviar cópia para o Google Drive...');
          client = await _client(account!);
          final api = drive.DriveApi(client);
          final bytes = await _database.lerCopiaSeguranca();
          final files = await api.files.list(
              q: "name = '$backupName' and trashed = false",
              orderBy: 'modifiedTime desc',
              pageSize: 1,
              $fields: 'files(id)');
          final metadata = drive.File()..name = backupName;
          final media = drive.Media(Stream.value(bytes), bytes.length);
          if (files.files?.isNotEmpty == true) {
            await api.files
                .update(metadata, files.files!.first.id!, uploadMedia: media);
          } else {
            await api.files.create(metadata, uploadMedia: media);
          }
          await store.save(
              txn,
              BackupSettings(
                  email: state.email,
                  ready: true,
                  automatic: state.automatic,
                  lastSuccess: _now().toUtc()));
          onFeedback?.call(
              'Cópia de segurança guardada com sucesso no Google Drive.');
          return true;
        } catch (e) {
          final error = 'Não foi possível enviar a cópia: $e';
          await store.save(
              txn,
              BackupSettings(
                  email: state.email,
                  ready: state.ready,
                  automatic: state.automatic,
                  lastSuccess: state.lastSuccess,
                  lastError: error));
          onFeedback?.call(error);
          return false;
        } finally {
          client?.close();
        }
      });

  Future<List<RemoteBackup>> procurarCopias() => store.locked((_, state) async {
        final account = await _account();
        _checkAccount(account, state);
        final client = await _client(account!);
        try {
          final api = drive.DriveApi(client);
          final result = <RemoteBackup>[];
          String? page;
          do {
            final files = await api.files.list(
                q: "(name = '$backupName' or name contains 'gestao_horarios_backup_') and trashed = false",
                orderBy: 'modifiedTime desc',
                pageSize: 100,
                pageToken: page,
                $fields: 'nextPageToken,files(id,name,modifiedTime,size)');
            result.addAll((files.files ?? []).where((f) => f.id != null).map(
                (f) => RemoteBackup(
                    f.id!, f.name ?? backupName, f.modifiedTime, f.size)));
            page = files.nextPageToken;
          } while (page != null && page.isNotEmpty);
          return result;
        } finally {
          client.close();
        }
      });

  Future<PreparedBackup> prepararRestauro(RemoteBackup remote) =>
      store.locked((_, state) async {
        final account = await _account();
        _checkAccount(account, state);
        final client = await _client(account!);
        final directory =
            await Directory.systemTemp.createTemp('horarios_drive_restore_');
        try {
          final media = await drive.DriveApi(client).files.get(remote.id,
              downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
          final file = File('${directory.path}/backup.db');
          final sink = file.openWrite();
          try {
            await sink.addStream(media.stream);
          } finally {
            await sink.close();
          }
          final summary = await DatabaseHelper.inspecionarCopia(file.path);
          return PreparedBackup(
              remote, directory, file.path, summary, account.email);
        } catch (_) {
          await directory.delete(recursive: true);
          rethrow;
        } finally {
          client.close();
        }
      });

  Future<bool> restaurarCopia(PreparedBackup backup) =>
      store.locked((txn, state) async {
        final account = await _account();
        _checkAccount(account, state);
        if (backup.email != account!.email) {
          throw StateError('A cópia pertence à conta anterior.');
        }
        final ok = await _database.restaurarBaseDeDados(backup.path);
        if (ok) {
          await store.save(
              txn, BackupSettings(email: account.email, ready: true));
          await scheduler.cancel();
        }
        return ok;
      });

  Future<bool> restaurarFicheiroLocal(String path) =>
      store.locked((_, state) async => _database.restaurarBaseDeDados(path));
}
