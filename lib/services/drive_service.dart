import 'package:flutter/services.dart';
import 'database_helper.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }

  @override
  void close() {
    _client.close();
    super.close();
  }
}

class DriveService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: <String>[
      drive.DriveApi.driveFileScope,
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
    } on PlatformException catch (e) {
      if (e.message?.contains('10:') == true || e.message?.contains('ApiException: 10') == true) {
        onFeedback('A ligação Google não está configurada para esta versão da aplicação (erro 10). Contacte o responsável pela aplicação.');
      } else {
        onFeedback('Erro ao ligar a conta Google (${e.code}): ${e.message ?? ''}');
      }
      return false;
    } catch (e) {
      onFeedback('Erro ao iniciar sessão: $e');
      return false;
    }
  }

  static Future<void> terminarSessao() async {
    await _googleSignIn.signOut();
  }

  static Future<bool> fazerUploadBackup({Function(String)? onFeedback}) async {
    GoogleAuthClient? client;
    try {
      GoogleSignInAccount? account = _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();
      if (account == null) {
        if (onFeedback != null) onFeedback('Sem sessão Google ativa.');
        return false;
      }

      if (onFeedback != null) onFeedback('A enviar cópia para o Google Drive...');
      final headers = await account.authHeaders;
      client = GoogleAuthClient(headers);
      final driveApi = drive.DriveApi(client);

      final bytes = await DatabaseHelper.instance.lerCopiaSeguranca();

      final fileList = await driveApi.files.list(
        q: "name = 'gestao_horarios_backup_v3.db' and trashed = false",
      );

      var media = drive.Media(Stream.value(bytes), bytes.length);
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
    } finally {
      client?.close();
    }
  }

  /// Recupera apenas a sessão. Um restauro nunca deve substituir dados ao abrir.
  static Future<bool> recuperarSessaoAoAbrir(Function(String) onFeedback) async {
    try {
      final account = _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();
      return account != null;
    } catch (e) {
      onFeedback('Não foi possível recuperar a sessão Google: $e');
      return false;
    }
  }
}