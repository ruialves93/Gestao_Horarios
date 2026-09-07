import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/drive_service.dart';

class DayModal {
  static Future<void> abrirRegistoDia({
    required BuildContext context,
    required DateTime dia,
    required Map<String, dynamic> perfil,
    required VoidCallback onAtualizado,
  }) async {
    String chaveData = "${dia.year}-${dia.month.toString().padLeft(2, '0')}-${dia.day.toString().padLeft(2, '0')}";
    
    final registosMes = await DatabaseHelper.instance.getRegistosMes(dia.year, dia.month);
    final registoAtual = registosMes[chaveData];

    String tipoDiaSelecionado = registoAtual?['tipoDia']?.toString() ?? 'Trabalho';

    String horaInicioSelecionada = registoAtual?['horaInicio']?.toString() ?? '08:00';
    String horaFimSelecionada = registoAtual?['horaFim']?.toString() ?? '17:00';
    String almocoInicioSelecionado = registoAtual?['almocoInicio']?.toString() ?? '12:00';
    String almocoFimSelecionado = registoAtual?['almocoFim']?.toString() ?? '13:00';
    
    String horasContratadasSelecionadas = registoAtual?['horasContratadasStr']?.toString() ?? '08:00';

    bool incluiSubsidio = registoAtual?['incluiSubsidio'] != null 
        ? (registoAtual!['incluiSubsidio'] == 1) 
        : (dia.weekday != DateTime.saturday && dia.weekday != DateTime.sunday);

    String acaoExcesso = registoAtual?['acaoExcesso']?.toString() ?? 'Banco de Horas'; 
    String acaoFalta = registoAtual?['acaoFalta']?.toString() ?? 'Descontar no Banco'; 
    String tipoJustificacao = registoAtual?['tipoJustificacao']?.toString() ?? 'Justificado'; 
    
    String acaoFolgaTrabalhada = registoAtual?['acaoFolgaTrabalhada']?.toString() ?? 'Banco de Horas';

    final List<String> listaDuracoesContratadas = ['04:00', '06:00', '07:00', '07:30', '08:00', '08:30', '09:00'];

    Future<String> selecionarHoraMinutoRelogio(BuildContext context, String horaAtual) async {
      final partes = horaAtual.split(':');
      int horaSelecionada = partes.isNotEmpty ? int.tryParse(partes[0]) ?? 8 : 8;
      int minutoSelecionado = partes.length > 1 ? int.tryParse(partes[1]) ?? 0 : 0;

      String? resultado = await showDialog<String>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (context, setStateDialog) {
              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: const Text('Selecione a Hora e Minuto', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('1. Escolha a Hora:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 50,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: 24,
                        itemBuilder: (context, h) {
                          bool sel = horaSelecionada == h;
                          return InkWell(
                            onTap: () => setStateDialog(() => horaSelecionada = h),
                            child: Container(
                              width: 44,
                              alignment: Alignment.center,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: sel ? const Color(0xFF1A237E) : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                h.toString().padLeft(2, '0'),
                                style: TextStyle(color: sel ? Colors.white : Colors.black87, fontWeight: FontWeight.bold),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('2. Escolha o Minuto:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 50,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: 60,
                        itemBuilder: (context, m) {
                          bool sel = minutoSelecionado == m;
                          return InkWell(
                            onTap: () => setStateDialog(() => minutoSelecionado = m),
                            child: Container(
                              width: 44,
                              alignment: Alignment.center,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: sel ? const Color(0xFF1A237E) : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                m.toString().padLeft(2, '0'),
                                style: TextStyle(color: sel ? Colors.white : Colors.black87, fontWeight: FontWeight.bold),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Selecionado: ${horaSelecionada.toString().padLeft(2, '0')}:${minutoSelecionado.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
                    ),
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A237E), foregroundColor: Colors.white),
                    onPressed: () => Navigator.pop(ctx, '${horaSelecionada.toString().padLeft(2, '0')}:${minutoSelecionado.toString().padLeft(2, '0')}'),
                    child: const Text('Confirmar'),
                  ),
                ],
              );
            },
          );
        },
      );
      return resultado ?? horaAtual;
    }

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            
            int timeToMinutes(String time) {
              final parts = time.split(':');
              if (parts.length != 2) return 0;
              return (int.parse(parts[0]) * 60) + int.parse(parts[1]);
            }

            int minInicio = timeToMinutes(horaInicioSelecionada);
            int minFim = timeToMinutes(horaFimSelecionada);
            int minAlmocoIni = timeToMinutes(almocoInicioSelecionado);
            int minAlmocoFim = timeToMinutes(almocoFimSelecionado);

            bool almocoValido = true;
            String? avisoAlmoco;
            if (minFim > minInicio) {
              if (minAlmocoIni < minInicio || minAlmocoFim > minFim || minAlmocoFim <= minAlmocoIni) {
                almocoValido = false;
                avisoAlmoco = 'O almoço deve estar compreendido entre a hora de início e fim!';
              }
            }

            bool temAlmocoDefinido = almocoInicioSelecionado.isNotEmpty && almocoFimSelecionado.isNotEmpty && almocoValido;

            double calcularHorasEfetivas() {
              if (!almocoValido || minFim <= minInicio) return 0.0;
              int minAlmoco = minAlmocoFim - minAlmocoIni;
              int totalMinutos = (minFim - minInicio) - minAlmoco;
              if (totalMinutos < 0) totalMinutos = 0;
              return double.parse((totalMinutos / 60).toStringAsFixed(2));
            }

            double horasEfetivasCalculadas = (tipoDiaSelecionado == 'Trabalho' || tipoDiaSelecionado == 'Folga Trabalhada') ? calcularHorasEfetivas() : 0.0;
            
            final partesContratadas = horasContratadasSelecionadas.split(':');
            double horasContratadasDouble = 8.0;
            if (partesContratadas.length == 2) {
              horasContratadasDouble = int.parse(partesContratadas[0]) + (int.parse(partesContratadas[1]) / 60.0);
            }

            double diferenca = horasEfetivasCalculadas - horasContratadasDouble;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(
                'Registo: ${dia.day}/${dia.month}/${dia.year}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1A237E)),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Selecione o Estado do Dia', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        {'nome': 'Trabalho', 'icone': Icons.work},
                        {'nome': 'Folga', 'icone': Icons.weekend},
                        {'nome': 'Folga Trabalhada', 'icone': Icons.work_history},
                        {'nome': 'Férias', 'icone': Icons.beach_access},
                        {'nome': 'Falta', 'icone': Icons.warning_amber},
                        {'nome': 'Baixa', 'icone': Icons.local_hospital},
                      ].map((mapa) {
                        String tipo = mapa['nome'] as String;
                        IconData icone = mapa['icone'] as IconData;
                        bool selecionado = tipoDiaSelecionado == tipo;
                        return ChoiceChip(
                          avatar: Icon(icone, size: 16, color: selecionado ? Colors.white : const Color(0xFF1A237E)),
                          label: Text(tipo),
                          selected: selecionado,
                          selectedColor: const Color(0xFF1A237E),
                          labelStyle: TextStyle(color: selecionado ? Colors.white : Colors.black87),
                          onSelected: (bool selected) {
                            if (selected) {
                              setStateModal(() {
                                tipoDiaSelecionado = tipo;
                                if (tipo == 'Folga') incluiSubsidio = false;
                              });
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    if (tipoDiaSelecionado == 'Trabalho' || tipoDiaSelecionado == 'Folga Trabalhada') ...[
                      if (tipoDiaSelecionado == 'Trabalho') ...[
                        DropdownButtonFormField<String>(
                          initialValue: horasContratadasSelecionadas,
                          decoration: const InputDecoration(labelText: 'Horas Diárias Contratadas'),
                          items: listaDuracoesContratadas.map((h) => DropdownMenuItem(value: h, child: Text('$h h'))).toList(),
                          onChanged: (val) {
                            if (val != null) setStateModal(() => horasContratadasSelecionadas = val);
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (tipoDiaSelecionado == 'Folga Trabalhada') ...[
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(8)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Trabalhar na Folga (Art.º 229.º CT)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 13)),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String>(
                                initialValue: acaoFolgaTrabalhada,
                                decoration: const InputDecoration(labelText: 'Tratamento das Horas'),
                                items: ['Banco de Horas', 'Pagar', 'Voluntariado']
                                    .map((opt) => DropdownMenuItem(value: opt, child: Text(opt)))
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) setStateModal(() => acaoFolgaTrabalhada = val);
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                String novaHora = await selecionarHoraMinutoRelogio(context, horaInicioSelecionada);
                                setStateModal(() => horaInicioSelecionada = novaHora);
                              },
                              child: InputDecorator(
                                decoration: const InputDecoration(labelText: 'Hora Início', suffixIcon: Icon(Icons.access_time)),
                                child: Text(horaInicioSelecionada, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                String novaHora = await selecionarHoraMinutoRelogio(context, horaFimSelecionada);
                                setStateModal(() => horaFimSelecionada = novaHora);
                              },
                              child: InputDecorator(
                                decoration: const InputDecoration(labelText: 'Hora Fim', suffixIcon: Icon(Icons.access_time)),
                                child: Text(horaFimSelecionada, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text('Intervalo de Almoço', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                String novaHora = await selecionarHoraMinutoRelogio(context, almocoInicioSelecionado);
                                setStateModal(() => almocoInicioSelecionado = novaHora);
                              },
                              child: InputDecorator(
                                decoration: const InputDecoration(labelText: 'Almoço Início', suffixIcon: Icon(Icons.access_time)),
                                child: Text(almocoInicioSelecionado, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                String novaHora = await selecionarHoraMinutoRelogio(context, almocoFimSelecionado);
                                setStateModal(() => almocoFimSelecionado = novaHora);
                              },
                              child: InputDecorator(
                                decoration: const InputDecoration(labelText: 'Almoço Fim', suffixIcon: Icon(Icons.access_time)),
                                child: Text(almocoFimSelecionado, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (!almocoValido) ...[
                        const SizedBox(height: 6),
                        Text(avisoAlmoco ?? '', style: const TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total Efetivo Calculado:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            Text('${horasEfetivasCalculadas.toStringAsFixed(2)}h', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1A237E))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (tipoDiaSelecionado == 'Trabalho' && diferenca > 0.01) ...[
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Excesso: +${diferenca.toStringAsFixed(2)}h', style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String>(
                                initialValue: acaoExcesso,
                                decoration: const InputDecoration(labelText: 'Ação para o Excesso'),
                                items: ['Banco de Horas', 'Pagar', 'Não fazer nada']
                                    .map((opt) => DropdownMenuItem(value: opt, child: Text(opt)))
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) setStateModal(() => acaoExcesso = val);
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (tipoDiaSelecionado == 'Trabalho' && diferenca < -0.01) ...[
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Défice de horas: ${diferenca.toStringAsFixed(2)}h', style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String>(
                                initialValue: acaoFalta,
                                decoration: const InputDecoration(labelText: 'Tratamento do Défice'),
                                items: ['Descontar no Banco', 'Descontar no Salário', 'Não fazer nada']
                                    .map((opt) => DropdownMenuItem(value: opt, child: Text(opt)))
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) setStateModal(() => acaoFalta = val);
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      SwitchListTile(
                        title: const Text('Inclui Subsídio de Alimentação', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          temAlmocoDefinido ? 'Subsídio ativo' : 'Indisponível (Defina almoço válido)',
                          style: TextStyle(fontSize: 11, color: temAlmocoDefinido ? Colors.grey.shade700 : Colors.red),
                        ),
                        value: incluiSubsidio,
                        activeThumbColor: const Color(0xFF1A237E),
                        onChanged: temAlmocoDefinido ? (val) => setStateModal(() => incluiSubsidio = val) : null,
                      ),
                    ],

                    if (tipoDiaSelecionado == 'Falta') ...[
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DropdownButtonFormField<String>(
                              initialValue: tipoJustificacao,
                              decoration: const InputDecoration(labelText: 'Tipo de Falta'),
                              items: ['Justificado', 'Injustificado']
                                  .map((opt) => DropdownMenuItem(value: opt, child: Text(opt)))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) setStateModal(() => tipoJustificacao = val);
                              },
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue: acaoFalta,
                              decoration: const InputDecoration(labelText: 'Efeito Salarial da Falta'),
                              items: ['Descontar no Salário', 'Não descontar no salário']
                                  .map((opt) => DropdownMenuItem(value: opt, child: Text(opt)))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) setStateModal(() => acaoFalta = val);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (tipoDiaSelecionado == 'Férias' || tipoDiaSelecionado == 'Folga' || tipoDiaSelecionado == 'Baixa') ...[
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            'Estado selecionado: $tipoDiaSelecionado',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                          ),
                        ),
                      ),
                    ],
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
                  onPressed: (tipoDiaSelecionado == 'Trabalho' || tipoDiaSelecionado == 'Folga Trabalhada') && !almocoValido ? null : () async {
                    double hEfetivas = (tipoDiaSelecionado == 'Trabalho' || tipoDiaSelecionado == 'Folga Trabalhada') ? calcularHorasEfetivas() : 0.0;
                    double diff = hEfetivas - horasContratadasDouble;

                    double horasExtraPagas = 0.0;
                    double horasDescontoSalario = 0.0;

                    if (tipoDiaSelecionado == 'Trabalho') {
                      if (diff > 0.01 && acaoExcesso == 'Pagar') horasExtraPagas = diff;
                      if (diff < -0.01 && acaoFalta == 'Descontar no Salário') horasDescontoSalario = diff.abs();
                    } else if (tipoDiaSelecionado == 'Folga Trabalhada') {
                      if (acaoFolgaTrabalhada == 'Pagar') horasExtraPagas = hEfetivas;
                    } else if (tipoDiaSelecionado == 'Falta' && acaoFalta == 'Descontar no Salário') {
                      horasDescontoSalario = horasContratadasDouble > 0 ? horasContratadasDouble : 8.0;
                    }

                    await DatabaseHelper.instance.guardarRegistoCompleto(
                      data: chaveData,
                      tipoDia: tipoDiaSelecionado,
                      horasContratadas: tipoDiaSelecionado == 'Trabalho' ? horasContratadasDouble : 0.0,
                      horaInicio: (tipoDiaSelecionado == 'Trabalho' || tipoDiaSelecionado == 'Folga Trabalhada') ? horaInicioSelecionada : '',
                      horaFim: (tipoDiaSelecionado == 'Trabalho' || tipoDiaSelecionado == 'Folga Trabalhada') ? horaFimSelecionada : '',
                      almocoInicio: (tipoDiaSelecionado == 'Trabalho' || tipoDiaSelecionado == 'Folga Trabalhada') ? almocoInicioSelecionado : '',
                      almocoFim: (tipoDiaSelecionado == 'Trabalho' || tipoDiaSelecionado == 'Folga Trabalhada') ? almocoFimSelecionado : '',
                      horasEfetivas: hEfetivas,
                      horasExtraPagas: horasExtraPagas,
                      horasDescontoSalario: horasDescontoSalario,
                      acaoExcesso: acaoExcesso,
                      acaoFalta: acaoFalta,
                      tipoJustificacao: tipoJustificacao,
                      incluiSubsidio: ((tipoDiaSelecionado == 'Trabalho' || tipoDiaSelecionado == 'Folga Trabalhada') && incluiSubsidio) ? 1 : 0,
                    );

                    DriveService.fazerUploadBackup();

                    onAtualizado();
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
}