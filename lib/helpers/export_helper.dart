import 'dart:io';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

class ExportHelper {
  /// Função auxiliar para formatar horas decimais para o formato "HH:mm" (ex: 0.3 -> "00:18h", 1.5 -> "+01:30h")
  static String _formatarHorasPdf(double horasDecimais, {bool incluirSinal = true}) {
    int minutosTotais = (horasDecimais * 60).round();
    bool negativo = minutosTotais < 0;
    minutosTotais = minutosTotais.abs();

    int horas = minutosTotais ~/ 60;
    int minutos = minutosTotais % 60;

    String hStr = horas.toString().padLeft(2, '0');
    String mStr = minutos.toString().padLeft(2, '0');
    String sinalStr = '';

    if (incluirSinal) {
      if (negativo) {
        sinalStr = '-';
      } else if (horasDecimais > 0) {
        sinalStr = '+';
      }
    } else if (negativo) {
      sinalStr = '-';
    }

    return '$sinalStr$hStr:$mStr h';
  }

  // ---------------------------------------------------------------------------
  // 1. GERAR PDF RESUMO ANUAL (BANCO DE HORAS & RENDIMENTOS - LEI N.º 7/2009)
  // ---------------------------------------------------------------------------
  static Future<File> gerarPDFResumoAnual({
    required Map<String, dynamic> perfil,
    required List<Map<String, dynamic>> registosAno,
    required int ano,
  }) async {
    final pdf = pw.Document(compress: true);

    pw.MemoryImage? logoImage;
    try {
      final logoBytes = await rootBundle.load('assets/logo_rb.png');
      logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
    } catch (_) {}

    String nomeTrabalhador = perfil['nomeTrabalhador']?.isNotEmpty == true ? perfil['nomeTrabalhador'] : 'Rui Barata';
    String nomeEmpresa = perfil['nomeEmpresa']?.isNotEmpty == true ? perfil['nomeEmpresa'] : 'Empresa';
    double salarioBase = (perfil['salarioBase'] as num?)?.toDouble() ?? 1000.0;
    double valorSubsidioDiario = (perfil['valorSubsidioAlimentacao'] as num?)?.toDouble() ?? 6.0;
    double valorHoraBase = salarioBase / 174.0;

    List<List<String>> dadosTabela = [];
    double totalHorasBancoGanhas = 0.0;
    double totalHorasBancoDescontadas = 0.0;
    int totalDiasFerias = 0;
    int totalDiasFolgas = 0;
    int totalDiasFaltas = 0;
    int totalDiasBaixas = 0;
    double totalValorExtraEurosAnual = 0.0;
    double totalValorDescontosEurosAnual = 0.0;
    double totalSubsidioAlimentacaoAnual = 0.0;

    final nomesMeses = [
      'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
      'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'
    ];

    for (int m = 1; m <= 12; m++) {
      double mGanhas = 0.0;
      double mDescontadas = 0.0;
      int mFerias = 0;
      int mFolgas = 0;
      int mFaltas = 0;
      int mBaixas = 0;
      double mExtraEuros = 0.0;
      double mDescEuros = 0.0;
      double mSubsidioEuros = 0.0;

      String mesFiltro = "$ano-${m.toString().padLeft(2, '0')}";
      var registosDoMes = registosAno.where((r) => (r['data'] ?? '').toString().startsWith(mesFiltro));

      for (var r in registosDoMes) {
        String tipo = r['tipoDia'] ?? 'Trabalho';
        double hContratadas = (r['horasContratadas'] as num?)?.toDouble() ?? 8.0;
        double hEfetivas = (r['horasEfetivas'] as num?)?.toDouble() ?? 0.0;
        int sub = (r['incluiSubsidio'] as num?)?.toInt() ?? 0;

        if (sub == 1) {
          mSubsidioEuros += valorSubsidioDiario;
        }

        if (tipo == 'Férias') {
          mFerias++;
        } else if (tipo == 'Folga') {
          mFolgas++;
        } else if (tipo == 'Falta') {
          mFaltas++;
          String acaoFalta = r['acaoFaltaTratamento'] ?? 'Descontar no Salário';
          if (acaoFalta == 'Descontar no Banco de Horas') {
            mDescontadas += hContratadas;
          } else {
            mDescEuros += hContratadas * valorHoraBase;
          }
        } else if (tipo == 'Baixa') {
          mBaixas++;
          mDescEuros += hContratadas * valorHoraBase;
        } else if (tipo == 'Trabalho') {
          double diff = hEfetivas - hContratadas;
          if (diff > 0.01) {
            String acao = r['acaoExcesso'] ?? 'Banco de Horas';
            if (acao == 'Banco de Horas') {
              mGanhas += diff;
            } else if (acao == 'Pagar') {
              mExtraEuros += diff * valorHoraBase * 1.25;
            }
          } else if (diff < -0.01) {
            String acaoFalta = r['acaoFalta'] ?? 'Descontar no Banco';
            if (acaoFalta == 'Descontar no Banco') {
              mDescontadas += diff.abs();
            } else if (acaoFalta == 'Descontar no Salário') {
              mDescEuros += diff.abs() * valorHoraBase;
            }
          }
        } else if (tipo == 'Folga Trabalhada') {
          String acao = r['acaoFolgaTrabalhada'] ?? 'Banco de Horas';
          if (acao == 'Banco de Horas') {
            mGanhas += hEfetivas;
          } else if (acao == 'Salário') {
            mExtraEuros += hEfetivas * valorHoraBase * 1.25;
          }
        }
      }

      totalHorasBancoGanhas += mGanhas;
      totalHorasBancoDescontadas += mDescontadas;
      totalDiasFerias += mFerias;
      totalDiasFolgas += mFolgas;
      totalDiasFaltas += mFaltas;
      totalDiasBaixas += mBaixas;
      totalValorExtraEurosAnual += mExtraEuros;
      totalValorDescontosEurosAnual += mDescEuros;
      totalSubsidioAlimentacaoAnual += mSubsidioEuros;

      double saldoMes = mGanhas - mDescontadas;
      dadosTabela.add([
        nomesMeses[m - 1],
        _formatarHorasPdf(mGanhas),
        _formatarHorasPdf(mDescontadas, incluirSinal: false),
        _formatarHorasPdf(saldoMes),
        "${mFerias}d",
        "${mFolgas}d",
        "${mFaltas}d",
        "${mBaixas}d",
        "${mExtraEuros.toStringAsFixed(2)} EUR",
        "${mDescEuros.toStringAsFixed(2)} EUR",
        "${mSubsidioEuros.toStringAsFixed(2)} EUR",
      ]);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          _construirCabecalhoPdf(
            logo: logoImage,
            titulo: 'RESUMO ANUAL DE REGISTO E BANCO DE HORAS',
            subtitulo: 'Regulamentação Laboral e Extrato Global de $ano (Lei n.º 7/2009)',
            trabalhador: nomeTrabalhador,
            empresa: nomeEmpresa,
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: [
              'Mês', 'H. Ganhas', 'H. Desconto', 'Saldo Banco',
              'Férias', 'Folgas', 'Faltas', 'Baixas',
              'Valor Extra', 'Descontos', 'Subs. Alim.'
            ],
            data: dadosTabela,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1A237E)),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignment: pw.Alignment.center,
            cellPadding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          ),
          pw.SizedBox(height: 14),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _construirCaixaResumoPdf('Total H. Ganhas', _formatarHorasPdf(totalHorasBancoGanhas), PdfColors.green800),
              _construirCaixaResumoPdf('Total H. Descontadas', _formatarHorasPdf(-totalHorasBancoDescontadas, incluirSinal: false), PdfColors.red800),
              _construirCaixaResumoPdf('Saldo Final Banco', _formatarHorasPdf(totalHorasBancoGanhas - totalHorasBancoDescontadas), PdfColors.indigo900),
              _construirCaixaResumoPdf('Total Férias/Folgas', "${totalDiasFerias}d / ${totalDiasFolgas}d", PdfColors.blue800),
              _construirCaixaResumoPdf('Total Faltas/Baixas', "${totalDiasFaltas}d / ${totalDiasBaixas}d", PdfColors.orange900),
              _construirCaixaResumoPdf('Extras em EUR', "+${totalValorExtraEurosAnual.toStringAsFixed(2)} EUR", PdfColors.green900),
              _construirCaixaResumoPdf('Descontos em EUR', "-${totalValorDescontosEurosAnual.toStringAsFixed(2)} EUR", PdfColors.red900),
              _construirCaixaResumoPdf('Total Subs. Alim.', "${totalSubsidioAlimentacaoAnual.toStringAsFixed(2)} EUR", PdfColors.brown),
            ],
          ),
          pw.Spacer(),
          _construirRodapePdf(),
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/Resumo_Anual_${ano}_${nomeTrabalhador.replaceAll(' ', '_')}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  // ---------------------------------------------------------------------------
  // 2. GERAR PDF EXTRATO SALARIAL DETALHADO DO MÊS
  // ---------------------------------------------------------------------------
  static Future<File> gerarPDFValoresReceberDetalhado({
    required Map<String, dynamic> perfil,
    required List<Map<String, dynamic>> registosMes,
    required int ano,
    required int mes,
  }) async {
    final pdf = pw.Document(compress: true);

    pw.MemoryImage? logoImage;
    try {
      final logoBytes = await rootBundle.load('assets/logo_rb.png');
      logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
    } catch (_) {}

    String nomeTrabalhador = perfil['nomeTrabalhador']?.isNotEmpty == true ? perfil['nomeTrabalhador'] : 'Rui Barata';
    String nomeEmpresa = perfil['nomeEmpresa']?.isNotEmpty == true ? perfil['nomeEmpresa'] : 'Empresa';
    double salarioBase = (perfil['salarioBase'] as num?)?.toDouble() ?? 1000.0;
    double valorSubsidioDiario = (perfil['valorSubsidioAlimentacao'] as num?)?.toDouble() ?? 6.0;
    double valorHoraBase = salarioBase / 174.0;

    double totalExtraEuros = 0.0;
    double totalDescontoEuros = 0.0;
    double totalSubsidioEuros = 0.0;

    List<List<String>> dadosTabela = [];

    registosMes.sort((a, b) => (a['data'] ?? '').compareTo(b['data'] ?? ''));

    for (var r in registosMes) {
      String data = r['data'] ?? '';
      String tipo = r['tipoDia'] ?? 'Trabalho';
      double hContratadas = (r['horasContratadas'] as num?)?.toDouble() ?? 8.0;
      double hEfetivas = (r['horasEfetivas'] as num?)?.toDouble() ?? 0.0;
      int sub = (r['incluiSubsidio'] as num?)?.toInt() ?? 0;

      double extraDia = 0.0;
      double descDia = 0.0;
      double subDia = sub == 1 ? valorSubsidioDiario : 0.0;

      if (sub == 1) {
        totalSubsidioEuros += valorSubsidioDiario;
      }

      if (tipo == 'Trabalho') {
        double diff = hEfetivas - hContratadas;
        if (diff > 0.01 && r['acaoExcesso'] == 'Pagar') {
          extraDia = diff * valorHoraBase * 1.25;
        } else if (diff < -0.01 && r['acaoFalta'] == 'Descontar no Salário') {
          descDia = diff.abs() * valorHoraBase;
        }
      } else if (tipo == 'Folga Trabalhada' && r['acaoFolgaTrabalhada'] == 'Salário') {
        extraDia = hEfetivas * valorHoraBase * 1.25;
      } else if (tipo == 'Falta' && r['acaoFaltaTratamento'] == 'Descontar no Salário') {
        descDia = hContratadas * valorHoraBase;
      } else if (tipo == 'Baixa') {
        descDia = hContratadas * valorHoraBase;
      }

      totalExtraEuros += extraDia;
      totalDescontoEuros += descDia;

      dadosTabela.add([
        data,
        tipo,
        _formatarHorasPdf(hContratadas, incluirSinal: false),
        _formatarHorasPdf(hEfetivas, incluirSinal: false),
        extraDia > 0 ? "+${extraDia.toStringAsFixed(2)} EUR" : "-",
        descDia > 0 ? "-${descDia.toStringAsFixed(2)} EUR" : "-",
        subDia > 0 ? "${subDia.toStringAsFixed(2)} EUR" : "-",
      ]);
    }

    double totalIliquido = salarioBase + totalExtraEuros - totalDescontoEuros + totalSubsidioEuros;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          _construirCabecalhoPdf(
            logo: logoImage,
            titulo: 'EXTRATO SALARIAL E VALORES A RECEBER',
            subtitulo: 'Período: ${mes.toString().padLeft(2, '0')}/$ano (Lei n.º 7/2009)',
            trabalhador: nomeTrabalhador,
            empresa: nomeEmpresa,
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: ['Data', 'Tipo de Dia', 'Previstas', 'Efetivas', 'Horas Extra (EUR)', 'Descontos (EUR)', 'Subs. Alim.'],
            data: dadosTabela,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1A237E)),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            cellAlignment: pw.Alignment.center,
          ),
          pw.SizedBox(height: 14),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: PdfColors.grey300),
            ),
            child: pw.Column(
              children: [
                _linhaValorExtrato('Vencimento Base:', "${salarioBase.toStringAsFixed(2)} EUR"),
                _linhaValorExtrato('Total Horas Extra (com acréscimo legal):', "+${totalExtraEuros.toStringAsFixed(2)} EUR", corValor: PdfColors.green800),
                _linhaValorExtrato('Total de Descontos (Faltas/Baixas/Défice):', "-${totalDescontoEuros.toStringAsFixed(2)} EUR", corValor: PdfColors.red800),
                _linhaValorExtrato('Total Subsídio de Alimentação:', "+${totalSubsidioEuros.toStringAsFixed(2)} EUR", corValor: PdfColors.brown),
                pw.Divider(),
                _linhaValorExtrato('TOTAL ILÍQUIDO ESTIMADO A RECEBER:', "${totalIliquido.toStringAsFixed(2)} EUR", destaque: true),
              ],
            ),
          ),
          pw.Spacer(),
          _construirRodapePdf(),
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/Extrato_Salarial_${mes}_${ano}_${nomeTrabalhador.replaceAll(' ', '_')}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  // ---------------------------------------------------------------------------
  // 3. GERAR PDF BANCO DE HORAS MENSAL
  // ---------------------------------------------------------------------------
  static Future<File> gerarPDF({
    required Map<String, dynamic> perfil,
    required List<Map<String, dynamic>> registosMes,
    required int ano,
    required int mes,
  }) async {
    final pdf = pw.Document(compress: true);

    pw.MemoryImage? logoImage;
    try {
      final logoBytes = await rootBundle.load('assets/logo_rb.png');
      logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
    } catch (_) {}

    String nomeTrabalhador = perfil['nomeTrabalhador']?.isNotEmpty == true ? perfil['nomeTrabalhador'] : 'Rui Barata';
    String nomeEmpresa = perfil['nomeEmpresa']?.isNotEmpty == true ? perfil['nomeEmpresa'] : 'Empresa';

    double hGanhas = 0.0;
    double hDescontadas = 0.0;

    List<List<String>> dadosTabela = [];
    registosMes.sort((a, b) => (a['data'] ?? '').compareTo(b['data'] ?? ''));

    for (var r in registosMes) {
      String data = r['data'] ?? '';
      String tipo = r['tipoDia'] ?? 'Trabalho';
      double hContratadas = (r['horasContratadas'] as num?)?.toDouble() ?? 8.0;
      double hEfetivas = (r['horasEfetivas'] as num?)?.toDouble() ?? 0.0;
      double diff = hEfetivas - hContratadas;

      String destino = '-';
      if (tipo == 'Trabalho') {
        if (diff > 0.01) {
          destino = r['acaoExcesso'] ?? 'Banco de Horas';
          if (destino == 'Banco de Horas') {
            hGanhas += diff;
          }
        } else if (diff < -0.01) {
          destino = r['acaoFalta'] ?? 'Descontar no Banco';
          if (destino == 'Descontar no Banco') {
            hDescontadas += diff.abs();
          }
        }
      } else if (tipo == 'Folga Trabalhada') {
        destino = r['acaoFolgaTrabalhada'] ?? 'Banco de Horas';
        if (destino == 'Banco de Horas') {
          hGanhas += hEfetivas;
        }
      } else if (tipo == 'Falta' && r['acaoFaltaTratamento'] == 'Descontar no Banco de Horas') {
        destino = 'Desconto no Banco';
        hDescontadas += hContratadas;
      }

      dadosTabela.add([
        data,
        tipo,
        _formatarHorasPdf(hContratadas, incluirSinal: false),
        _formatarHorasPdf(hEfetivas, incluirSinal: false),
        _formatarHorasPdf(diff),
        destino,
      ]);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          _construirCabecalhoPdf(
            logo: logoImage,
            titulo: 'RELATÓRIO MENSAL DO BANCO DE HORAS',
            subtitulo: 'Registo e Movimentações de ${mes.toString().padLeft(2, '0')}/$ano',
            trabalhador: nomeTrabalhador,
            empresa: nomeEmpresa,
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: ['Data', 'Tipo de Dia', 'Horas Previstas', 'Horas Efetivas', 'Diferença', 'Destino / Aplicação'],
            data: dadosTabela,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1A237E)),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            cellAlignment: pw.Alignment.center,
          ),
          pw.SizedBox(height: 14),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _construirCaixaResumoPdf('Horas Ganhas no Banco', _formatarHorasPdf(hGanhas), PdfColors.green800),
              _construirCaixaResumoPdf('Horas Descontadas', _formatarHorasPdf(-hDescontadas, incluirSinal: false), PdfColors.red800),
              _construirCaixaResumoPdf('Saldo do Mês', _formatarHorasPdf(hGanhas - hDescontadas), PdfColors.indigo900),
            ],
          ),
          pw.Spacer(),
          _construirRodapePdf(),
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/Banco_Horas_${mes}_${ano}_${nomeTrabalhador.replaceAll(' ', '_')}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  // ---------------------------------------------------------------------------
  // 4. GERAR PDF MAPA DE FÉRIAS ANUAL
  // ---------------------------------------------------------------------------
  static Future<File> gerarPDFMapaFerias({
    required Map<String, dynamic> perfil,
    required List<Map<String, dynamic>> registosAno,
    required int ano,
  }) async {
    final pdf = pw.Document(compress: true);

    pw.MemoryImage? logoImage;
    try {
      final logoBytes = await rootBundle.load('assets/logo_rb.png');
      logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
    } catch (_) {}

    String nomeTrabalhador = perfil['nomeTrabalhador']?.isNotEmpty == true ? perfil['nomeTrabalhador'] : 'Rui Barata';
    String nomeEmpresa = perfil['nomeEmpresa']?.isNotEmpty == true ? perfil['nomeEmpresa'] : 'Empresa';

    Set<String> diasFeriasSet = {};
    for (var r in registosAno) {
      if (r['tipoDia'] == 'Férias' && r['data'] != null) {
        diasFeriasSet.add(r['data'].toString());
      }
    }

    final nomesMeses = [
      'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
    ];

    Map<int, int> contagemPorMes = {};
    int totalAno = 0;

    for (int m = 1; m <= 12; m++) {
      int count = 0;
      int diasNoMes = DateTime(ano, m + 1, 0).day;
      for (int d = 1; d <= diasNoMes; d++) {
        String dataStr = "$ano-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}";
        if (diasFeriasSet.contains(dataStr)) {
          count++;
        }
      }
      contagemPorMes[m] = count;
      totalAno += count;
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (context) {
          List<pw.Widget> widgets = [
            _construirCabecalhoPdf(
              logo: logoImage,
              titulo: 'MAPA ANUAL DE FÉRIAS E CALENDÁRIO',
              subtitulo: 'Ano Civil de $ano - Controlo e Gozo de Férias (Lei n.º 7/2009)',
              trabalhador: nomeTrabalhador,
              empresa: nomeEmpresa,
            ),
            pw.SizedBox(height: 10),
            pw.Container(
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  pw.Text('RESUMO ANUAL:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: const PdfColor.fromInt(0xFF1A237E))),
                  pw.Text('Total Férias Gozadas: $totalAno Dias', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.blue800)),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
          ];

          List<pw.Widget> linhasMeses = [];
          for (int i = 0; i < 12; i += 2) {
            linhasMeses.addRow([
              _construirMiniCalendarioMes(ano, i + 1, nomesMeses[i], diasFeriasSet, contagemPorMes[i + 1] ?? 0),
              _construirMiniCalendarioMes(ano, i + 2, nomesMeses[i + 1], diasFeriasSet, contagemPorMes[i + 2] ?? 0),
            ]);
            linhasMeses.add(pw.SizedBox(height: 8));
          }

          widgets.add(pw.Column(children: linhasMeses));
          widgets.add(pw.Spacer());
          widgets.add(_construirRodapePdf());

          return widgets;
        },
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/Mapa_Ferias_${ano}_${nomeTrabalhador.replaceAll(' ', '_')}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  // ---------------------------------------------------------------------------
  // 5. GERAR PDF CALENDÁRIO CONSOLIDADO ANUAL (ICONES + HORAS EXTRAS/CORTADAS)
  // ---------------------------------------------------------------------------
  static Future<File> gerarPDFCalendarioConsolidado({
    required Map<String, dynamic> perfil,
    required List<Map<String, dynamic>> registosAno,
    required int ano,
  }) async {
    final pdf = pw.Document(compress: true);

    pw.MemoryImage? logoImage;
    try {
      final logoBytes = await rootBundle.load('assets/logo_rb.png');
      logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
    } catch (_) {}

    String nomeTrabalhador = perfil['nomeTrabalhador']?.isNotEmpty == true ? perfil['nomeTrabalhador'] : 'Rui Barata';
    String nomeEmpresa = perfil['nomeEmpresa']?.isNotEmpty == true ? perfil['nomeEmpresa'] : 'Empresa';

    Map<String, Map<String, dynamic>> mapaRegistos = {};
    for (var r in registosAno) {
      if (r['data'] != null) {
        mapaRegistos[r['data'].toString()] = r;
      }
    }

    final nomesMeses = [
      'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
    ];

    int totalFeriasAno = 0;
    int totalBaixasAno = 0;
    int totalFaltasAno = 0;
    double totalExtrasAno = 0.0;
    double totalCortadasAno = 0.0;

    for (var r in registosAno) {
      String tipo = r['tipoDia'] ?? '';
      double hContratadas = (r['horasContratadas'] as num?)?.toDouble() ?? 8.0;
      double hEfetivas = (r['horasEfetivas'] as num?)?.toDouble() ?? 0.0;
      double diff = hEfetivas - hContratadas;

      if (tipo == 'Férias') totalFeriasAno++;
      if (tipo == 'Baixa') totalBaixasAno++;
      if (tipo == 'Falta') totalFaltasAno++;

      if (tipo == 'Trabalho') {
        if (diff > 0.01) totalExtrasAno += diff;
        if (diff < -0.01) totalCortadasAno += diff.abs();
      } else if (tipo == 'Folga Trabalhada') {
        totalExtrasAno += hEfetivas;
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (context) {
          List<pw.Widget> widgets = [
            _construirCabecalhoPdf(
              logo: logoImage,
              titulo: 'CALENDÁRIO CONSOLIDADO ANUAL DE REGISTOS',
              subtitulo: 'Resumo com Identificação de Ocorrências e Horas (Ano $ano)',
              trabalhador: nomeTrabalhador,
              empresa: nomeEmpresa,
            ),
            pw.SizedBox(height: 10),
            pw.Container(
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _itemLegendaResumo('Férias', '$totalFeriasAno d', const PdfColor.fromInt(0xFF0288D1)),
                  _itemLegendaResumo('Baixas', '$totalBaixasAno d', const PdfColor.fromInt(0xFFC62828)),
                  _itemLegendaResumo('Faltas', '$totalFaltasAno d', const PdfColor.fromInt(0xFFE65100)),
                  _itemLegendaResumo('H. Extras', _formatarHorasPdf(totalExtrasAno), const PdfColor.fromInt(0xFF2E7D32)),
                  _itemLegendaResumo('H. Cortadas', _formatarHorasPdf(-totalCortadasAno, incluirSinal: false), const PdfColor.fromInt(0xFFB71C1C)),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
          ];

          List<pw.Widget> linhasMeses = [];
          for (int i = 0; i < 12; i += 2) {
            linhasMeses.addRow([
              _construirMiniCalendarioConsolidado(ano, i + 1, nomesMeses[i], mapaRegistos),
              _construirMiniCalendarioConsolidado(ano, i + 2, nomesMeses[i + 1], mapaRegistos),
            ]);
            linhasMeses.add(pw.SizedBox(height: 8));
          }

          widgets.add(pw.Column(children: linhasMeses));
          widgets.add(pw.Spacer());
          widgets.add(_construirRodapePdf());

          return widgets;
        },
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/Calendario_Consolidado_${ano}_${nomeTrabalhador.replaceAll(' ', '_')}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  // ---------------------------------------------------------------------------
  // MÉTODOS AUXILIARES DE CALENDÁRIOS E FORMATAÇÃO
  // ---------------------------------------------------------------------------
  static pw.Widget _itemLegendaResumo(String label, String valor, PdfColor cor) {
    return pw.Column(
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
        pw.SizedBox(height: 1),
        pw.Text(valor, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: cor)),
      ],
    );
  }

  static pw.Widget _construirMiniCalendarioMes(int ano, int mes, String nomeMes, Set<String> diasFeriasSet, int totalMes) {
    final primeiroDia = DateTime(ano, mes, 1);
    final ultimoDia = DateTime(ano, mes + 1, 0);
    int diasNoMes = ultimoDia.day;
    int diaSemanaInicio = primeiroDia.weekday - 1;

    List<pw.Widget> cabecalhos = ['S', 'T', 'Q', 'Q', 'S', 'S', 'D']
        .map((d) => pw.Center(child: pw.Text(d, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 6.5, color: PdfColors.grey700))))
        .toList();

    List<pw.Widget> celulas = [...cabecalhos];

    for (int i = 0; i < diaSemanaInicio; i++) {
      celulas.add(pw.SizedBox());
    }

    for (int dia = 1; dia <= diasNoMes; dia++) {
      String dataStr = "$ano-${mes.toString().padLeft(2, '0')}-${dia.toString().padLeft(2, '0')}";
      bool eFerias = diasFeriasSet.contains(dataStr);

      celulas.add(
        pw.Container(
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(
            color: eFerias ? const PdfColor.fromInt(0xFF0288D1) : PdfColors.white,
            borderRadius: pw.BorderRadius.circular(2),
            border: pw.Border.all(color: eFerias ? const PdfColor.fromInt(0xFF01579B) : PdfColors.grey300, width: 0.5),
          ),
          child: pw.Text(
            '$dia',
            style: pw.TextStyle(
              fontSize: 6.5,
              fontWeight: eFerias ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: eFerias ? PdfColors.white : PdfColors.black,
            ),
          ),
        ),
      );
    }

    return pw.Expanded(
      child: pw.Container(
        margin: const pw.EdgeInsets.symmetric(horizontal: 4),
        padding: const pw.EdgeInsets.all(5),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
          borderRadius: pw.BorderRadius.circular(4),
          color: PdfColors.grey50,
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(nomeMes, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5, color: const PdfColor.fromInt(0xFF1A237E))),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: pw.BoxDecoration(
                    color: totalMes > 0 ? const PdfColor.fromInt(0xFFE1F5FE) : PdfColors.grey200,
                    borderRadius: pw.BorderRadius.circular(3),
                  ),
                  child: pw.Text('Férias: $totalMes d', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: totalMes > 0 ? const PdfColor.fromInt(0xFF0288D1) : PdfColors.grey700)),
                ),
              ],
            ),
            pw.SizedBox(height: 3),
            pw.GridView(
              crossAxisCount: 7,
              childAspectRatio: 1.2,
              crossAxisSpacing: 1.5,
              mainAxisSpacing: 1.5,
              children: celulas,
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _construirMiniCalendarioConsolidado(int ano, int mes, String nomeMes, Map<String, Map<String, dynamic>> mapaRegistos) {
    final primeiroDia = DateTime(ano, mes, 1);
    final ultimoDia = DateTime(ano, mes + 1, 0);
    int diasNoMes = ultimoDia.day;
    int diaSemanaInicio = primeiroDia.weekday - 1;

    List<pw.Widget> cabecalhos = ['S', 'T', 'Q', 'Q', 'S', 'S', 'D']
        .map((d) => pw.Center(child: pw.Text(d, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 6.5, color: PdfColors.grey700))))
        .toList();

    List<pw.Widget> celulas = [...cabecalhos];

    for (int i = 0; i < diaSemanaInicio; i++) {
      celulas.add(pw.SizedBox());
    }

    for (int dia = 1; dia <= diasNoMes; dia++) {
      String dataStr = "$ano-${mes.toString().padLeft(2, '0')}-${dia.toString().padLeft(2, '0')}";
      final reg = mapaRegistos[dataStr];

      String tipo = reg?['tipoDia'] ?? '';
      double hContratadas = (reg?['horasContratadas'] as num?)?.toDouble() ?? 8.0;
      double hEfetivas = (reg?['horasEfetivas'] as num?)?.toDouble() ?? 0.0;
      double diff = hEfetivas - hContratadas;

      PdfColor corFundo = PdfColors.white;
      PdfColor corBorda = PdfColors.grey300;
      String etiqueta = '';
      PdfColor corTextoEtiqueta = PdfColors.black;

      if (tipo == 'Férias') {
        corFundo = const PdfColor.fromInt(0xFFE1F5FE);
        corBorda = const PdfColor.fromInt(0xFF0288D1);
        etiqueta = 'F';
        corTextoEtiqueta = const PdfColor.fromInt(0xFF0288D1);
      } else if (tipo == 'Baixa') {
        corFundo = const PdfColor.fromInt(0xFFFFEBEE);
        corBorda = const PdfColor.fromInt(0xFFC62828);
        etiqueta = 'B';
        corTextoEtiqueta = const PdfColor.fromInt(0xFFC62828);
      } else if (tipo == 'Falta') {
        corFundo = const PdfColor.fromInt(0xFFFFF3E0);
        corBorda = const PdfColor.fromInt(0xFFE65100);
        etiqueta = 'X';
        corTextoEtiqueta = const PdfColor.fromInt(0xFFE65100);
      } else if (tipo == 'Folga') {
        corFundo = const PdfColor.fromInt(0xFFF3E5F5);
        corBorda = const PdfColor.fromInt(0xFF7B1FA2);
        etiqueta = 'L';
        corTextoEtiqueta = const PdfColor.fromInt(0xFF7B1FA2);
      } else if (tipo == 'Trabalho') {
        if (diff > 0.01) {
          corFundo = const PdfColor.fromInt(0xFFE8F5E9);
          corBorda = const PdfColor.fromInt(0xFF2E7D32);
          etiqueta = _formatarHorasPdf(diff);
          corTextoEtiqueta = const PdfColor.fromInt(0xFF2E7D32);
        } else if (diff < -0.01) {
          corFundo = const PdfColor.fromInt(0xFFFFCDD2);
          corBorda = const PdfColor.fromInt(0xFFB71C1C);
          etiqueta = _formatarHorasPdf(diff, incluirSinal: false);
          corTextoEtiqueta = const PdfColor.fromInt(0xFFB71C1C);
        }
      } else if (tipo == 'Folga Trabalhada') {
        corFundo = const PdfColor.fromInt(0xFFE0F2F1);
        corBorda = const PdfColor.fromInt(0xFF00796B);
        etiqueta = _formatarHorasPdf(hEfetivas);
        corTextoEtiqueta = const PdfColor.fromInt(0xFF00796B);
      }

      celulas.add(
        pw.Container(
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(
            color: corFundo,
            borderRadius: pw.BorderRadius.circular(2),
            border: pw.Border.all(color: corBorda, width: 0.6),
          ),
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text('$dia', style: pw.TextStyle(fontSize: 5.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
              pw.Text(etiqueta, style: pw.TextStyle(fontSize: 5.0, fontWeight: pw.FontWeight.bold, color: corTextoEtiqueta)),
            ],
          ),
        ),
      );
    }

    return pw.Expanded(
      child: pw.Container(
        margin: const pw.EdgeInsets.symmetric(horizontal: 4),
        padding: const pw.EdgeInsets.all(5),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
          borderRadius: pw.BorderRadius.circular(4),
          color: PdfColors.grey50,
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(nomeMes, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5, color: const PdfColor.fromInt(0xFF1A237E))),
            pw.SizedBox(height: 3),
            pw.GridView(
              crossAxisCount: 7,
              childAspectRatio: 1.0,
              crossAxisSpacing: 1.5,
              mainAxisSpacing: 1.5,
              children: celulas,
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _construirCabecalhoPdf({
    required pw.MemoryImage? logo,
    required String titulo,
    required String subtitulo,
    required String trabalhador,
    required String empresa,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(titulo, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF1A237E))),
            pw.SizedBox(height: 2),
            pw.Text(subtitulo, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
            pw.SizedBox(height: 6),
            pw.Text('Trabalhador: $trabalhador  |  Empresa: $empresa', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          ],
        ),
        if (logo != null)
          pw.Container(
            width: 40,
            height: 40,
            child: pw.Image(logo),
          ),
      ],
    );
  }

  static pw.Widget _construirCaixaResumoPdf(String titulo, String valor, PdfColor cor) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        border: pw.Border.all(color: cor, width: 1),
      ),
      child: pw.Column(
        children: [
          pw.Text(titulo, style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800)),
          pw.SizedBox(height: 2),
          pw.Text(valor, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: cor)),
        ],
      ),
    );
  }

  static pw.Widget _linhaValorExtrato(String label, String valor, {PdfColor corValor = PdfColors.black, bool destaque = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: destaque ? 10 : 8.5, fontWeight: destaque ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(valor, style: pw.TextStyle(fontSize: destaque ? 11 : 9, fontWeight: pw.FontWeight.bold, color: corValor)),
        ],
      ),
    );
  }

  static pw.Widget _construirRodapePdf() {
    final dataHoje = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    return pw.Column(
      children: [
        pw.Divider(color: PdfColors.grey400),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Gestão de Horários - Desenvolvido por Rui Barata', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            pw.Text('Emitido em: $dataHoje', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          ],
        ),
      ],
    );
  }

  static void mostrarOpcoesExportacao({
    required material.BuildContext context,
    required String tipo,
    required File ficheiro,
    required Function(String) onFeedback,
  }) {
    material.showModalBottomSheet(
      context: context,
      shape: const material.RoundedRectangleBorder(
        borderRadius: material.BorderRadius.vertical(top: material.Radius.circular(20)),
      ),
      builder: (bottomSheetCtx) {
        return material.SafeArea(
          child: material.Padding(
            padding: const material.EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
            child: material.Column(
              mainAxisSize: material.MainAxisSize.min,
              children: [
                material.Container(
                  width: 40,
                  height: 4,
                  margin: const material.EdgeInsets.only(bottom: 12),
                  decoration: material.BoxDecoration(
                    color: material.Colors.grey.shade300,
                    borderRadius: material.BorderRadius.circular(2),
                  ),
                ),
                material.Text(
                  tipo,
                  style: const material.TextStyle(fontWeight: material.FontWeight.bold, fontSize: 16, color: material.Color(0xFF1A237E)),
                  textAlign: material.TextAlign.center,
                ),
                const material.SizedBox(height: 4),
                material.Text(
                  'Escolha a ação pretendida para o relatório gerado:',
                  style: material.TextStyle(fontSize: 12, color: material.Colors.grey.shade600),
                ),
                const material.SizedBox(height: 12),
                const material.Divider(),
                material.ListTile(
                  leading: const material.CircleAvatar(
                    backgroundColor: material.Color(0xFFE8EAF6),
                    child: material.Icon(material.Icons.visibility, color: material.Color(0xFF1A237E)),
                  ),
                  title: const material.Text('Ver', style: material.TextStyle(fontWeight: material.FontWeight.bold)),
                  subtitle: const material.Text('Abrir o relatório num leitor de PDF do telemóvel'),
                  onTap: () async {
                    material.Navigator.pop(bottomSheetCtx);
                    try {
                      final resultado = await OpenFilex.open(ficheiro.path);
                      if (resultado.type != ResultType.done) {
                        onFeedback('Aviso ao abrir: ${resultado.message}');
                      }
                    } catch (e) {
                      onFeedback('Não foi possível abrir o PDF: $e');
                    }
                  },
                ),
                material.ListTile(
                  leading: const material.CircleAvatar(
                    backgroundColor: material.Color(0xFFE8F5E9),
                    child: material.Icon(material.Icons.share, color: material.Color(0xFF2E7D32)),
                  ),
                  title: const material.Text('Partilhar', style: material.TextStyle(fontWeight: material.FontWeight.bold)),
                  subtitle: const material.Text('Enviar por WhatsApp, Email ou outras aplicações'),
                  onTap: () async {
                    material.Navigator.pop(bottomSheetCtx);
                    try {
                      final xFile = XFile(ficheiro.path);
                      await Share.shareXFiles([xFile], text: 'Relatório: $tipo');
                    } catch (e) {
                      onFeedback('Erro ao partilhar relatório: $e');
                    }
                  },
                ),
                material.ListTile(
                  leading: const material.CircleAvatar(
                    backgroundColor: material.Color(0xFFFFF3E0),
                    child: material.Icon(material.Icons.download_rounded, color: material.Color(0xFFE65100)),
                  ),
                  title: const material.Text('Guardar', style: material.TextStyle(fontWeight: material.FontWeight.bold)),
                  subtitle: const material.Text('Guardar cópia na pasta de Descargas/Downloads'),
                  onTap: () async {
                    material.Navigator.pop(bottomSheetCtx);
                    try {
                      Directory? downloadDir;
                      if (Platform.isAndroid) {
                        downloadDir = Directory('/storage/emulated/0/Download');
                        if (!await downloadDir.exists()) {
                          downloadDir = await getExternalStorageDirectory();
                        }
                      } else {
                        downloadDir = await getApplicationDocumentsDirectory();
                      }

                      if (downloadDir != null) {
                        String nomeFicheiro = ficheiro.path.split(Platform.pathSeparator).last;
                        final destino = File('${downloadDir.path}/$nomeFicheiro');
                        await ficheiro.copy(destino.path);
                        onFeedback('Guardado com sucesso na pasta Download.');
                      } else {
                        onFeedback('Não foi possível aceder à pasta de destino.');
                      }
                    } catch (e) {
                      onFeedback('Erro ao guardar: $e');
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

extension on List<pw.Widget> {
  void addRow(List<pw.Widget> widgets) {
    add(pw.Row(children: widgets));
  }
}