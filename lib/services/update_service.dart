import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  // Repositório correto no GitHub
  static const String _githubRepo = 'ruialves93/Gestao_Horarios'; 

  /// Verifica se há nova versão no GitHub.
  static Future<void> verificarEForcarAtualizacao(
    BuildContext context, {
    bool manual = false,
    Function(String)? onFeedback,
  }) async {
    try {
      // Define como 'false' para consultar o GitHub real agora que o link está correto
      const bool ativarSimulacaoTeste = false; 
      
      if (ativarSimulacaoTeste) {
        if (context.mounted) {
          _mostrarDialogoAtualizacao(
            context, 
            '1.0.4 (Teste)', 
            'https://github.com/$_githubRepo/releases'
          );
        }
        return;
      }

      final packageInfo = await PackageInfo.fromPlatform();
      String versaoAtualStr = packageInfo.version; 
      if (versaoAtualStr.isEmpty || versaoAtualStr == '1.0.0') {
        versaoAtualStr = '1.0.3';
      }

      final url = Uri.parse('https://api.github.com/repos/$_githubRepo/releases/latest');
      final response = await http.get(url, headers: {'Accept': 'application/vnd.github.v3+json'});

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        String tagVersaoGitHub = data['tag_name']?.toString() ?? '';
        String urlDownload = data['html_url']?.toString() ?? 'https://github.com/$_githubRepo/releases';

        String versaoGitHubLimpa = tagVersaoGitHub.startsWith('v') ? tagVersaoGitHub.substring(1) : tagVersaoGitHub;

        if (versaoGitHubLimpa.isNotEmpty) {
          bool temNovaVersao = _compararVersoes(versaoGitHubLimpa, versaoAtualStr);

          if (temNovaVersao) {
            if (context.mounted) {
              _mostrarDialogoAtualizacao(context, versaoGitHubLimpa, urlDownload);
            }
          } else if (manual) {
            if (onFeedback != null) {
              onFeedback('A sua aplicação (v$versaoAtualStr) já está atualizada com a versão mais recente.');
            }
          }
        } else if (manual && onFeedback != null) {
          onFeedback('Não foi encontrada nenhuma versão válida no GitHub.');
        }
      } else if (response.statusCode == 404) {
        if (manual && onFeedback != null) {
          onFeedback('Ainda não existem versões publicadas nas Releases do GitHub.');
        }
      } else {
        if (manual && onFeedback != null) {
          onFeedback('Erro ao consultar GitHub (Código: ${response.statusCode}).');
        }
      }
    } catch (e) {
      if (manual && onFeedback != null) {
        onFeedback('Sem ligação à internet ou erro de rede.');
      }
    }
  }

  static bool _compararVersoes(String versaoGitHub, String versaoAtual) {
    List<int> partesGit = versaoGitHub.split('.').map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).toList();
    List<int> partesAtual = versaoAtual.split('.').map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).toList();

    while (partesGit.length < 3) partesGit.add(0);
    while (partesAtual.length < 3) partesAtual.add(0);

    for (int i = 0; i < 3; i++) {
      if (partesGit[i] > partesAtual[i]) return true;
      if (partesGit[i] < partesAtual[i]) return false;
    }
    return false; 
  }

  static void _mostrarDialogoAtualizacao(BuildContext context, String novaVersao, String urlDownload) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.system_update, color: Color(0xFF1A237E), size: 28),
              const SizedBox(width: 10),
              const Text('Nova Versão Disponível', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Está disponível a versão $novaVersao da aplicação no GitHub.'),
              const SizedBox(height: 10),
              const Text('Recomendamos que atualize para usufruir das últimas melhorias e correções.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Mais Tarde', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A237E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final Uri url = Uri.parse(urlDownload);
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
              child: const Text('Atualizar Agora', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }
}