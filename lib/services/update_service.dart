import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:install_plugin/install_plugin.dart';

class UpdateService {
  // CONFIGURAÇÃO DO SEU REPOSITÓRIO GITHUB
  static const String repoOwner = 'ruibarata'; // O seu nome de utilizador no GitHub
  static const String repoName = 'gestao_horarios'; // Nome do repositório

  static Future<void> verificarAtualizacao(BuildContext context) async {
    try {
      final url = Uri.parse('https://api.github.com/repos/$repoOwner/$repoName/releases/latest');
      final response = await http.get(url, headers: {'Accept': 'application/vnd.github.v3+json'});

      if (response.statusCode != 200) return;

      final data = json.decode(response.body);
      final String tagRemota = data['tag_name']?.toString().replaceAll('v', '').trim() ?? '';
      final List assets = data['assets'] ?? [];

      if (tagRemota.isEmpty || assets.isEmpty) return;

      // Encontrar o ficheiro .apk nos anexos do Release
      String? apkDownloadUrl;
      for (var asset in assets) {
        if (asset['name'].toString().endsWith('.apk')) {
          apkDownloadUrl = asset['browser_download_url'];
          break;
        }
      }

      if (apkDownloadUrl == null) return;

      final packageInfo = await PackageInfo.fromPlatform();
      final String versaoLocal = packageInfo.version.trim();

      if (_existeNovaVersao(versaoLocal, tagRemota)) {
        if (!context.mounted) return;
        _iniciarDescarregamentoEInstalacao(context, apkDownloadUrl, tagRemota);
      }
    } catch (_) {
      // Falha de rede ou repositório offline silenciosa para não incomodar o utilizador
    }
  }

  static bool _existeNovaVersao(String local, String remota) {
    List<int> partesLocal = local.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    List<int> partesRemota = remota.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < partesRemota.length; i++) {
      int vRemota = partesRemota[i];
      int vLocal = i < partesLocal.length ? partesLocal[i] : 0;
      if (vRemota > vLocal) return true;
      if (vRemota < vLocal) return false;
    }
    return false;
  }

  static void _iniciarDescarregamentoEInstalacao(
      BuildContext context, String url, String versaoNova) {
    double progresso = 0.0;
    bool descarregando = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Text('A atualizar para v$versaoNova'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: progresso > 0 ? progresso : null),
                const SizedBox(height: 12),
                Text(
                  descarregando
                      ? 'A transferir atualização: ${(progresso * 100).toStringAsFixed(0)}%'
                      : 'A iniciar instalação...',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          );
        },
      ),
    );

    _descarregarEInstalar(url, (p) {
      progresso = p;
    }, () {
      if (context.mounted) Navigator.pop(context);
    });
  }

  static Future<void> _descarregarEInstalar(
      String url, Function(double) onProgress, VoidCallback onFinish) async {
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);

      final totalBytes = response.contentLength ?? 0;
      int recebidos = 0;

      final tempDir = await getTemporaryDirectory();
      final apkFile = File('${tempDir.path}/app_update.apk');
      final sink = apkFile.openWrite();

      await response.stream.listen((chunk) {
        sink.add(chunk);
        recebidos += chunk.length;
        if (totalBytes > 0) {
          onProgress(recebidos / totalBytes);
        }
      }).asFuture();

      await sink.close();
      onFinish();

      // Dispara a janela de instalação nativa do Android imediatamente
      await InstallPlugin.install(apkFile.path);
    } catch (_) {
      onFinish();
    }
  }
}