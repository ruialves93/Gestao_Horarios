import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/auth_service.dart';

class SettingsModal {
  // ---------------------------------------------------------------------------
  // MODAL DE PERFIL E REMUNERAÇÃO
  // ---------------------------------------------------------------------------
  static void abrirModalPerfil({
    required BuildContext context,
    required Map<String, dynamic> perfil,
    required VoidCallback onAtualizado,
  }) {
    final nomeController = TextEditingController(text: perfil['nomeTrabalhador'] ?? '');
    final empresaController = TextEditingController(text: perfil['nomeEmpresa'] ?? '');
    final salarioController = TextEditingController(text: perfil['salarioBase']?.toString() ?? '1000.0');
    final subsidioController = TextEditingController(text: perfil['valorSubsidioAlimentacao']?.toString() ?? '6.0');

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Configurar Perfil', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nomeController,
                  decoration: const InputDecoration(labelText: 'Nome do Trabalhador', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: empresaController,
                  decoration: const InputDecoration(labelText: 'Nome da Empresa', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: salarioController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Salário Base (EUR)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: subsidioController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Subsídio de Alimentação Diário (EUR)', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A237E), foregroundColor: Colors.white),
              onPressed: () async {
                Map<String, dynamic> novoPerfil = Map<String, dynamic>.from(perfil);
                novoPerfil['nomeTrabalhador'] = nomeController.text.trim();
                novoPerfil['nomeEmpresa'] = empresaController.text.trim();
                novoPerfil['salarioBase'] = double.tryParse(salarioController.text.replaceAll(',', '.')) ?? 1000.0;
                novoPerfil['valorSubsidioAlimentacao'] = double.tryParse(subsidioController.text.replaceAll(',', '.')) ?? 6.0;

                await DatabaseHelper.instance.salvarPerfil(novoPerfil);
                if (ctx.mounted) Navigator.pop(ctx);
                onAtualizado();
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // RESTAURO DE BASE DE DADOS
  // ---------------------------------------------------------------------------
  static Future<void> executarRestauro({
    required BuildContext context,
    required VoidCallback onAtualizado,
    required Function(String) onFeedback,
  }) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result != null && result.files.single.path != null) {
        String caminho = result.files.single.path!;
        bool sucesso = await DatabaseHelper.instance.restaurarBaseDeDados(caminho);
        if (sucesso) {
          onAtualizado();
          onFeedback('Base de dados restaurada com sucesso!');
        } else {
          onFeedback('Erro ao restaurar o ficheiro selecionado.');
        }
      } else {
        onFeedback('Nenhum ficheiro selecionado.');
      }
    } catch (e) {
      onFeedback('Erro no restauro: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // MODAL DE SEGURANÇA E BIOMETRIA
  // ---------------------------------------------------------------------------
  static void abrirModalSeguranca({
    required BuildContext context,
    required Map<String, dynamic> perfil,
    required Function(String) onFeedback,
    required VoidCallback onAtualizado,
  }) {
    int pinAtivo = (perfil['pinAtivo'] as num?)?.toInt() ?? 0;
    int biometriaAtiva = (perfil['biometriaAtiva'] as num?)?.toInt() ?? 0;
    String codigoPinAtual = perfil['codigoPin']?.toString() ?? '';

    final TextEditingController pinController = TextEditingController(text: codigoPinAtual);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Segurança e Código PIN', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      title: const Text('Ativar Proteção por PIN', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Text('Exigir código ao abrir a aplicação'),
                      value: pinAtivo == 1,
                      activeThumbColor: const Color(0xFF1A237E),
                      onChanged: (bool valor) {
                        setStateModal(() {
                          pinAtivo = valor ? 1 : 0;
                          if (pinAtivo == 0) {
                            biometriaAtiva = 0;
                          }
                        });
                      },
                    ),
                    if (pinAtivo == 1) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: pinController,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Definir PIN (4 dígitos)',
                          border: OutlineInputBorder(),
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        title: const Text('Desbloquear com Impressão Digital', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text('Usar biometria do telemóvel'),
                        value: biometriaAtiva == 1,
                        activeThumbColor: const Color(0xFF1A237E),
                        onChanged: (bool valor) async {
                          if (valor) {
                            bool suportado = await AuthService.dispoeBiometria();
                            if (!context.mounted) return;
                            if (!suportado) {
                              onFeedback('Este dispositivo não suporta biometria.');
                              return;
                            }
                            bool autenticado = await AuthService.autenticarComBiometria();
                            if (!context.mounted) return;
                            if (!autenticado) {
                              onFeedback('Impressão digital não reconhecida.');
                              return;
                            }
                          }
                          setStateModal(() {
                            biometriaAtiva = valor ? 1 : 0;
                          });
                        },
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A237E), foregroundColor: Colors.white),
                  onPressed: () async {
                    if (pinAtivo == 1 && pinController.text.length < 4) {
                      onFeedback('O PIN deve ter 4 dígitos.');
                      return;
                    }

                    Map<String, dynamic> perfilAtualizado = Map<String, dynamic>.from(perfil);
                    perfilAtualizado['pinAtivo'] = pinAtivo;
                    perfilAtualizado['codigoPin'] = pinAtivo == 1 ? pinController.text : '';
                    perfilAtualizado['biometriaAtiva'] = biometriaAtiva;

                    await DatabaseHelper.instance.salvarPerfil(perfilAtualizado);
                    if (ctx.mounted) Navigator.pop(ctx);
                    onAtualizado();
                    onFeedback('Definições de segurança atualizadas com sucesso.');
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}