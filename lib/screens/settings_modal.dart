import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/database_helper.dart';

class SettingsModal {
  static void abrirModalPerfil({
    required BuildContext context,
    required Map<String, dynamic> perfil,
    required VoidCallback onAtualizado,
  }) {
    final nomeTrabalhadorController = TextEditingController(text: perfil['nomeTrabalhador']?.toString() ?? '');
    final nomeEmpresaController = TextEditingController(text: perfil['nomeEmpresa']?.toString() ?? '');
    final salarioBaseController = TextEditingController(text: perfil['salarioBase']?.toString() ?? '1000.0');
    final subsidioAlimentacaoController = TextEditingController(text: perfil['valorSubsidioAlimentacao']?.toString() ?? '6.0');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Configurar Perfil e Empresa', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nomeTrabalhadorController,
                  decoration: const InputDecoration(labelText: 'Nome do Trabalhador', prefixIcon: Icon(Icons.person)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nomeEmpresaController,
                  decoration: const InputDecoration(labelText: 'Nome da Empresa', prefixIcon: Icon(Icons.business)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: salarioBaseController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Salário Base (€)', prefixIcon: Icon(Icons.euro)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: subsidioAlimentacaoController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Subsídio de Alimentação por Dia (€)', prefixIcon: Icon(Icons.restaurant)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A237E), foregroundColor: Colors.white),
              onPressed: () async {
                double salario = double.tryParse(salarioBaseController.text.replaceAll(',', '.')) ?? 1000.0;
                double subsidio = double.tryParse(subsidioAlimentacaoController.text.replaceAll(',', '.')) ?? 0.0;

                await DatabaseHelper.instance.atualizarPerfil({
                  'nomeTrabalhador': nomeTrabalhadorController.text,
                  'nomeEmpresa': nomeEmpresaController.text,
                  'salarioBase': salario,
                  'valorSubsidioAlimentacao': subsidio,
                  'pinApp': perfil['pinApp'] ?? '',
                  'biometriaAtiva': perfil['biometriaAtiva'] ?? 0,
                });

                onAtualizado();
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
  }

  static void abrirModalSeguranca({
    required BuildContext context,
    required Map<String, dynamic> perfil,
    required Function(String) onFeedback,
    required VoidCallback onAtualizado,
  }) {
    final pinController = TextEditingController(text: perfil['pinApp']?.toString() ?? '');
    bool biometria = (perfil['biometriaAtiva'] == 1);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Segurança', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: pinController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'PIN de Acesso (Opcional)', prefixIcon: Icon(Icons.lock)),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Ativar Biometria'),
                    value: biometria,
                    onChanged: (val) {
                      setStateModal(() {
                        biometria = val;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A237E), foregroundColor: Colors.white),
                  onPressed: () async {
                    await DatabaseHelper.instance.atualizarPerfil({
                      'nomeTrabalhador': perfil['nomeTrabalhador'],
                      'nomeEmpresa': perfil['nomeEmpresa'],
                      'salarioBase': perfil['salarioBase'],
                      'valorSubsidioAlimentacao': perfil['valorSubsidioAlimentacao'] ?? 6.0,
                      'pinApp': pinController.text.trim(),
                      'biometriaAtiva': biometria ? 1 : 0,
                    });
                    onAtualizado();
                    onFeedback('Definições de segurança atualizadas.');
                    if (context.mounted) Navigator.pop(context);
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

  static Future<void> executarRestauro({
    required BuildContext context,
    required VoidCallback onAtualizado,
    required Function(String) onFeedback,
  }) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        dialogTitle: 'Selecionar Ficheiro de Backup (.db)',
      );

      if (result != null && result.files.single.path != null) {
        bool sucesso = await DatabaseHelper.instance.restaurarBaseDeDadosDeFicheiro(result.files.single.path!);
        if (sucesso) {
          onAtualizado();
          onFeedback('Base de dados restaurada com sucesso!');
        } else {
          onFeedback('Erro ao restaurar o ficheiro selecionado.');
        }
      }
    } catch (e) {
      onFeedback('Erro no restauro: $e');
    }
  }
}