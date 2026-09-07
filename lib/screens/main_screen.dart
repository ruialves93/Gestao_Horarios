import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/database_helper.dart';
import '../services/drive_service.dart';
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
  int _anoAtual = DateTime.now().year;
  int _mesAtual = DateTime.now().month;
  
  Map<String, dynamic> _perfil = {};
  Map<String, Map<String, dynamic>> _registosMes = {};
  Map<String, double> _totaisGerais = {};
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _inicializarApp();
  }

  Future<void> _inicializarApp() async {
    if (mounted) {
      await UpdateService.verificarEForcarAtualizacao(context);
    }
    await DriveService.sincronizarAoAbrir((msg) {});
    await _carregarDados();
  }

  Future<void> _carregarDados() async {
    setState(() => _carregando = true);
    final perfil = await DatabaseHelper.instance.getPerfil();
    final registos = await DatabaseHelper.instance.getRegistosMes(_anoAtual, _mesAtual);
    final totais = await DatabaseHelper.instance.getTotaisGerais();

    setState(() {
      _perfil = perfil;
      _registosMes = registos;
      _totaisGerais = totais;
      _carregando = false;
    });
  }

  void _mudarMes(int delta) {
    setState(() {
      _mesAtual += delta;
      if (_mesAtual > 12) {
        _mesAtual = 1;
        _anoAtual++;
      } else if (_mesAtual < 1) {
        _mesAtual = 12;
        _anoAtual--;
      }
    });
    _carregarDados();
  }

  Future<void> _abrirCodigoTrabalho() async {
    final Uri url = Uri.parse('https://diariodarepublica.pt/dr/legislacao-consolidada/-/decreto-lei/2009-72215041');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _mostrarDialogoGoogleDrive(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        bool autenticado = DriveService.estaAutenticado;
        String? email = DriveService.emailContaAtiva;

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Google Drive & Sincronização', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: autenticado ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: autenticado ? Colors.green.shade300 : Colors.red.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          autenticado ? Icons.cloud_done : Icons.cloud_off,
                          color: autenticado ? Colors.green.shade800 : Colors.red.shade800,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                autenticado ? 'Conta Google Ligada' : 'Sem Conta Ligada',
                                style: TextStyle(fontWeight: FontWeight.bold, color: autenticado ? Colors.green.shade900 : Colors.red.shade900),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                autenticado ? (email ?? 'Ativa') : 'Toque em Ligar para sincronizar dados',
                                style: const TextStyle(fontSize: 12, color: Colors.black87),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!autenticado)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A237E), foregroundColor: Colors.white),
                        icon: const Icon(Icons.login),
                        label: const Text('Ligar à Conta Google'),
                        onPressed: () async {
                          await DriveService.iniciarSessao((msg) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                          });
                          setStateDialog(() {});
                          _carregarDados();
                        },
                      ),
                    )
                  else ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
                        icon: const Icon(Icons.sync),
                        label: const Text('Forçar Sincronização Manual'),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await DriveService.fazerUploadBackup(onFeedback: (msg) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        icon: const Icon(Icons.logout),
                        label: const Text('Terminar Sessão Google'),
                        onPressed: () async {
                          await DriveService.terminarSessao();
                          setStateDialog(() {});
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sessão Google terminada.')));
                          }
                        },
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
              ],
            );
          },
        );
      },
    );
  }

  void _mostrarDialogoExportacaoPdf(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Exportar Relatórios PDF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1A237E))),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.assessment, color: Colors.indigo),
                title: const Text('Resumo Anual de Rendimentos'),
                subtitle: Text('Banco de horas e valores de $_anoAtual (Lei n.º 7/2009)'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final registosAnoLista = await DatabaseHelper.instance.getRegistosAno(_anoAtual);
                  final file = await ExportHelper.gerarPDFResumoAnual(
                    perfil: _perfil,
                    registosAno: registosAnoLista,
                    ano: _anoAtual,
                  );
                  if (context.mounted) {
                    ExportHelper.mostrarOpcoesExportacao(
                      context: context,
                      tipo: 'Resumo Anual ($_anoAtual)',
                      ficheiro: file,
                      onFeedback: (msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg))),
                    );
                  }
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.receipt_long, color: Color(0xFF1A237E)),
                title: const Text('Extrato Salarial Detalhado'),
                subtitle: const Text('Valores diários, extras e descontos do mês'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final registosLista = _registosMes.values.toList();
                  final file = await ExportHelper.gerarPDFValoresReceberDetalhado(
                    perfil: _perfil,
                    registosMes: registosLista,
                    ano: _anoAtual,
                    mes: _mesAtual,
                  );
                  if (context.mounted) {
                    ExportHelper.mostrarOpcoesExportacao(
                      context: context,
                      tipo: 'Extrato Salarial ($_mesAtual/$_anoAtual)',
                      ficheiro: file,
                      onFeedback: (msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg))),
                    );
                  }
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.schedule, color: Colors.green),
                title: const Text('Banco de Horas Mensal'),
                subtitle: const Text('Relatório de horas e saldos mensais'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final registosLista = _registosMes.values.toList();
                  final file = await ExportHelper.gerarPDF(
                    perfil: _perfil,
                    registosMes: registosLista,
                    ano: _anoAtual,
                    mes: _mesAtual,
                  );
                  if (context.mounted) {
                    ExportHelper.mostrarOpcoesExportacao(
                      context: context,
                      tipo: 'Banco de Horas ($_mesAtual/$_anoAtual)',
                      ficheiro: file,
                      onFeedback: (msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg))),
                    );
                  }
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.beach_access, color: Colors.amber),
                title: const Text('Mapa de Férias Anual'),
                subtitle: Text('Calendário detalhado de férias de $_anoAtual'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final registosAnoLista = await DatabaseHelper.instance.getRegistosAno(_anoAtual);
                  final file = await ExportHelper.gerarPDFMapaFerias(
                    perfil: _perfil,
                    registosAno: registosAnoLista,
                    ano: _anoAtual,
                  );
                  if (context.mounted) {
                    ExportHelper.mostrarOpcoesExportacao(
                      context: context,
                      tipo: 'Mapa de Férias ($_anoAtual)',
                      ficheiro: file,
                      onFeedback: (msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg))),
                    );
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<String> mesesNomes = [
      'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
    ];

    String nomeTrabalhador = _perfil['nomeTrabalhador']?.isNotEmpty == true ? _perfil['nomeTrabalhador'] : 'Rui Barata';
    String nomeEmpresa = _perfil['nomeEmpresa']?.isNotEmpty == true ? _perfil['nomeEmpresa'] : 'Gestão de Horários';

    // Cálculo unificado de horas extra (horas e valor monetário em €)
    double salarioBase = (_perfil['salarioBase'] as num?)?.toDouble() ?? 1000.0;
    double valorHoraBase = salarioBase / 174.0;

    double totalHorasExtraPagasMes = 0.0;
    double totalValorExtraMesEuros = 0.0;

    _registosMes.forEach((key, reg) {
      double extraPaga = (reg['horasExtraPagas'] as num?)?.toDouble() ?? 0.0;
      if (extraPaga > 0) {
        totalHorasExtraPagasMes += extraPaga;
        totalValorExtraMesEuros += extraPaga * valorHoraBase * 1.25;
      }
      String tipo = reg['tipoDia']?.toString() ?? '';
      if (tipo == 'Folga Trabalhada') {
        String acaoFolga = reg['acaoFolgaTrabalhada']?.toString() ?? '';
        if (acaoFolga == 'Pagar') {
          double hEfetivas = (reg['horasEfetivas'] as num?)?.toDouble() ?? 0.0;
          totalHorasExtraPagasMes += hEfetivas;
          totalValorExtraMesEuros += hEfetivas * valorHoraBase * 1.25;
        }
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(nomeEmpresa != 'Gestão de Horários' ? '$nomeEmpresa - Gestão' : 'Gestão de Horários'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        leading: Builder(
          builder: (context) => IconButton(
            icon: Padding(
              padding: const EdgeInsets.all(4.0),
              child: ClipOval(
                child: Image.asset(
                  'assets/logo_rb.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.person, color: Colors.white),
                ),
              ),
            ),
            onPressed: () => Scaffold.of(context).openDrawer(),
            tooltip: 'Menu',
          ),
        ),
      ),
      
      drawer: Drawer(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(color: Color(0xFF1A237E)),
              currentAccountPicture: ClipOval(
                child: Image.asset(
                  'assets/logo_rb.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.person, size: 40, color: Colors.white),
                ),
              ),
              accountName: Text(
                nomeTrabalhador,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              accountEmail: Text(nomeEmpresa),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline, color: Color(0xFF1A237E)),
              title: const Text('Configurar Perfil'),
              onTap: () {
                Navigator.pop(context);
                SettingsModal.abrirModalPerfil(
                  context: context,
                  perfil: _perfil,
                  onAtualizado: _carregarDados,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_sync, color: Colors.blue),
              title: const Text('Google Drive & Sincronização'),
              subtitle: Text(DriveService.estaAutenticado ? (DriveService.emailContaAtiva ?? 'Ligado') : 'Ver conta / Forçar backup'),
              onTap: () {
                Navigator.pop(context);
                _mostrarDialogoGoogleDrive(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: const Text('Relatórios e Mapas PDF'),
              subtitle: const Text('Resumo Anual, Extratos e Banco de Horas'),
              onTap: () {
                Navigator.pop(context);
                _mostrarDialogoExportacaoPdf(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.system_update_rounded, color: Colors.green),
              title: const Text('Atualizar Aplicação'),
              subtitle: const Text('Verificar nova versão no GitHub'),
              onTap: () async {
                Navigator.pop(context);
                await UpdateService.verificarEForcarAtualizacao(
                  context,
                  manual: true,
                  onFeedback: (msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg))),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline, color: Color(0xFF1A237E)),
              title: const Text('Segurança e PIN'),
              onTap: () {
                Navigator.pop(context);
                SettingsModal.abrirModalSeguranca(
                  context: context,
                  perfil: _perfil,
                  onFeedback: (msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg))),
                  onAtualizado: _carregarDados,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file, color: Colors.green),
              title: const Text('Exportar Base de Dados (Backup)'),
              onTap: () async {
                Navigator.pop(context);
                bool ok = await DatabaseHelper.instance.exportarEGuardarBaseDeDados();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ok ? 'Backup exportado com sucesso!' : 'Erro ou cancelado na exportação.'),
                  ));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.download, color: Colors.orange),
              title: const Text('Restaurar Base de Dados'),
              onTap: () async {
                Navigator.pop(context);
                await SettingsModal.executarRestauro(
                  context: context,
                  onAtualizado: _carregarDados,
                  onFeedback: (msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg))),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.menu_book, color: Colors.indigo),
              title: const Text('Código do Trabalho'),
              subtitle: const Text('Consulta legislativa oficial'),
              onTap: () {
                Navigator.pop(context);
                _abrirCodigoTrabalho();
              },
            ),
            const Spacer(),
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Desenvolvido por Rui Barata\nCopyright © 2026',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),

      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  color: Colors.indigo.shade50,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left, color: Color(0xFF1A237E)),
                        onPressed: () => _mudarMes(-1),
                      ),
                      Text(
                        '${mesesNomes[_mesAtual - 1]} $_anoAtual',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right, color: Color(0xFF1A237E)),
                        onPressed: () => _mudarMes(1),
                      ),
                    ],
                  ),
                ),
                
                Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildResumoItem('Banco Horas', '${(_totaisGerais['credito'] ?? 0.0).toStringAsFixed(1)}h', Colors.indigo.shade900),
                              _buildResumoItem('Férias', '${(_totaisGerais['ferias'] ?? 0.0).toInt()}d', Colors.blue),
                              _buildResumoItem('Folgas', '${(_totaisGerais['folgas'] ?? 0.0).toInt()}d', Colors.purple),
                            ],
                          ),
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildResumoItem('Salário Base', '${(_totaisGerais['salarioBase'] ?? 0.0).toStringAsFixed(2)}€', Colors.black87),
                              _buildResumoItem('Horas Extra', '${totalHorasExtraPagasMes.toStringAsFixed(1)}h (${totalValorExtraMesEuros.toStringAsFixed(2)}€)', Colors.green.shade800),
                              _buildResumoItem('Subs. Alim.', '${(_totaisGerais['subsidioAlimentacao'] ?? 0.0).toStringAsFixed(2)}€', Colors.brown),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A237E),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('TOTAL ESTIMADO A RECEBER:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                Text(
                                  '${(_totaisGerais['totalAReceber'] ?? 0.0).toStringAsFixed(2)} €',
                                  style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: _construirCalendario(),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildResumoItem(String titulo, String valor, Color cor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(titulo, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(valor, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: cor)),
      ],
    );
  }

  Widget _construirCalendario() {
    final primeiroDiaDoMes = DateTime(_anoAtual, _mesAtual, 1);
    final ultimoDiaDoMes = DateTime(_anoAtual, _mesAtual + 1, 0);
    int diasNoMes = ultimoDiaDoMes.day;
    int diaSemanaInicio = primeiroDiaDoMes.weekday - 1;

    List<Widget> cabecalhos = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom']
        .map((d) => Center(child: Text(d, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))))
        .toList();

    List<Widget> celulas = [];
    
    for (int i = 0; i < diaSemanaInicio; i++) {
      celulas.add(Container());
    }

    for (int dia = 1; dia <= diasNoMes; dia++) {
      final dataAtual = DateTime(_anoAtual, _mesAtual, dia);
      String chaveData = "$_anoAtual-${_mesAtual.toString().padLeft(2, '0')}-${dia.toString().padLeft(2, '0')}";
      final reg = _registosMes[chaveData];

      String tipoDia = reg?['tipoDia'] ?? 'Trabalho';
      double hEfetivas = (reg?['horasEfetivas'] as num?)?.toDouble() ?? 0.0;
      double hContratadas = (reg?['horasContratadas'] as num?)?.toDouble() ?? 8.0;
      double diff = hEfetivas - hContratadas;

      Color corFundo = Colors.white;
      Color corBorda = Colors.grey.shade300;
      IconData? iconeSituacao;
      Color corIcone = Colors.black;

      if (tipoDia == 'Férias') {
        corFundo = Colors.blue.shade50;
        corBorda = Colors.blue.shade300;
        iconeSituacao = Icons.beach_access;
        corIcone = Colors.blue.shade800;
      } else if (tipoDia == 'Folga') {
        corFundo = Colors.purple.shade50;
        corBorda = Colors.purple.shade300;
        iconeSituacao = Icons.weekend;
        corIcone = Colors.purple.shade800;
      } else if (tipoDia == 'Folga Trabalhada') {
        corFundo = Colors.teal.shade50;
        corBorda = Colors.teal.shade300;
        iconeSituacao = Icons.work_history;
        corIcone = Colors.teal.shade800;
      } else if (tipoDia == 'Falta') {
        corFundo = Colors.orange.shade50;
        corBorda = Colors.orange.shade300;
        iconeSituacao = Icons.warning_amber;
        corIcone = Colors.orange.shade800;
      } else if (tipoDia == 'Baixa') {
        corFundo = Colors.red.shade50;
        corBorda = Colors.red.shade300;
        iconeSituacao = Icons.local_hospital;
        corIcone = Colors.red.shade800;
      } else if (reg != null) {
        corFundo = Colors.green.shade50;
        corBorda = Colors.green.shade300;
      }

      celulas.add(
        GestureDetector(
          onTap: () {
            DayModal.abrirRegistoDia(
              context: context,
              dia: dataAtual,
              perfil: _perfil,
              onAtualizado: _carregarDados,
            );
          },
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: corFundo,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: corBorda),
            ),
            padding: const EdgeInsets.all(4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$dia', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    if (iconeSituacao != null)
                      Icon(iconeSituacao, size: 14, color: corIcone),
                  ],
                ),
                if ((tipoDia == 'Trabalho' || tipoDia == 'Folga Trabalhada') && reg != null && diff.abs() > 0.01)
                  Center(
                    child: Text(
                      diff > 0 ? '+${diff.toStringAsFixed(1)}h' : '${diff.toStringAsFixed(1)}h',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: diff > 0 ? Colors.green.shade800 : Colors.orange.shade900,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: cabecalhos,
        ),
        const SizedBox(height: 4),
        Expanded(
          child: GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            children: celulas,
          ),
        ),
      ],
    );
  }
}