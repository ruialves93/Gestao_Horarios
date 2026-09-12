import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  // Ajusta o utilizador e o repositório conforme o teu GitHub
  static const String _owner = 'ruialves93';
  static const String _repo = 'gestao_horarios';

  static Future<void> verificarEForcarAtualizacao(
    BuildContext context, {
    bool manual = false,
    Function(String)? onFeedback,
  }) async {
    try {
      final url = Uri.parse('https://api.github.com/repos/$_owner/$_repo/releases/latest');
      
      // O GitHub exige obrigatoriamente um User-Agent
      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'GestaoHorarios-App',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String latestTag = (data['tag_name'] ?? '').toString().replaceAll('v', '').trim();
        String htmlUrl = data['html_url'] ?? 'https://github.com/$_owner/$_repo/releases';

        PackageInfo packageInfo = await PackageInfo.fromPlatform();
        String currentVersion = packageInfo.version.trim();

        if (_versaoMaisRecente(latestTag, currentVersion)) {
          if (context.mounted) {
            _mostrarDialogoAtualizacao(context, latestTag, htmlUrl);
          }
        } else {
          if (manual && onFeedback != null) {
            onFeedback('A aplicação já se encontra na versão mais recente (v$currentVersion).');
          }
        }
      } else if (response.statusCode == 404) {
        if (manual && onFeedback != null) {
          onFeedback('Nenhum release público encontrado no GitHub.');
        }
      } else {
        if (manual && onFeedback != null) {
          onFeedback('GitHub inacessível (Código HTTP ${response.statusCode}).');
        }
      }
    } catch (e) {
      if (manual && onFeedback != null) {
        onFeedback('Não foi possível verificar atualizações. Verifique a ligação à Internet.');
      }
    }
  }

  static bool _versaoMaisRecente(String remote, String current) {
    if (remote.isEmpty || current.isEmpty) return false;
    List<int> rParts = remote.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    List<int> cParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < rParts.length && i < cParts.length; i++) {
      if (rParts[i] > cParts[i]) return true;
      if (rParts[i] < cParts[i]) return false;
    }
    return rParts.length > cParts.length;
  }

  static void _mostrarDialogoAtualizacao(BuildContext context, String novaVersao, String linkDownload) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.system_update, color: Color(0xFF1A237E)),
            SizedBox(width: 8),
            Text('Nova Versão Disponível', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text('Está disponível a versão v$novaVersao no GitHub. Deseja descarregar agora?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Mais Tarde'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A237E),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final uri = Uri.parse(linkDownload);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: const Text('Atualizar'),
          ),
        ],
      ),
    );
  }
}