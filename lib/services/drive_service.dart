import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }
}

class DriveService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: <String>[
      drive.DriveApi.driveFileScope,
      drive.DriveApi.driveAppdataScope,
    ],
  );

  static bool get estaAutenticado => _googleSignIn.currentUser != null;
  static String? get emailContaAtiva => _googleSignIn.currentUser?.email;

  static Future<bool> iniciarSessao(Function(String) onFeedback) async {
    try {
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account == null) {
        onFeedback('Autenticação cancelada.');
        return false;
      }
      onFeedback('Sessão iniciada: ${account.email}');
      return true;
    } catch (e) {
      onFeedback('Erro ao iniciar sessão: $e');
      return false;
    }
  }

  static Future<void> terminarSessao() async {
    await _googleSignIn.signOut();
  }

  static Future<bool> fazerUploadBackup({Function(String)? onFeedback}) async {
    try {
      GoogleSignInAccount? account = _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();
      if (account == null) {
        if (onFeedback != null) onFeedback('Sem sessão Google ativa.');
        return false;
      }

      if (onFeedback != null) onFeedback('A enviar cópia para o Google Drive...');
      final headers = await account.authHeaders;
      final client = GoogleAuthClient(headers);
      final driveApi = drive.DriveApi(client);

      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'gestao_horarios_v3.db');
      final localFile = File(path);

      if (!await localFile.exists()) return false;

      final fileList = await driveApi.files.list(
        q: "name = 'gestao_horarios_backup_v3.db' and trashed = false",
      );

      var media = drive.Media(localFile.openRead(), localFile.lengthSync());
      drive.File fileMetadata = drive.File();
      fileMetadata.name = 'gestao_horarios_backup_v3.db';

      if (fileList.files != null && fileList.files!.isNotEmpty) {
        final fileId = fileList.files!.first.id!;
        await driveApi.files.update(fileMetadata, fileId, uploadMedia: media);
        if (onFeedback != null) onFeedback('Cópia de segurança atualizada com sucesso no Drive!');
      } else {
        await driveApi.files.create(fileMetadata, uploadMedia: media);
        if (onFeedback != null) onFeedback('Cópia de segurança enviada com sucesso para o Drive!');
      }
      return true;
    } catch (e) {
      if (onFeedback != null) onFeedback('Erro ao enviar backup: $e');
      return false;
    }
  }

  static Future<bool> sincronizarAoAbrir(Function(String) onFeedback) async {
    try {
      GoogleSignInAccount? account = _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();
      if (account == null) return false;

      final headers = await account.authHeaders;
      final client = GoogleAuthClient(headers);
      final driveApi = drive.DriveApi(client);

      final fileList = await driveApi.files.list(
        q: "name = 'gestao_horarios_backup_v3.db' and trashed = false",
      );

      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'gestao_horarios_v3.db');

      if (fileList.files != null && fileList.files!.isNotEmpty) {
        final fileId = fileList.files!.first.id!;
        drive.Media media = await driveApi.files.get(
          fileId,
          downloadOptions: drive.DownloadOptions.fullMedia,
        ) as drive.Media;

        final File localFile = File(path);
        List<int> dataBytes = [];
        await for (var data in media.stream) {
          dataBytes.addAll(data);
        }
        await localFile.writeAsBytes(dataBytes);
        onFeedback('Dados sincronizados do Drive (${account.email})');
      } else {
        await fazerUploadBackup(onFeedback: onFeedback);
      }
      return true;
    } catch (e) {
      return false;
    }
  }
}