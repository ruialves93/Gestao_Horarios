import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

class ExportHelper {
  // --- GERADOR DE PDF 1: RELATÓRIO DO BANCO DE HORAS MENSAL ---
  static Future<File> gerarPDF({
    required Map<String, dynamic> perfil,
    required List<Map<String, dynamic>> registosMes,
    required int ano,
    required int mes,
  }) async {
    final pdf = pw.Document(
      title: 'Relatório Mensal do Banco de Horas',
      author: 'Rui Barata',
      creator: 'Gestão de Horários - Rui Barata © 2026',
      subject: 'Código do Trabalho - Lei n.º 7/2009',
    );
    pw.MemoryImage? imageLogo;

    try {
      final ByteData bytes = await rootBundle.load('assets/logo_rb.png');
      imageLogo = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) {}

    final List<String> nomesMeses = [
      'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
    ];
    String nomeMesStr = nomesMeses[mes - 1];

    double salarioBase = (perfil['salarioBase'] as num?)?.toDouble() ?? 1000.0;
    double valorHoraBase = salarioBase / 174.0;

    double totalHorasExtraMes = 0.0;
    double totalValorExtraMes = 0.0;

    final List<List<String>> linhasTabela = [];
    int totalDiasMes = DateUtils.getDaysInMonth(ano, mes);

    for (int d = 1; d <= totalDiasMes; d++) {
      String diaStr = '$ano-${mes.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';

      var reg = registosMes.firstWhere(
        (r) => r['data'].toString() == diaStr,
        orElse: () => {},
      );

      String entrada = '-';
      String saida = '-';
      String almoco = '-';
      String horasExtraTexto = '-';
      String valorTexto = '-';

      if (reg.isNotEmpty) {
        entrada = reg['horaInicio']?.toString() ?? '-';
        saida = reg['horaFim']?.toString() ?? '-';

        if (reg['horaAlmocoInicio'] != null && reg['horaAlmocoFim'] != null) {
          almoco = '${reg['horaAlmocoInicio']} - ${reg['horaAlmocoFim']}';
        }

        double credito = (reg['horasCreditoBanco'] as num?)?.toDouble() ?? 0.0;
        double debito = (reg['horasDebitoBanco'] as num?)?.toDouble() ?? 0.0;
        double extraPaga = (reg['horasExtraPagas'] as num?)?.toDouble() ?? 0.0;

        if (credito > 0) {
          horasExtraTexto = '+${credito.toStringAsFixed(2)}h';
          totalHorasExtraMes += credito;
          if (extraPaga > 0) {
            double val = extraPaga * valorHoraBase * 1.25;
            totalValorExtraMes += val;
            valorTexto = '${val.toStringAsFixed(2)} EUR';
          } else {
            valorTexto = 'B. Horas';
          }
        } else if (debito > 0) {
          horasExtraTexto = '-${debito.toStringAsFixed(2)}h (falta)';
          valorTexto = '0.00 EUR';
        } else if (extraPaga > 0) {
          horasExtraTexto = '+${extraPaga.toStringAsFixed(2)}h';
          totalHorasExtraMes += extraPaga;
          double val = extraPaga * valorHoraBase * 1.25;
          totalValorExtraMes += val;
          valorTexto = '${val.toStringAsFixed(2)} EUR';
        }
      }

      linhasTabela.add([
        d.toString().padLeft(2, '0'),
        entrada,
        saida,
        almoco,
        horasExtraTexto,
        valorTexto,
      ]);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Relatório de Banco de Horas Mensal',
                        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Período: $nomeMesStr de $ano', style: const pw.TextStyle(fontSize: 11)),
                    pw.Text('Trabalhador: ${perfil['nomeTrabalhador'] ?? ''} | Empresa: ${perfil['nomeEmpresa'] ?? ''}',
                        style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('Desenvolvimento por Rui Barata © 2026',
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                    pw.Text('Enquadramento: Código do Trabalho (Lei n.º 7/2009, art.º 208.º - Banco de Horas)',
                        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                  ],
                ),
                if (imageLogo != null) pw.ClipOval(child: pw.Image(imageLogo, width: 44, height: 44)),
              ],
            ),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 10),
            pw.Table.fromTextArray(
              headers: ['Dia', 'Entrada', 'Saída', 'Intervalo Almoço', 'Banco / Extra', 'Valor Extra'],
              data: [
                ...linhasTabela,
                [
                  'TOTAL',
                  '',
                  '',
                  '',
                  '${totalHorasExtraMes.toStringAsFixed(2)}h',
                  '${totalValorExtraMes.toStringAsFixed(2)} EUR'
                ]
              ],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo900),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignment: pw.Alignment.center,
            ),
            pw.SizedBox(height: 16),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Documento digital autêntico - Proibida a edição e modificação de dados.',
                    style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                pw.Text('Desenvolvimento por Rui Barata © 2026',
                    style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
              ],
            ),
          ];
        },
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'relatorio_banco_horas_mensal.pdf'));
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  // --- GERADOR DE PDF 2: RELATÓRIO FINANCEIRO E SALARIAL DETALHADO POR DIA ---
  static Future<File> gerarPDFValoresReceberDetalhado({
    required Map<String, dynamic> perfil,
    required List<Map<String, dynamic>> registosMes,
    required int ano,
    required int mes,
  }) async {
    final pdf = pw.Document(
      title: 'Extrato Salarial e Valores Diários a Receber',
      author: 'Rui Barata',
      creator: 'Gestão de Horários - Rui Barata © 2026',
      subject: 'Código do Trabalho - Artigos 208, 268 e 271 da Lei n.º 7/2009',
    );

    pw.MemoryImage? imageLogo;
    try {
      final ByteData bytes = await rootBundle.load('assets/logo_rb.png');
      imageLogo = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) {}

    final List<String> nomesMeses = [
      'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
    ];
    String nomeMesStr = nomesMeses[mes - 1];

    double salarioBase = (perfil['salarioBase'] as num?)?.toDouble() ?? 1000.0;
    double valorHoraBase = salarioBase / 174.0;

    double somaValorHorasExtra = 0.0;
    double somaValorDescontos = 0.0;
    double somaHorasExtra = 0.0;
    double somaHorasDesconto = 0.0;

    final List<List<String>> linhasTabela = [];
    int totalDiasMes = DateUtils.getDaysInMonth(ano, mes);

    for (int d = 1; d <= totalDiasMes; d++) {
      String diaStr = '$ano-${mes.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
      DateTime dataObj = DateTime(ano, mes, d);
      final List<String> siglasSemana = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
      String diaSemanaSigla = siglasSemana[dataObj.weekday - 1];

      var reg = registosMes.firstWhere(
        (r) => r['data'].toString() == diaStr,
        orElse: () => {},
      );

      String tipoDia = 'Descanso';
      String extraPagaStr = '-';
      String descSalarioStr = '-';
      String valorExtraStr = '-';
      String valorDescStr = '-';
      String subtotalDiaStr = '-';

      if (reg.isNotEmpty) {
        tipoDia = reg['tipoDia']?.toString() ?? 'Trabalho';
        double extraPaga = (reg['horasExtraPagas'] as num?)?.toDouble() ?? 0.0;
        double descSalario = (reg['horasDescontoSalario'] as num?)?.toDouble() ?? 0.0;

        double valorExtra = 0.0;
        double valorDesc = 0.0;

        if (extraPaga > 0) {
          valorExtra = extraPaga * valorHoraBase * 1.25;
          extraPagaStr = '${extraPaga.toStringAsFixed(2)}h';
          valorExtraStr = '+${valorExtra.toStringAsFixed(2)} EUR';
          somaHorasExtra += extraPaga;
          somaValorHorasExtra += valorExtra;
        }

        if (descSalario > 0) {
          valorDesc = descSalario * valorHoraBase;
          descSalarioStr = '${descSalario.toStringAsFixed(2)}h';
          valorDescStr = '-${valorDesc.toStringAsFixed(2)} EUR';
          somaHorasDesconto += descSalario;
          somaValorDescontos += valorDesc;
        }

        double saldoFinDia = valorExtra - valorDesc;
        if (saldoFinDia > 0) {
          subtotalDiaStr = '+${saldoFinDia.toStringAsFixed(2)} EUR';
        } else if (saldoFinDia < 0) {
          subtotalDiaStr = '${saldoFinDia.toStringAsFixed(2)} EUR';
        } else if (extraPaga > 0 || descSalario > 0) {
          subtotalDiaStr = '0.00 EUR';
        }
      }

      linhasTabela.add([
        '${d.toString().padLeft(2, '0')} ($diaSemanaSigla)',
        tipoDia,
        extraPagaStr,
        valorExtraStr,
        descSalarioStr,
        valorDescStr,
        subtotalDiaStr,
      ]);
    }

    double totalFinalAReceber = salarioBase + somaValorHorasExtra - somaValorDescontos;
    final dataEmissao =
        "${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year} às ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}";

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(22),
        build: (pw.Context context) {
          return [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Extrato Salarial e Valores Diários a Receber',
                        style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
                    pw.Text('Período: $nomeMesStr de $ano', style: const pw.TextStyle(fontSize: 11)),
                    pw.Text(
                      'Trabalhador: ${perfil['nomeTrabalhador'] ?? ''} | Empresa: ${perfil['nomeEmpresa'] ?? ''}',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                    pw.Text('Desenvolvimento por Rui Barata © 2026',
                        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                  ],
                ),
                if (imageLogo != null) pw.ClipOval(child: pw.Image(imageLogo, width: 44, height: 44)),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 6),

            pw.Container(
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Salário Base: ${salarioBase.toStringAsFixed(2)} EUR',
                          style: const pw.TextStyle(fontSize: 9)),
                      pw.Text('Valor Hora Base: ${valorHoraBase.toStringAsFixed(2)} EUR/h',
                          style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                          'Extra Paga (${somaHorasExtra.toStringAsFixed(2)}h): +${somaValorHorasExtra.toStringAsFixed(2)} EUR',
                          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                      pw.Text(
                          'Descontos (${somaHorasDesconto.toStringAsFixed(2)}h): -${somaValorDescontos.toStringAsFixed(2)} EUR',
                          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.red900)),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: pw.BoxDecoration(color: PdfColors.indigo900, borderRadius: pw.BorderRadius.circular(4)),
                    child: pw.Column(
                      children: [
                        pw.Text('TOTAL ESTIMADO', style: pw.TextStyle(fontSize: 8, color: PdfColors.white)),
                        pw.Text('${totalFinalAReceber.toStringAsFixed(2)} EUR',
                            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),

            pw.Table.fromTextArray(
              headers: ['Dia', 'Tipo de Dia', 'Horas Extra', 'Valor Extra', 'Défice/Falta', 'Desconto', 'Ajuste Dia'],
              data: [
                ...linhasTabela,
                [
                  'TOTAIS',
                  '-',
                  '${somaHorasExtra.toStringAsFixed(2)}h',
                  '+${somaValorHorasExtra.toStringAsFixed(2)} EUR',
                  '${somaHorasDesconto.toStringAsFixed(2)}h',
                  '-${somaValorDescontos.toStringAsFixed(2)} EUR',
                  '${(somaValorHorasExtra - somaValorDescontos) >= 0 ? '+' : ''}${(somaValorHorasExtra - somaValorDescontos).toStringAsFixed(2)} EUR'
                ]
              ],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo900),
              cellStyle: const pw.TextStyle(fontSize: 7.5),
              cellAlignment: pw.Alignment.center,
            ),
            pw.SizedBox(height: 12),

            pw.Container(
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                color: PdfColors.grey50,
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('BASE LEGAL E ENQUADRAMENTO JURÍDICO (CÓDIGO DO TRABALHO - LEI N.º 7/2009):',
                      style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                  pw.Text(
                    '1. Valor/Hora: art.º 271.º (fórmula legal [(Salário x 12) / (52 x n.º horas normais semanais)]).\n'
                    '2. Trabalho Suplementar: art.º 268.º, n.º 1 (majoração de 25% na primeira hora ou fração em dia de trabalho útil).\n'
                    '3. Banco de Horas: art.º 208.º e liquidação salarial subsidiária de créditos e débitos.\n'
                    '4. Documento digital oficial não editável gerado pelo software de gestão de horários.',
                    style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey800),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Data e hora de emissão: $dataEmissao',
                    style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                pw.Text('Desenvolvimento por Rui Barata © 2026',
                    style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
              ],
            ),
          ];
        },
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'extrato_salarial_detalhado_${ano}_$mes.pdf'));
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  // --- GERADOR DE PDF 3: MAPA DE FÉRIAS ANUAL (CALENDÁRIO DETALHADO POR MÊS E ANO) ---
  static Future<File> gerarPDFMapaFerias({
    required Map<String, dynamic> perfil,
    required List<Map<String, dynamic>> registosAno,
    required int ano,
  }) async {
    final pdf = pw.Document(
      title: 'Mapa de Férias Anual - $ano',
      author: 'Rui Barata',
      creator: 'Gestão de Horários - Rui Barata © 2026',
      subject: 'Código do Trabalho - Artigos 237 a 247 da Lei n.º 7/2009',
    );

    pw.MemoryImage? imageLogo;
    try {
      final ByteData bytes = await rootBundle.load('assets/logo_rb.png');
      imageLogo = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) {}

    int totalDiasFeriasAno = 0;
    final Set<String> datasFerias = {};

    for (var r in registosAno) {
      if (r['tipoDia']?.toString() == 'Férias') {
        totalDiasFeriasAno++;
        datasFerias.add(r['data'].toString());
      }
    }

    final List<String> nomesMeses = [
      'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
    ];

    final agora = DateTime.now();
    final dataHora =
        "${agora.day.toString().padLeft(2, '0')}/${agora.month.toString().padLeft(2, '0')}/${agora.year} às ${agora.hour.toString().padLeft(2, '0')}:${agora.minute.toString().padLeft(2, '0')}";

    // Construtor do Mini-Calendário de Cada Mês
    pw.Widget buildCalendarioMes(int mes) {
      int totalDias = DateUtils.getDaysInMonth(ano, mes);
      DateTime primeiroDia = DateTime(ano, mes, 1);
      int offsetInicio = primeiroDia.weekday - 1; // 0 = Seg, 6 = Dom

      int feriasDoMes = 0;
      for (int dia = 1; dia <= totalDias; dia++) {
        String dataStr = '$ano-${mes.toString().padLeft(2, '0')}-${dia.toString().padLeft(2, '0')}';
        if (datasFerias.contains(dataStr)) {
          feriasDoMes++;
        }
      }

      final cabecalhoDias = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

      // Construção das linhas de semanas para o mês
      List<pw.TableRow> linhasSemanas = [];
      int diaAtual = 1;

      while (diaAtual <= totalDias) {
        List<pw.Widget> celulasSemana = [];

        for (int col = 0; col < 7; col++) {
          if (linhasSemanas.isEmpty && col < offsetInicio) {
            celulasSemana.add(pw.Container(
              height: 18,
              color: PdfColors.grey100,
            ));
          } else if (diaAtual > totalDias) {
            celulasSemana.add(pw.Container(
              height: 18,
              color: PdfColors.grey100,
            ));
          } else {
            String dataStr = '$ano-${mes.toString().padLeft(2, '0')}-${diaAtual.toString().padLeft(2, '0')}';
            bool isFerias = datasFerias.contains(dataStr);
            bool isFimDeSemana = (col >= 5);

            celulasSemana.add(
              pw.Container(
                height: 18,
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(
                  color: isFerias
                      ? PdfColors.amber300
                      : (isFimDeSemana ? PdfColors.grey200 : PdfColors.white),
                  border: pw.Border.all(
                    color: isFerias ? PdfColors.amber800 : PdfColors.grey300,
                    width: isFerias ? 0.8 : 0.4,
                  ),
                ),
                child: pw.Text(
                  '$diaAtual',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: isFerias ? pw.FontWeight.bold : pw.FontWeight.normal,
                    color: isFerias
                        ? PdfColors.amber900
                        : (isFimDeSemana ? PdfColors.grey700 : PdfColors.black),
                  ),
                ),
              ),
            );
            diaAtual++;
          }
        }

        linhasSemanas.add(pw.TableRow(children: celulasSemana));
      }

      return pw.Container(
        width: 245,
        margin: const pw.EdgeInsets.all(4),
        decoration: pw.BoxDecoration(
          border: pw.TableBorder.all(color: PdfColors.indigo900, width: 0.8),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // Barra de Título do Mês com Contagem de Férias do Mês
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: const pw.BoxDecoration(
                color: PdfColors.indigo900,
                borderRadius: pw.BorderRadius.vertical(top: pw.Radius.circular(3)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    nomesMeses[mes - 1].toUpperCase(),
                    style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9.5),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: pw.BoxDecoration(
                      color: feriasDoMes > 0 ? PdfColors.amber400 : PdfColors.indigo700,
                      borderRadius: pw.BorderRadius.circular(3),
                    ),
                    child: pw.Text(
                      'Férias: $feriasDoMes d',
                      style: pw.TextStyle(
                        color: feriasDoMes > 0 ? PdfColors.black : PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 8.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Tabela com Dias da Semana e Dias do Mês
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.4),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: cabecalhoDias
                      .map((d) => pw.Container(
                            alignment: pw.Alignment.center,
                            padding: const pw.EdgeInsets.symmetric(vertical: 2),
                            child: pw.Text(
                              d,
                              style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
                            ),
                          ))
                      .toList(),
                ),
                ...linhasSemanas,
              ],
            ),
          ],
        ),
      );
    }

    // Função de Construção da Página Semestral (6 meses por folha)
    pw.Page buildPaginaSemestre({
      required int mesInicio,
      required int mesFim,
      required String tituloSemestre,
      required int totalFeriasSemestre,
    }) {
      return pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Cabeçalho Oficial
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('MAPA DE FÉRIAS ANUAL — $ano',
                          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
                      pw.Text(
                        'Trabalhador: ${perfil['nomeTrabalhador'] ?? ''} | Empresa: ${perfil['nomeEmpresa'] ?? ''}',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                      pw.Text('$tituloSemestre | Subtotal Semestre: $totalFeriasSemestre dias',
                          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
                    ],
                  ),
                  // Caixa Destaque com Total de Férias Anual
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.amber100,
                      border: pw.Border.all(color: PdfColors.amber800, width: 1),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text('TOTAL ANUAL GOZADO',
                            style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.amber900)),
                        pw.Text('$totalDiasFeriasAno DIAS',
                            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
                      ],
                    ),
                  ),
                  if (imageLogo != null) pw.ClipOval(child: pw.Image(imageLogo, width: 40, height: 40)),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 1, color: PdfColors.indigo900),
              pw.SizedBox(height: 6),

              // Grelha de 6 Meses (2 linhas de 3 meses)
              pw.Expanded(
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        buildCalendarioMes(mesInicio),
                        buildCalendarioMes(mesInicio + 1),
                        buildCalendarioMes(mesInicio + 2),
                      ],
                    ),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        buildCalendarioMes(mesInicio + 3),
                        buildCalendarioMes(mesInicio + 4),
                        buildCalendarioMes(mesInicio + 5),
                      ],
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 6),
              pw.Divider(thickness: 0.5),
              // Rodapé com Legenda, Legislação e Autoria
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Row(
                    children: [
                      pw.Container(width: 10, height: 10, color: PdfColors.amber300, margin: const pw.EdgeInsets.only(right: 4)),
                      pw.Text('Dia de Férias Gozado', style: const pw.TextStyle(fontSize: 7.5)),
                      pw.SizedBox(width: 12),
                      pw.Text('Enquadramento: Artigos 237.º a 247.º do Código do Trabalho (Lei n.º 7/2009)',
                          style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Text('Emitido em: $dataHora | Desenvolvimento por Rui Barata © 2026',
                      style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                ],
              ),
            ],
          );
        },
      );
    }

    // Calcula férias do 1º e 2º semestre
    int ferias1Sem = 0;
    int ferias2Sem = 0;
    for (var r in registosAno) {
      if (r['tipoDia']?.toString() == 'Férias') {
        DateTime? d = DateTime.tryParse(r['data'].toString());
        if (d != null) {
          if (d.month <= 6) ferias1Sem++;
          else ferias2Sem++;
        }
      }
    }

    // Página 1: 1.º Semestre (Janeiro a Junho)
    pdf.addPage(buildPaginaSemestre(
      mesInicio: 1,
      mesFim: 6,
      tituloSemestre: '1.º Semestre (Janeiro a Junho)',
      totalFeriasSemestre: ferias1Sem,
    ));

    // Página 2: 2.º Semestre (Julho a Dezembro)
    pdf.addPage(buildPaginaSemestre(
      mesInicio: 7,
      mesFim: 12,
      tituloSemestre: '2.º Semestre (Julho a Dezembro)',
      totalFeriasSemestre: ferias2Sem,
    ));

    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'mapa_ferias_anual_$ano.pdf'));
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  // --- MODAL DE GESTÃO DAS 3 OPÇÕES (VER, EXPORTAR, PARTILHAR) ---
  static void mostrarOpcoesExportacao({
    required BuildContext context,
    required String tipo,
    required File ficheiro,
    required Function(String mensagem) onFeedback,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              title: Text('Relatório: $tipo', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Selecione a ação desejada:'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.visibility, color: Colors.blue),
              title: const Text('Ver'),
              subtitle: const Text('Abrir o PDF no leitor predefinido'),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  final result = await OpenFilex.open(ficheiro.path);
                  if (result.type != ResultType.done) {
                    onFeedback('Aviso: ${result.message}');
                  }
                } catch (e) {
                  onFeedback('Erro ao abrir: $e');
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open, color: Colors.amber),
              title: const Text('Exportar'),
              subtitle: const Text('Guardar na pasta Downloads'),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  Directory? downloadsDir = Directory('/storage/emulated/0/Download');
                  if (!await downloadsDir.exists()) {
                    downloadsDir = await getExternalStorageDirectory();
                  }
                  downloadsDir ??= await getApplicationDocumentsDirectory();

                  final nomeFicheiro = p.basename(ficheiro.path);
                  final destino = p.join(downloadsDir.path, nomeFicheiro);
                  await ficheiro.copy(destino);
                  onFeedback('Ficheiro guardado em:\n$destino');
                } catch (e) {
                  onFeedback('Erro ao exportar: $e');
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.green),
              title: const Text('Partilhar'),
              subtitle: const Text('Enviar via WhatsApp, Email, etc.'),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  await Share.shareXFiles(
                    [XFile(ficheiro.path)],
                    text: 'Relatório $tipo - Rui Barata © 2026',
                  );
                } catch (e) {
                  onFeedback('Erro ao partilhar: $e');
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}