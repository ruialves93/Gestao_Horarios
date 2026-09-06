import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/database_helper.dart';
import '../services/update_service.dart';
import '../helpers/export_helper.dart';
import 'day_modal.dart';
import 'settings_modal.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  DateTime _mesAtual = DateTime(DateTime.now().year, DateTime.now().month, 1);
  Map<String, dynamic> _perfil = {};
  Map<String, Map<String, dynamic>> _registosDoMes = {};
  Map<String, double> _totais = {'credito': 0.0, 'debito': 0.0, 'ferias': 0.0, 'folgas': 0.0};
  String _mensagemFeedback = '';

  final List<String> _nomesMeses = [
    'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
    'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
  ];

  @override
  void initState() {
    super.initState();
    _recarregarTudo();

    // Verificação obrigatória automática no arranque
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.verificarEForcarAtualizacao(context);
    });
  }

  String _formatarData(DateTime data) {
    return "${data.year}-${data.month.toString().padLeft(2, '0')}-${data.day.toString().padLeft(2, '0')}";
  }

  Future<void> _recarregarTudo() async {
    final perfil = await DatabaseHelper.instance.getPerfil();
    final totais = await DatabaseHelper.instance.getTotaisGerais();
    final registos = await DatabaseHelper.instance.getRegistosMes(_mesAtual.year, _mesAtual.month);
    if (mounted) {
      setState(() {
        _perfil = perfil;
        _totais = totais;
        _registosDoMes = registos;
      });
    }
  }

  void _mudarMes(int offset) {
    setState(() {
      _mesAtual = DateTime(_mesAtual.year, _mesAtual.month + offset, 1);
    });
    _recarregarTudo();
  }

  Future<void> _processarRelatorioBancoHoras() async {
    try {
      final registosMesList = await DatabaseHelper.instance.getRegistosMes(_mesAtual.year, _mesAtual.month);
      final ficheiro = await ExportHelper.gerarPDF(
        perfil: _perfil,
        registosMes: registosMesList.values.toList(),
        ano: _mesAtual.year,
        mes: _mesAtual.month,
      );

      if (!mounted) return;
      ExportHelper.mostrarOpcoesExportacao(
        context: context,
        tipo: 'Banco de Horas Mensal',
        ficheiro: ficheiro,
        onFeedback: (msg) => setState(() => _mensagemFeedback = msg),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _mensagemFeedback = 'Erro ao gerar PDF: $e');
      }
    }
  }

  Future<void> _processarRelatorioValoresDetalhado() async {
    try {
      final registosMesList = await DatabaseHelper.instance.getRegistosMes(_mesAtual.year, _mesAtual.month);
      final ficheiro = await ExportHelper.gerarPDFValoresReceberDetalhado(
        perfil: _perfil,
        registosMes: registosMesList.values.toList(),
        ano: _mesAtual.year,
        mes: _mesAtual.month,
      );

      if (!mounted) return;
      ExportHelper.mostrarOpcoesExportacao(
        context: context,
        tipo: 'Extrato Salarial Diário',
        ficheiro: ficheiro,
        onFeedback: (msg) => setState(() => _mensagemFeedback = msg),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _mensagemFeedback = 'Erro ao gerar Extrato Salarial: $e');
      }
    }
  }

  Future<void> _processarMapaFerias() async {
    try {
      final registosAno = await DatabaseHelper.instance.getRegistosAno(_mesAtual.year);
      final ficheiro = await ExportHelper.gerarPDFMapaFerias(
        perfil: _perfil,
        registosAno: registosAno,
        ano: _mesAtual.year,
      );

      if (!mounted) return;
      ExportHelper.mostrarOpcoesExportacao(
        context: context,
        tipo: 'Mapa de Férias Anual',
        ficheiro: ficheiro,
        onFeedback: (msg) => setState(() => _mensagemFeedback = msg),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _mensagemFeedback = 'Erro ao gerar Mapa de Férias: $e');
      }
    }
  }

  Future<void> _abrirCodigoDoTrabalho() async {
    final Uri url = Uri.parse('https://diariodarepublica.pt/dr/legislacao-consolidada/lei/2009-34546475-914159294');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      setState(() => _mensagemFeedback = 'Não foi possível abrir o link do Código do Trabalho.');
    }
  }

  @override
  Widget build(BuildContext context) {
    double saldoBancoTotal = (_totais['credito'] ?? 0.0) - (_totais['debito'] ?? 0.0);
    final totalDiasMes = DateUtils.getDaysInMonth(_mesAtual.year, _mesAtual.month);
    final primeiroDiaMes = DateTime(_mesAtual.year, _mesAtual.month, 1);
    int primeiroDiaSemana = primeiroDiaMes.weekday - 1;

    // --- CÁLCULOS FINANCEIROS MENSAIS ---
    double salarioBase = (_perfil['salarioBase'] as num?)?.toDouble() ?? 1000.0;
    double valorHoraBase = salarioBase / 174.0;
    double totalHorasExtraPagasMes = 0.0;
    double totalDescontosSalarioMes = 0.0;

    for (var reg in _registosDoMes.values) {
      double extraPaga = (reg['horasExtraPagas'] as num?)?.toDouble() ?? 0.0;
      double descSalario = (reg['horasDescontoSalario'] as num?)?.toDouble() ?? 0.0;
      totalHorasExtraPagasMes += extraPaga;
      totalDescontosSalarioMes += descSalario;
    }

    double valorTotalExtraPagas = totalHorasExtraPagasMes * valorHoraBase * 1.25;
    double valorTotalDescontos = totalDescontosSalarioMes * valorHoraBase;
    double totalAReceber = salarioBase + valorTotalExtraPagas - valorTotalDescontos;

    final String nomeTrabalhador = _perfil['nomeTrabalhador']?.toString().trim() ?? '';
    final String nomeEmpresa = _perfil['nomeEmpresa']?.toString().trim() ?? '';
    final String subtituloPerfil = (nomeTrabalhador.isNotEmpty || nomeEmpresa.isNotEmpty)
        ? '$nomeTrabalhador${nomeTrabalhador.isNotEmpty && nomeEmpresa.isNotEmpty ? ' | ' : ''}$nomeEmpresa'
        : 'Configurar dados';

    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              accountName: const Text('Gestão de Horários', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              accountEmail: const Text('Desenvolvimento por Rui Barata © 2026', style: TextStyle(color: Colors.white70)),
              currentAccountPicture: ClipOval(
                child: Image.asset(
                  'assets/logo_rb.png',
                  fit: BoxFit.cover,
                  errorBuilder: (c, o, s) => const CircleAvatar(child: Text('RB')),
                ),
              ),
              decoration: const BoxDecoration(color: Color(0xFF1A237E)),
            ),
            ListTile(
              leading: const Icon(Icons.person, color: Color(0xFF1A237E)),
              title: const Text('Perfil e Empresa'),
              subtitle: Text(subtituloPerfil),
              onTap: () {
                Navigator.pop(context);
                SettingsModal.abrirModalPerfil(
                  context: context,
                  perfil: _perfil,
                  onAtualizado: _recarregarTudo,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock, color: Colors.deepPurple),
              title: const Text('Segurança (PIN / Biometria)'),
              subtitle: const Text('Configurar bloqueio da aplicação'),
              onTap: () {
                Navigator.pop(context);
                SettingsModal.abrirModalSeguranca(
                  context: context,
                  perfil: _perfil,
                  onFeedback: (msg) => setState(() => _mensagemFeedback = msg),
                  onAtualizado: _recarregarTudo,
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: const Text('PDF Banco de Horas'),
              subtitle: const Text('Ver, exportar ou partilhar horas'),
              onTap: () {
                Navigator.pop(context);
                _processarRelatorioBancoHoras();
              },
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long, color: Colors.green),
              title: const Text('PDF Valores Detalhados'),
              subtitle: const Text('Extrato salarial diário e base legal'),
              onTap: () {
                Navigator.pop(context);
                _processarRelatorioValoresDetalhado();
              },
            ),
            ListTile(
              leading: const Icon(Icons.date_range, color: Colors.amber),
              title: const Text('Mapa Férias Anual'),
              subtitle: const Text('Ver calendário com contagem mensal e anual'),
              onTap: () {
                Navigator.pop(context);
                _processarMapaFerias();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.gavel, color: Colors.indigo),
              title: const Text('Código do Trabalho - CT | DR'),
              subtitle: const Text('Aceder à legislação oficial'),
              onTap: () {
                Navigator.pop(context);
                _abrirCodigoDoTrabalho();
              },
            ),
            ListTile(
              leading: const Icon(Icons.system_update_alt, color: Colors.teal),
              title: const Text('Procurar Atualizações'),
              subtitle: const Text('Forçar verificação de nova versão no GitHub'),
              onTap: () {
                Navigator.pop(context);
                UpdateService.verificarEForcarAtualizacao(
                  context,
                  manual: true,
                  onFeedback: (msg) => setState(() => _mensagemFeedback = msg),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.backup, color: Colors.orange),
              title: const Text('Criar Backup BD'),
              subtitle: const Text('Escolher onde guardar o ficheiro'),
              onTap: () async {
                Navigator.pop(context);
                bool ok = await DatabaseHelper.instance.exportarEGuardarBaseDeDados();
                setState(() => _mensagemFeedback = ok ? 'Backup gerado com sucesso!' : 'Erro ao gerar backup.');
              },
            ),
            ListTile(
              leading: const Icon(Icons.restore, color: Colors.blue),
              title: const Text('Carregar Backup BD'),
              subtitle: const Text('Selecionar ficheiro no telemóvel'),
              onTap: () {
                Navigator.pop(context);
                SettingsModal.executarRestauro(
                  context: context,
                  onAtualizado: _recarregarTudo,
                  onFeedback: (msg) => setState(() => _mensagemFeedback = msg),
                );
              },
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Desenvolvimento por Rui Barata © 2026\nLegislação Laboral: Código do Trabalho',
                style: TextStyle(fontSize: 11, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Abrir Menu',
          padding: const EdgeInsets.all(6.0),
          icon: ClipOval(
            child: Image.asset(
              'assets/logo_rb.png',
              width: 38,
              height: 38,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.menu, color: Colors.white),
            ),
          ),
          onPressed: () {
            _scaffoldKey.currentState?.openDrawer();
          },
        ),
        title: const Text('Gestão de Horários', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Bloco 1: Resumo do Banco de Horas
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: Colors.indigo.shade50,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Saldo Global Banco:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        '${saldoBancoTotal >= 0 ? '+' : ''}${saldoBancoTotal.toStringAsFixed(2)} h',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: saldoBancoTotal >= 0 ? Colors.green.shade800 : Colors.red.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Text('Entradas: +${(_totais['credito'] ?? 0.0).toStringAsFixed(2)}h', style: const TextStyle(fontSize: 11, color: Colors.green)),
                      Text('Saídas: -${(_totais['debito'] ?? 0.0).toStringAsFixed(2)}h', style: const TextStyle(fontSize: 11, color: Colors.red)),
                      Text('Férias: ${(_totais['ferias'] ?? 0).toInt()} d', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      Text('Folgas: ${(_totais['folgas'] ?? 0).toInt()} d', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Bloco 2: Resumo Financeiro Mensal em EUR
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total a Receber:', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                      Text(
                        '${totalAReceber.toStringAsFixed(2)} EUR',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                      ),
                    ],
                  ),
                  const Divider(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Salário Base: ${salarioBase.toStringAsFixed(2)} EUR', style: const TextStyle(fontSize: 11)),
                      Text('Horas Extra Paga: +${valorTotalExtraPagas.toStringAsFixed(2)} EUR', style: const TextStyle(fontSize: 11, color: Colors.green)),
                      if (valorTotalDescontos > 0)
                        Text('Desc.: -${valorTotalDescontos.toStringAsFixed(2)} EUR', style: const TextStyle(fontSize: 11, color: Colors.red)),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Seletor de Mês
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _mudarMes(-1)),
                Text(
                  '${_nomesMeses[_mesAtual.month - 1]} ${_mesAtual.year}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
                ),
                IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _mudarMes(1)),
              ],
            ),
          ),

          // Cabeçalho dos Dias da Semana
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: const [
                Text('Seg', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                Text('Ter', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                Text('Qua', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                Text('Qui', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                Text('Sex', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                Text('Sáb', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                Text('Dom', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),

          // Calendário Mensal
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  childAspectRatio: 1.0,
                ),
                itemCount: primeiroDiaSemana + totalDiasMes,
                itemBuilder: (context, index) {
                  if (index < primeiroDiaSemana) {
                    return const SizedBox.shrink();
                  }

                  int diaNum = index - primeiroDiaSemana + 1;
                  DateTime dataDia = DateTime(_mesAtual.year, _mesAtual.month, diaNum);
                  String chaveData = _formatarData(dataDia);
                  final registo = _registosDoMes[chaveData];

                  Color corFundo = Colors.grey.shade100;
                  Color corTexto = Colors.black87;
                  String rotulo = '';

                  if (registo != null) {
                    final tipo = registo['tipoDia']?.toString();
                    if (tipo == 'Trabalho') {
                      corFundo = Colors.blue.shade50;
                      corTexto = const Color(0xFF1A237E);
                      rotulo = '${(registo['horasEfetivas'] as num?)?.toStringAsFixed(1) ?? ''}h';
                    } else if (tipo == 'Férias') {
                      corFundo = Colors.amber.shade100;
                      corTexto = Colors.brown;
                      rotulo = 'Férias';
                    } else if (tipo == 'Folga') {
                      corFundo = Colors.green.shade100;
                      corTexto = Colors.green.shade900;
                      rotulo = 'Folga';
                    }
                  }

                  bool isHoje = _formatarData(DateTime.now()) == chaveData;

                  return InkWell(
                    onTap: () => DayModal.abrirRegistoDia(
                      context: context,
                      dia: dataDia,
                      perfil: _perfil,
                      onAtualizado: _recarregarTudo,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: corFundo,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isHoje ? const Color(0xFF1A237E) : Colors.grey.shade300,
                          width: isHoje ? 2.0 : 1.0,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$diaNum',
                            style: TextStyle(
                              fontWeight: isHoje ? FontWeight.bold : FontWeight.w600,
                              fontSize: 13,
                              color: isHoje ? const Color(0xFF1A237E) : corTexto,
                            ),
                          ),
                          if (rotulo.isNotEmpty)
                            Text(
                              rotulo,
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: corTexto),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          if (_mensagemFeedback.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                _mensagemFeedback,
                style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}