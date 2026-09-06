import 'package:flutter/material.dart';
import '../services/database_helper.dart';

class SettingsModal {
  static void abrirModalPerfil({
    required BuildContext context,
    required Map<String, dynamic> perfil,
    required VoidCallback onAtualizado,
  }) {
    final nomeTrabController = TextEditingController(text: perfil['nomeTrabalhador']?.toString() ?? '');
    final nomeEmpController = TextEditingController(text: perfil['nomeEmpresa']?.toString() ?? '');
    final salarioController = TextEditingController(
      text: perfil['salarioBase'] != null ? perfil['salarioBase'].toString() : '1000.0',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Definições do Trabalhador e Empresa'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nomeTrabController,
                decoration: const InputDecoration(
                  labelText: 'Nome do Trabalhador',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nomeEmpController,
                decoration: const InputDecoration(
                  labelText: 'Nome da Empresa',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: salarioController,
                decoration: const InputDecoration(
                  labelText: 'Salário Base (€)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
            onPressed: () async {
              final updated = {
                'nomeTrabalhador': nomeTrabController.text.trim(),
                'nomeEmpresa': nomeEmpController.text.trim(),
                'salarioBase': double.tryParse(salarioController.text) ?? 1000.0,
                'horarioNormalDiario': perfil['horarioNormalDiario'] ?? 8.0,
                'pinSeguranca': perfil['pinSeguranca'] ?? '',
                'biometriaAtiva': perfil['biometriaAtiva'] ?? 0,
              };
              await DatabaseHelper.instance.updatePerfil(updated);
              if (context.mounted) Navigator.pop(ctx);
              onAtualizado();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  static void abrirModalSeguranca({
    required BuildContext context,
    required Map<String, dynamic> perfil,
    required Function(String mensagem) onFeedback,
    required VoidCallback onAtualizado,
  }) {
    final pinController = TextEditingController(text: perfil['pinSeguranca']?.toString() ?? '');
    bool biometriaVal = (perfil['biometriaAtiva'] ?? 0) == 1;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Definições de Segurança'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Defina um PIN de 4 a 6 dígitos para proteger o acesso à aplicação:', style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: pinController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'PIN de Acesso (Deixar vazio para desativar)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    title: const Text('Ativar Impressão Digital / Facial', style: TextStyle(fontSize: 13)),
                    value: biometriaVal,
                    onChanged: (val) {
                      setDialogState(() => biometriaVal = val);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton(
                onPressed: () async {
                  final updated = {
                    'nomeTrabalhador': perfil['nomeTrabalhador'] ?? '',
                    'nomeEmpresa': perfil['nomeEmpresa'] ?? '',
                    'salarioBase': perfil['salarioBase'] ?? 1000.0,
                    'horarioNormalDiario': perfil['horarioNormalDiario'] ?? 8.0,
                    'pinSeguranca': pinController.text.trim(),
                    'biometriaAtiva': biometriaVal ? 1 : 0,
                  };
                  await DatabaseHelper.instance.updatePerfil(updated);
                  if (context.mounted) Navigator.pop(ctx);
                  onAtualizado();
                  onFeedback('Definições de segurança guardadas com sucesso!');
                },
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );
  }

  static Future<void> executarRestauro({
    required BuildContext context,
    required VoidCallback onAtualizado,
    required Function(String mensagem) onFeedback,
  }) async {
    bool ok = await DatabaseHelper.instance.restaurarBaseDeDadosPorFilePicker();
    if (ok) {
      onAtualizado();
      onFeedback('Base de dados restaurada com sucesso!');
    } else {
      onFeedback('Nenhum ficheiro selecionado ou erro ao restaurar.');
    }
  }
}