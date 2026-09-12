import 'package:flutter/material.dart';
import '../services/database_helper.dart';

class DayModal {
  static void abrirRegistoDia({
    required BuildContext context,
    required DateTime dia,
    required Map<String, dynamic> perfil,
    required VoidCallback onAtualizado,
  }) async {
    String dataStr = "${dia.year}-${dia.month.toString().padLeft(2, '0')}-${dia.day.toString().padLeft(2, '0')}";

    Map<String, dynamic>? registoExistente;
    try {
      registoExistente = await DatabaseHelper.instance.getRegisto(dataStr);
    } catch (e) {
      debugPrint("Erro ao carregar registo prévio: $e");
    }

    if (!context.mounted) return;

    String tipoDia = registoExistente?['tipoDia'] ?? 'Trabalho';
    TimeOfDay horaInicio = _parseHora(registoExistente?['horaInicio'], const TimeOfDay(hour: 8, minute: 0));
    TimeOfDay horaFim = _parseHora(registoExistente?['horaFim'], const TimeOfDay(hour: 17, minute: 0));

    TimeOfDay? almocoInicio = registoExistente?['almocoInicio'] != null
        ? _parseHora(registoExistente?['almocoInicio'], const TimeOfDay(hour: 13, minute: 0))
        : null;
    TimeOfDay? almocoFim = registoExistente?['almocoFim'] != null
        ? _parseHora(registoExistente?['almocoFim'], const TimeOfDay(hour: 14, minute: 0))
        : null;

    double horasContratadas = (registoExistente?['horasContratadas'] as num?)?.toDouble() ?? 8.0;
    final horasContratadasController = TextEditingController(text: horasContratadas.toStringAsFixed(1));

    int incluiSubsidio = registoExistente?['incluiSubsidio'] ?? (tipoDia == 'Trabalho' || tipoDia == 'Folga Trabalhada' ? 1 : 0);

    String acaoExcesso = registoExistente?['acaoExcesso'] ?? 'Banco de Horas';
    String acaoDefice = registoExistente?['acaoFalta'] ?? 'Descontar no Banco';
    String subTipoFalta = registoExistente?['subTipoFalta'] ?? 'Injustificada';
    String acaoFaltaTratamento = registoExistente?['acaoFaltaTratamento'] ?? 'Descontar no Salário';
    String acaoFolgaTrabalhada = registoExistente?['acaoFolgaTrabalhada'] ?? 'Banco de Horas';

    final tiposDisponiveis = [
      {'nome': 'Trabalho', 'icone': Icons.work, 'cor': const Color(0xFF2E7D32)},
      {'nome': 'Férias', 'icone': Icons.beach_access, 'cor': const Color(0xFF0288D1)},
      {'nome': 'Folga', 'icone': Icons.weekend, 'cor': const Color(0xFF7B1FA2)},
      {'nome': 'Folga Trabalhada', 'icone': Icons.work_history, 'cor': const Color(0xFF00796B)},
      {'nome': 'Falta', 'icone': Icons.warning_amber_rounded, 'cor': const Color(0xFFE65100)},
      {'nome': 'Baixa', 'icone': Icons.local_hospital, 'cor': const Color(0xFFC62828)},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            double horasEfetivasCalc = 0.0;
            if (tipoDia == 'Trabalho' || tipoDia == 'Folga Trabalhada') {
              double totalMinutos = ((horaFim.hour * 60 + horaFim.minute) - (horaInicio.hour * 60 + horaInicio.minute)).toDouble();
              if (almocoInicio != null && almocoFim != null) {
                double minAlmoco = ((almocoFim!.hour * 60 + almocoFim!.minute) - (almocoInicio!.hour * 60 + almocoInicio!.minute)).toDouble();
                totalMinutos -= minAlmoco;
              }
              horasEfetivasCalc = totalMinutos > 0 ? (totalMinutos / 60.0) : 0.0;
            }

            double hContratadasParsed = double.tryParse(horasContratadasController.text.replaceAll(',', '.')) ?? 8.0;
            double diffHoras = horasEfetivasCalc - hContratadasParsed;

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Registo: ${dia.day.toString().padLeft(2, '0')}/${dia.month.toString().padLeft(2, '0')}/${dia.year}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1A237E)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(modalCtx).pop(),
                        ),
                      ],
                    ),
                    const Divider(),

                    const Text('Selecione o Tipo de Dia:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: tiposDisponiveis.map((tipo) {
                        bool selecionado = (tipoDia == tipo['nome']);
                        Color corTipo = tipo['cor'] as Color;
                        return InkWell(
                          onTap: () {
                            setStateModal(() {
                              tipoDia = tipo['nome'] as String;
                              incluiSubsidio = (tipoDia == 'Trabalho' || tipoDia == 'Folga Trabalhada') ? 1 : 0;
                            });
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: selecionado ? corTipo : corTipo.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: corTipo, width: selecionado ? 2 : 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(tipo['icone'] as IconData, size: 16, color: selecionado ? Colors.white : corTipo),
                                const SizedBox(width: 6),
                                Text(
                                  tipo['nome'] as String,
                                  style: TextStyle(
                                    color: selecionado ? Colors.white : corTipo,
                                    fontWeight: selecionado ? FontWeight.bold : FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    Row(
                      children: [
                        const Expanded(
                          flex: 2,
                          child: Text('Horas previstas no dia (h):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: horasContratadasController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onChanged: (_) => setStateModal(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (tipoDia == 'Trabalho' || tipoDia == 'Folga Trabalhada') ...[
                      Row(
                        children: [
                          Expanded(
                            child: _buildTimePickerField(
                              label: 'Hora Início',
                              time: horaInicio,
                              onTap: () async {
                                TimeOfDay? picked = await showTimePicker(context: modalCtx, initialTime: horaInicio);
                                if (picked != null) setStateModal(() => horaInicio = picked);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildTimePickerField(
                              label: 'Hora Fim',
                              time: horaFim,
                              onTap: () async {
                                TimeOfDay? picked = await showTimePicker(context: modalCtx, initialTime: horaFim);
                                if (picked != null) setStateModal(() => horaFim = picked);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTimePickerField(
                              label: 'Almoço Início (opcional)',
                              time: almocoInicio,
                              onTap: () async {
                                TimeOfDay? picked = await showTimePicker(context: modalCtx, initialTime: almocoInicio ?? const TimeOfDay(hour: 13, minute: 0));
                                if (picked != null) setStateModal(() => almocoInicio = picked);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildTimePickerField(
                              label: 'Almoço Fim (opcional)',
                              time: almocoFim,
                              onTap: () async {
                                TimeOfDay? picked = await showTimePicker(context: modalCtx, initialTime: almocoFim ?? const TimeOfDay(hour: 14, minute: 0));
                                if (picked != null) setStateModal(() => almocoFim = picked);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Total Trabalhado: ${horasEfetivasCalc.toStringAsFixed(2)}h  (${diffHoras >= 0 ? '+' : ''}${diffHoras.toStringAsFixed(2)}h)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: diffHoras >= 0 ? Colors.green.shade900 : Colors.red.shade900,
                        ),
                      ),
                      const SizedBox(height: 10),

                      if (tipoDia == 'Trabalho' && diffHoras > 0.01) ...[
                        const Text('Destino das Horas Extras:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 4),
                        DropdownButtonFormField<String>(
                          initialValue: acaoExcesso,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          items: ['Banco de Horas', 'Pagar', 'Voluntariado']
                              .map((opcao) => DropdownMenuItem(value: opcao, child: Text(opcao)))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) setStateModal(() => acaoExcesso = val);
                          },
                        ),
                        const SizedBox(height: 10),
                      ],

                      if (tipoDia == 'Trabalho' && diffHoras < -0.01) ...[
                        const Text('Horas a menos trabalhadas (défice):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 4),
                        DropdownButtonFormField<String>(
                          initialValue: acaoDefice,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          items: ['Descontar no Banco', 'Descontar no Salário', 'Não faz nada']
                              .map((opcao) => DropdownMenuItem(value: opcao, child: Text(opcao)))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) setStateModal(() => acaoDefice = val);
                          },
                        ),
                        const SizedBox(height: 10),
                      ],

                      if (tipoDia == 'Folga Trabalhada') ...[
                        const Text('Destino da Folga Trabalhada:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 4),
                        DropdownButtonFormField<String>(
                          initialValue: acaoFolgaTrabalhada,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          items: ['Banco de Horas', 'Salário']
                              .map((opcao) => DropdownMenuItem(value: opcao, child: Text(opcao)))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) setStateModal(() => acaoFolgaTrabalhada = val);
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],

                    if (tipoDia == 'Falta') ...[
                      const Text('Classificação da Falta:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        initialValue: subTipoFalta,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: ['Justificada', 'Injustificada']
                            .map((opcao) => DropdownMenuItem(value: opcao, child: Text(opcao)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setStateModal(() => subTipoFalta = val);
                        },
                      ),
                      const SizedBox(height: 10),
                      const Text('Onde aplicar o desconto da Falta?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        initialValue: acaoFaltaTratamento,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: ['Descontar no Salário', 'Descontar no Banco de Horas']
                            .map((opcao) => DropdownMenuItem(value: opcao, child: Text(opcao)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setStateModal(() => acaoFaltaTratamento = val);
                        },
                      ),
                      const SizedBox(height: 10),
                    ],

                    if (tipoDia == 'Baixa') ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, color: Color(0xFFC62828), size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'A Baixa médica desconta o dia no salário.',
                                style: TextStyle(fontSize: 12, color: Colors.black87),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    CheckboxListTile(
                      title: const Text('Incluir Subsídio de Alimentação', style: TextStyle(fontSize: 13)),
                      value: incluiSubsidio == 1,
                      onChanged: (val) {
                        setStateModal(() => incluiSubsidio = (val == true ? 1 : 0));
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),

                    const SizedBox(height: 14),

                    Row(
                      children: [
                        if (registoExistente != null) ...[
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              icon: const Icon(Icons.delete, size: 18),
                              label: const Text('Apagar'),
                              onPressed: () async {
                                final nav = Navigator.of(modalCtx);
                                final messenger = ScaffoldMessenger.of(context);
                                try {
                                  await DatabaseHelper.instance.deletarRegisto(dataStr);
                                  nav.pop();
                                  onAtualizado();
                                  messenger.showSnackBar(
                                    const SnackBar(content: Text('Registo apagado com sucesso!')),
                                  );
                                } catch (e) {
                                  messenger.showSnackBar(
                                    SnackBar(content: Text('Erro ao apagar: $e'), backgroundColor: Colors.red),
                                  );
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1A237E),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text('Guardar Registo', style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: () async {
                              final nav = Navigator.of(modalCtx);
                              final messenger = ScaffoldMessenger.of(context);
                              try {
                                double hPrevistas = double.tryParse(horasContratadasController.text.replaceAll(',', '.')) ?? 8.0;
                                double horasEfetivasFinais = 0.0;
                                double horasExtraPagas = 0.0;
                                double horasDescontoSalario = 0.0;

                                if (tipoDia == 'Trabalho') {
                                  horasEfetivasFinais = horasEfetivasCalc;
                                  double diff = horasEfetivasCalc - hPrevistas;
                                  if (diff > 0.01 && acaoExcesso == 'Pagar') {
                                    horasExtraPagas = diff;
                                  } else if (diff < -0.01 && acaoDefice == 'Descontar no Salário') {
                                    horasDescontoSalario = diff.abs();
                                  }
                                } else if (tipoDia == 'Folga Trabalhada') {
                                  horasEfetivasFinais = horasEfetivasCalc;
                                  if (acaoFolgaTrabalhada == 'Salário') {
                                    horasExtraPagas = horasEfetivasCalc;
                                  }
                                } else if (tipoDia == 'Falta') {
                                  if (acaoFaltaTratamento == 'Descontar no Salário') {
                                    horasDescontoSalario = hPrevistas;
                                  }
                                } else if (tipoDia == 'Baixa') {
                                  horasDescontoSalario = hPrevistas;
                                }

                                Map<String, dynamic> dadosRegisto = {
                                  'data': dataStr,
                                  'tipoDia': tipoDia,
                                  'horaInicio': '${horaInicio.hour.toString().padLeft(2, '0')}:${horaInicio.minute.toString().padLeft(2, '0')}',
                                  'horaFim': '${horaFim.hour.toString().padLeft(2, '0')}:${horaFim.minute.toString().padLeft(2, '0')}',
                                  'almocoInicio': almocoInicio != null ? '${almocoInicio!.hour.toString().padLeft(2, '0')}:${almocoInicio!.minute.toString().padLeft(2, '0')}' : null,
                                  'almocoFim': almocoFim != null ? '${almocoFim!.hour.toString().padLeft(2, '0')}:${almocoFim!.minute.toString().padLeft(2, '0')}' : null,
                                  'horasEfetivas': horasEfetivasFinais,
                                  'horasContratadas': hPrevistas,
                                  'incluiSubsidio': incluiSubsidio,
                                  'acaoExcesso': acaoExcesso,
                                  'acaoFalta': acaoDefice,
                                  'acaoFolgaTrabalhada': acaoFolgaTrabalhada,
                                  'subTipoFalta': subTipoFalta,
                                  'acaoFaltaTratamento': acaoFaltaTratamento,
                                  'horasExtraPagas': horasExtraPagas,
                                  'horasDescontoSalario': horasDescontoSalario,
                                };

                                await DatabaseHelper.instance.salvarRegisto(dadosRegisto);

                                nav.pop();
                                onAtualizado();

                                messenger.showSnackBar(
                                  const SnackBar(content: Text('Registo guardado com sucesso!'), backgroundColor: Colors.green),
                                );
                              } catch (e) {
                                debugPrint("Erro ao salvar registo: $e");
                                messenger.showSnackBar(
                                  SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red, duration: const Duration(seconds: 4)),
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static TimeOfDay _parseHora(String? horaStr, TimeOfDay padrao) {
    if (horaStr == null || !horaStr.contains(':')) return padrao;
    List<String> partes = horaStr.split(':');
    return TimeOfDay(
      hour: int.tryParse(partes[0]) ?? padrao.hour,
      minute: int.tryParse(partes[1]) ?? padrao.minute,
    );
  }

  static Widget _buildTimePickerField({required String label, TimeOfDay? time, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              time != null ? '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}' : '--:--',
              style: const TextStyle(fontSize: 13),
            ),
            const Icon(Icons.access_time, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}