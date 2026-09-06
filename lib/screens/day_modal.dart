import 'package:flutter/material.dart';
import '../services/database_helper.dart';

class DayModal {
  static void abrirRegistoDia({
    required BuildContext context,
    required DateTime dia,
    required Map<String, dynamic> perfil,
    required VoidCallback onAtualizado,
  }) async {
    final dataStr = "${dia.year}-${dia.month.toString().padLeft(2, '0')}-${dia.day.toString().padLeft(2, '0')}";
    final reg = await DatabaseHelper.instance.getRegistoData(dataStr);
    final perfilHoras = (perfil['horarioNormalDiario'] as num?)?.toDouble() ?? 8.0;

    String tipoDia = reg != null ? (reg['tipoDia'] ?? 'Trabalho') : 'Trabalho';
    double horasPrevistas = reg != null ? ((reg['horasCargaPrevista'] as num?)?.toDouble() ?? perfilHoras) : perfilHoras;

    TimeOfDay horaInicio = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay horaFim = const TimeOfDay(hour: 18, minute: 0);
    TimeOfDay horaAlmocoInicio = const TimeOfDay(hour: 12, minute: 0);
    TimeOfDay horaAlmocoFim = const TimeOfDay(hour: 13, minute: 0);

    if (reg != null) {
      if (reg['horaInicio'] != null && reg['horaInicio'].toString().contains(':')) {
        final p = reg['horaInicio'].toString().split(':');
        horaInicio = TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
      }
      if (reg['horaFim'] != null && reg['horaFim'].toString().contains(':')) {
        final p = reg['horaFim'].toString().split(':');
        horaFim = TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
      }
      if (reg['horaAlmocoInicio'] != null && reg['horaAlmocoInicio'].toString().contains(':')) {
        final p = reg['horaAlmocoInicio'].toString().split(':');
        horaAlmocoInicio = TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
      }
      if (reg['horaAlmocoFim'] != null && reg['horaAlmocoFim'].toString().contains(':')) {
        final p = reg['horaAlmocoFim'].toString().split(':');
        horaAlmocoFim = TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
      }
    }

    String opcaoExcesso = 'Banco de Horas';
    if (reg != null) {
      if ((reg['horasExtraPagas'] as num? ?? 0) > 0) {
        opcaoExcesso = 'Pagar';
      } else if ((reg['horasCreditoBanco'] as num? ?? 0) > 0) {
        opcaoExcesso = 'Banco de Horas';
      } else {
        opcaoExcesso = 'Não fazer nada';
      }
    }

    String opcaoDefice = 'Banco de Horas';
    if (reg != null) {
      if ((reg['horasDescontoSalario'] as num? ?? 0) > 0) {
        opcaoDefice = 'Descontar no Salário';
      } else if ((reg['horasDebitoBanco'] as num? ?? 0) > 0) {
        opcaoDefice = 'Descontar no Banco de Horas';
      } else {
        opcaoDefice = 'Não fazer nada';
      }
    }

    String tipoFalta = reg != null ? (reg['tipoFalta'] ?? 'Justificada (ex: Médico)') : 'Justificada (ex: Médico)';

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            int minI = horaInicio.hour * 60 + horaInicio.minute;
            int minF = horaFim.hour * 60 + horaFim.minute;
            int minAI = horaAlmocoInicio.hour * 60 + horaAlmocoInicio.minute;
            int minAF = horaAlmocoFim.hour * 60 + horaAlmocoFim.minute;

            int minAlmocoCalculado = (minAF - minAI).clamp(0, 1440);
            int minTrabalhoLiquido = ((minF - minI) - minAlmocoCalculado).clamp(0, 1440);
            double horasEfetivasAtuais = tipoDia == 'Trabalho' ? (minTrabalhoLiquido / 60.0) : 0.0;

            double diferenca = horasEfetivasAtuais - horasPrevistas;
            bool temExcesso = diferenca > 0.001;
            bool temDefice = diferenca < -0.001;

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Registo: $dataStr', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'Trabalho', label: Text('Trabalho')),
                        ButtonSegment(value: 'Folga', label: Text('Folga')),
                        ButtonSegment(value: 'Férias', label: Text('Férias')),
                      ],
                      selected: {tipoDia},
                      onSelectionChanged: (s) => setModalState(() => tipoDia = s.first),
                    ),
                    const SizedBox(height: 12),

                    if (tipoDia == 'Trabalho') ...[
                      Card(
                        color: Colors.grey.shade100,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Horas previstas hoje:', style: TextStyle(fontWeight: FontWeight.w600)),
                              SizedBox(
                                width: 80,
                                child: TextField(
                                  decoration: const InputDecoration(isDense: true, suffixText: 'h'),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  controller: TextEditingController(text: horasPrevistas.toString()),
                                  onChanged: (v) {
                                    setModalState(() {
                                      horasPrevistas = double.tryParse(v) ?? 8.0;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      const Text('Horário de Trabalho:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          Expanded(
                            child: ListTile(
                              title: const Text('Início', style: TextStyle(fontSize: 12)),
                              subtitle: Text(horaInicio.format(context), style: const TextStyle(fontWeight: FontWeight.bold)),
                              trailing: const Icon(Icons.access_time),
                              onTap: () async {
                                final t = await showTimePicker(context: context, initialTime: horaInicio);
                                if (t != null) setModalState(() => horaInicio = t);
                              },
                            ),
                          ),
                          Expanded(
                            child: ListTile(
                              title: const Text('Fim', style: TextStyle(fontSize: 12)),
                              subtitle: Text(horaFim.format(context), style: const TextStyle(fontWeight: FontWeight.bold)),
                              trailing: const Icon(Icons.access_time),
                              onTap: () async {
                                final t = await showTimePicker(context: context, initialTime: horaFim);
                                if (t != null) setModalState(() => horaFim = t);
                              },
                            ),
                          ),
                        ],
                      ),

                      const Text('Período de Almoço:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          Expanded(
                            child: ListTile(
                              title: const Text('Início Almoço', style: TextStyle(fontSize: 12)),
                              subtitle: Text(horaAlmocoInicio.format(context), style: const TextStyle(fontWeight: FontWeight.bold)),
                              trailing: const Icon(Icons.lunch_dining),
                              onTap: () async {
                                final t = await showTimePicker(context: context, initialTime: horaAlmocoInicio);
                                if (t != null) setModalState(() => horaAlmocoInicio = t);
                              },
                            ),
                          ),
                          Expanded(
                            child: ListTile(
                              title: const Text('Fim Almoço', style: TextStyle(fontSize: 12)),
                              subtitle: Text(horaAlmocoFim.format(context), style: const TextStyle(fontWeight: FontWeight.bold)),
                              trailing: const Icon(Icons.lunch_dining),
                              onTap: () async {
                                final t = await showTimePicker(context: context, initialTime: horaAlmocoFim);
                                if (t != null) setModalState(() => horaAlmocoFim = t);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: temExcesso
                              ? Colors.green.shade50
                              : (temDefice ? Colors.orange.shade50 : Colors.blue.shade50),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Horas Trabalhadas: ${horasEfetivasAtuais.toStringAsFixed(2)}h',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              temExcesso
                                  ? '+${diferenca.toStringAsFixed(2)}h extra'
                                  : (temDefice ? '${diferenca.toStringAsFixed(2)}h em falta' : 'Cumprido'),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: temExcesso ? Colors.green.shade900 : (temDefice ? Colors.red.shade900 : Colors.blue.shade900),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      if (temExcesso) ...[
                        const Text('Opção para Horas Extra:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green)),
                        DropdownButton<String>(
                          value: opcaoExcesso,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(value: 'Banco de Horas', child: Text('Enviar para o banco de horas')),
                            DropdownMenuItem(value: 'Pagar', child: Text('Pagar')),
                            DropdownMenuItem(value: 'Não fazer nada', child: Text('Não fazer nada')),
                          ],
                          onChanged: (v) => setModalState(() => opcaoExcesso = v!),
                        ),
                      ],

                      if (temDefice) ...[
                        const Text('Opção para Horas em Falta:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red)),
                        DropdownButton<String>(
                          value: opcaoDefice,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(value: 'Descontar no Banco de Horas', child: Text('Descontar no banco de horas')),
                            DropdownMenuItem(value: 'Descontar no Salário', child: Text('Descontar no salário')),
                            DropdownMenuItem(value: 'Não fazer nada', child: Text('Não fazer nada')),
                          ],
                          onChanged: (v) => setModalState(() => opcaoDefice = v!),
                        ),
                        const SizedBox(height: 6),
                        const Text('Tipo de Falta / Ausência:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        DropdownButton<String>(
                          value: tipoFalta,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(value: 'Justificada (ex: Médico)', child: Text('Falta justificada (ex: médico)')),
                            DropdownMenuItem(value: 'Injustificada', child: Text('Falta injustificada')),
                          ],
                          onChanged: (v) => setModalState(() => tipoFalta = v!),
                        ),
                      ],
                    ],

                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () async {
                        double horasEfetivas = 0.0;
                        double duracaoAlmocoHoras = 0.0;
                        double creditoBanco = 0.0;
                        double debitoBanco = 0.0;
                        double extraPagas = 0.0;
                        double descontoSalario = 0.0;

                        if (tipoDia == 'Trabalho') {
                          int inicioMin = horaInicio.hour * 60 + horaInicio.minute;
                          int fimMin = horaFim.hour * 60 + horaFim.minute;
                          int almocoInicioMin = horaAlmocoInicio.hour * 60 + horaAlmocoInicio.minute;
                          int almocoFimMin = horaAlmocoFim.hour * 60 + horaAlmocoFim.minute;

                          int totalMinutosAlmoco = (almocoFimMin - almocoInicioMin).clamp(0, 1440);
                          duracaoAlmocoHoras = totalMinutosAlmoco / 60.0;

                          int minutosTrabalhados = ((fimMin - inicioMin) - totalMinutosAlmoco).clamp(0, 1440);
                          horasEfetivas = minutosTrabalhados / 60.0;

                          if (horasEfetivas > horasPrevistas) {
                            double dif = horasEfetivas - horasPrevistas;
                            if (opcaoExcesso == 'Banco de Horas') {
                              creditoBanco = dif;
                            } else if (opcaoExcesso == 'Pagar') {
                              extraPagas = dif;
                            }
                          } else if (horasEfetivas < horasPrevistas) {
                            double falta = horasPrevistas - horasEfetivas;
                            if (opcaoDefice == 'Descontar no Banco de Horas') {
                              debitoBanco = falta;
                            } else if (opcaoDefice == 'Descontar no Salário') {
                              descontoSalario = falta;
                            }
                          }
                        }

                        final novoRegisto = {
                          'data': dataStr,
                          'tipoDia': tipoDia,
                          'horaInicio': tipoDia == 'Trabalho' ? "${horaInicio.hour}:${horaInicio.minute.toString().padLeft(2, '0')}" : null,
                          'horaFim': tipoDia == 'Trabalho' ? "${horaFim.hour}:${horaFim.minute.toString().padLeft(2, '0')}" : null,
                          'horaAlmocoInicio': tipoDia == 'Trabalho' ? "${horaAlmocoInicio.hour}:${horaAlmocoInicio.minute.toString().padLeft(2, '0')}" : null,
                          'horaAlmocoFim': tipoDia == 'Trabalho' ? "${horaAlmocoFim.hour}:${horaAlmocoFim.minute.toString().padLeft(2, '0')}" : null,
                          'horasAlmoco': duracaoAlmocoHoras,
                          'horasEfetivas': horasEfetivas,
                          'horasCargaPrevista': tipoDia == 'Trabalho' ? horasPrevistas : 0.0,
                          'horasCreditoBanco': creditoBanco,
                          'horasDebitoBanco': debitoBanco,
                          'horasExtraPagas': extraPagas,
                          'horasDescontoSalario': descontoSalario,
                          'tipoFalta': (tipoDia == 'Trabalho' && horasEfetivas < horasPrevistas) ? tipoFalta : null,
                        };

                        await DatabaseHelper.instance.saveRegisto(novoRegisto);
                        if (context.mounted) Navigator.pop(ctx);
                        onAtualizado();
                      },
                      icon: const Icon(Icons.save),
                      label: const Text('Guardar Dia'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A237E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}