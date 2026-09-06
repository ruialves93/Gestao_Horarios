import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

class UpdateService {
  static const String repoOwner = 'ruibarata';
  static const String repoName = 'gestao_horarios';

  static Future<void> verificarEForcarAtualizacao(
    BuildContext context, {
    bool manual = false,
    Function(String msg)? onFeedback,
  }) async {
    try {
      if (manual && onFeedback != null) {
        onFeedback('A verificar atualizações no GitHub...');
      }

      final url = Uri.parse('https://api.github.com/repos/$repoOwner/$repoName/releases/latest');
      final response = await http.get(url, headers: {'Accept': 'application/vnd.github.v3+json'});

      if (response.statusCode != 200) {
        if (manual && onFeedback != null) {
          onFeedback('Não foi possível verificar atualizações (GitHub inacessível).');
        }
        return;
      }

      final data = json.decode(response.body);
      final String tagRemota = data['tag_name']?.toString().replaceAll('v', '').trim() ?? '';
      final List assets = data['assets'] ?? [];

      if (tagRemota.isEmpty || assets.isEmpty) {
        if (manual && onFeedback != null) {
          onFeedback('Nenhum instalador APK disponível na versão remota.');
        }
        return;
      }

      String? apkDownloadUrl;
      for (var asset in assets) {
        if (asset['name'].toString().endsWith('.apk')) {
          apkDownloadUrl = asset['browser_download_url'];
          break;
        }
      }

      if (apkDownloadUrl == null) {
        if (manual && onFeedback != null) {
          onFeedback('Ficheiro APK não encontrado na última release.');
        }
        return;
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final String versaoLocal = packageInfo.version.trim();

      if (_existeNovaVersao(versaoLocal, tagRemota)) {
        if (!context.mounted) return;
        _apresentarBloqueioAtualizacaoObrigatoria(context, apkDownloadUrl, versaoLocal, tagRemota);
      } else {
        if (manual && onFeedback != null) {
          onFeedback('A aplicação já se encontra na versão mais recente (v$versaoLocal).');
        }
      }
    } catch (e) {
      if (manual && onFeedback != null) {
        onFeedback('Erro ao procurar atualização: $e');
      }
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

  static void _apresentarBloqueioAtualizacaoObrigatoria(
    BuildContext context,
    String downloadUrl,
    String versaoAtual,
    String novaVersao,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        double progresso = 0.0;
        bool emDownload = false;
        String statusTexto = 'Uma nova versão está disponível e é necessária para continuar.';

        return StatefulBuilder(
          builder: (context, setState) {
            return PopScope(
              canPop: false,
              child: AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Row(
                  children: const [
                    Icon(Icons.system_update_rounded, color: Colors.orange, size: 28),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Atualização Obrigatória',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Versão instalada: v$versaoAtual', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    Text('Nova versão: v$novaVersao', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green)),
                    const SizedBox(height: 12),
                    Text(statusTexto, style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 16),
                    if (emDownload) ...[
                      LinearProgressIndicator(
                        value: progresso > 0 ? progresso : null,
                        backgroundColor: Colors.grey.shade300,
                        color: Colors.orange,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          progresso > 0 ? '${(progresso * 100).toStringAsFixed(0)}%' : 'A preparar...',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ],
                  ],
                ),
                actions: [
                  if (!emDownload)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A237E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.download),
                        label: const Text('Instalar Atualização Agora', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () {
                          setState(() {
                            emDownload = true;
                            statusTexto = 'A descarregar a atualização...';
                          });

                          _descarregarEInstalar(
                            downloadUrl,
                            onProgress: (p) {
                              setState(() {
                                progresso = p;
                              });
                            },
                            onError: (erro) {
                              setState(() {
                                emDownload = false;
                                statusTexto = 'Erro ao transferir: $erro. Tente novamente.';
                              });
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static Future<void> _descarregarEInstalar(
    String url, {
    required Function(double) onProgress,
    required Function(String) onError,
  }) async {
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        onError('Código HTTP ${response.statusCode}');
        return;
      }

      final totalBytes = response.contentLength ?? 0;
      int recebidos = 0;

      final tempDir = await getTemporaryDirectory();
      final apkFile = File('${tempDir.path}/update_obrigatorio.apk');
      if (await apkFile.exists()) {
        await apkFile.delete();
      }

      final sink = apkFile.openWrite();

      await response.stream.listen((chunk) {
        sink.add(chunk);
        recebidos += chunk.length;
        if (totalBytes > 0) {
          onProgress(recebidos / totalBytes);
        }
      }).asFuture();

      await sink.close();

      // Inicia a instalação com o leitor de pacotes nativo do Android
      await OpenFilex.open(
        apkFile.path,
        type: 'application/vnd.android.package-archive',
      );
    } catch (e) {
      onError(e.toString());
    }
  }
}