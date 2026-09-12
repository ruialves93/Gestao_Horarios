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
    await DatabaseHelper.instance.getTotaisGerais();

    if (!mounted) return;
    setState(() {
      _perfil = perfil;
      _registosMes = registos;
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
                          final messenger = ScaffoldMessenger.of(context);
                          await DriveService.iniciarSessao((msg) {
                            messenger.showSnackBar(SnackBar(content: Text(msg)));
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
                          final messenger = ScaffoldMessenger.of(context);
                          Navigator.pop(ctx);
                          await DriveService.fazerUploadBackup(onFeedback: (msg) {
                            messenger.showSnackBar(SnackBar(content: Text(msg)));
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
                          final messenger = ScaffoldMessenger.of(context);
                          await DriveService.terminarSessao();
                          setStateDialog(() {});
                          messenger.showSnackBar(const SnackBar(content: Text('Sessão Google terminada.')));
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
          titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          title: const Text(
            'Exportar Relatórios PDF',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF1A237E)),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    leading: const Icon(Icons.assessment, color: Colors.indigo),
                    title: const Text('Resumo Anual de Rendimentos', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('Banco de horas e valores de $_anoAtual (Lei n.º 7/2009)'),
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
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
                          onFeedback: (msg) => messenger.showSnackBar(SnackBar(content: Text(msg))),
                        );
                      }
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    leading: const Icon(Icons.receipt_long, color: Color(0xFF1A237E)),
                    title: const Text('Extrato Salarial Detalhado', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Valores diários, extras e descontos do mês'),
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
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
                          onFeedback: (msg) => messenger.showSnackBar(SnackBar(content: Text(msg))),
                        );
                      }
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    leading: const Icon(Icons.schedule, color: Colors.green),
                    title: const Text('Banco de Horas Mensal', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Relatório de horas e saldos mensais'),
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
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
                          onFeedback: (msg) => messenger.showSnackBar(SnackBar(content: Text(msg))),
                        );
                      }
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    leading: const Icon(Icons.beach_access, color: Colors.amber),
                    title: const Text('Mapa de Férias Anual', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('Calendário detalhado de férias de $_anoAtual'),
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
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
                          onFeedback: (msg) => messenger.showSnackBar(SnackBar(content: Text(msg))),
                        );
                      }
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    leading: const Icon(Icons.calendar_month, color: Colors.teal),
                    title: const Text('Calendário Consolidado Anual', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('Férias, baixas, faltas e horas de $_anoAtual'),
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      Navigator.pop(ctx);
                      final registosAnoLista = await DatabaseHelper.instance.getRegistosAno(_anoAtual);
                      final file = await ExportHelper.gerarPDFCalendarioConsolidado(
                        perfil: _perfil,
                        registosAno: registosAnoLista,
                        ano: _anoAtual,
                      );
                      if (context.mounted) {
                        ExportHelper.mostrarOpcoesExportacao(
                          context: context,
                          tipo: 'Calendário Consolidado ($_anoAtual)',
                          ficheiro: file,
                          onFeedback: (msg) => messenger.showSnackBar(SnackBar(content: Text(msg))),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
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

    double salarioBase = (_perfil['salarioBase'] as num?)?.toDouble() ?? 1000.0;
    double valorSubsidioDiario = (_perfil['valorSubsidioAlimentacao'] as num?)?.toDouble() ?? 6.0;
    double valorHoraBase = salarioBase / 174.0;

    double bancoHorasMesGanhas = 0.0;
    double bancoHorasMesDescontadas = 0.0;
    int diasFeriasMes = 0;
    int diasFolgasMes = 0;
    int diasFaltasMes = 0;
    int diasBaixasMes = 0;

    double totalValorExtraEuros = 0.0;
    double totalValorDescontosEuros = 0.0;
    double totalSubsidioEuros = 0.0;

    _registosMes.forEach((key, reg) {
      int incluiSub = (reg['incluiSubsidio'] as num?)?.toInt() ?? 0;
      if (incluiSub == 1) {
        totalSubsidioEuros += valorSubsidioDiario;
      }

      String tipo = reg['tipoDia']?.toString() ?? 'Trabalho';
      double hContratadas = (reg['horasContratadas'] as num?)?.toDouble() ?? 8.0;
      double hEfetivas = (reg['horasEfetivas'] as num?)?.toDouble() ?? 0.0;

      if (tipo == 'Férias') {
        diasFeriasMes++;
      } else if (tipo == 'Folga') {
        diasFolgasMes++;
      } else if (tipo == 'Falta') {
        diasFaltasMes++;
        String acaoFaltaTratamento = reg['acaoFaltaTratamento']?.toString() ?? 'Descontar no Salário';
        if (acaoFaltaTratamento == 'Descontar no Banco de Horas') {
          bancoHorasMesDescontadas += hContratadas;
        } else {
          totalValorDescontosEuros += hContratadas * valorHoraBase;
        }
      } else if (tipo == 'Baixa') {
        diasBaixasMes++;
        totalValorDescontosEuros += hContratadas * valorHoraBase;
      } else if (tipo == 'Trabalho') {
        double diff = hEfetivas - hContratadas;
        if (diff > 0.01) {
          String acaoExcesso = reg['acaoExcesso']?.toString() ?? 'Banco de Horas';
          if (acaoExcesso == 'Banco de Horas') {
            bancoHorasMesGanhas += diff;
          } else if (acaoExcesso == 'Pagar') {
            totalValorExtraEuros += diff * valorHoraBase * 1.25;
          }
        } else if (diff < -0.01) {
          String acaoDefice = reg['acaoFalta']?.toString() ?? 'Descontar no Banco';
          if (acaoDefice == 'Descontar no Banco') {
            bancoHorasMesDescontadas += diff.abs();
          } else if (acaoDefice == 'Descontar no Salário') {
            totalValorDescontosEuros += diff.abs() * valorHoraBase;
          }
        }
      } else if (tipo == 'Folga Trabalhada') {
        String acaoFolga = reg['acaoFolgaTrabalhada']?.toString() ?? 'Banco de Horas';
        if (acaoFolga == 'Banco de Horas') {
          bancoHorasMesGanhas += hEfetivas;
        } else if (acaoFolga == 'Salário') {
          totalValorExtraEuros += hEfetivas * valorHoraBase * 1.25;
        }
      }
    });

    double saldoBancoHorasLiquido = bancoHorasMesGanhas - bancoHorasMesDescontadas;
    double totalIliquidoAReceber = salarioBase + totalValorExtraEuros - totalValorDescontosEuros + totalSubsidioEuros;

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
        child: ListView(
          padding: EdgeInsets.zero,
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
              accountName: Text(nomeTrabalhador, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              accountEmail: Text(nomeEmpresa),
            ),
            _buildSectionHeader('CONTA & SEGURANÇA'),
            ListTile(
              dense: true,
              leading: const Icon(Icons.person_outline, color: Color(0xFF1A237E)),
              title: const Text('Configurar Perfil', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Dados pessoais, empresa e remuneração'),
              onTap: () {
                Navigator.pop(context);
                SettingsModal.abrirModalPerfil(context: context, perfil: _perfil, onAtualizado: _carregarDados);
              },
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.lock_outline, color: Color(0xFF1A237E)),
              title: const Text('Segurança e Código PIN', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Bloqueio e proteção de acesso'),
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
            const Divider(height: 20),
            _buildSectionHeader('RELATÓRIOS & LEGISLAÇÃO'),
            ListTile(
              dense: true,
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: const Text('Relatórios e Mapas PDF', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Resumo anual, extratos e banco de horas'),
              onTap: () {
                Navigator.pop(context);
                _mostrarDialogoExportacaoPdf(context);
              },
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.menu_book, color: Colors.indigo),
              title: const Text('Código do Trabalho', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Consulta legislativa oficial (Lei n.º 7/2009)'),
              onTap: () {
                Navigator.pop(context);
                _abrirCodigoTrabalho();
              },
            ),
            const Divider(height: 20),
            _buildSectionHeader('CÓPIAS & NUVEM'),
            ListTile(
              dense: true,
              leading: const Icon(Icons.cloud_sync, color: Colors.blue),
              title: const Text('Google Drive & Sincronização', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(DriveService.estaAutenticado ? (DriveService.emailContaAtiva ?? 'Ligado') : 'Ligar conta para backup na nuvem'),
              onTap: () {
                Navigator.pop(context);
                _mostrarDialogoGoogleDrive(context);
              },
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.upload_file, color: Colors.teal),
              title: const Text('Exportar Base de Dados (Local)', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Guardar cópia de segurança no dispositivo'),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(context);
                bool ok = await DatabaseHelper.instance.exportarEGuardarBaseDeDados();
                messenger.showSnackBar(SnackBar(
                  content: Text(ok ? 'Backup exportado com sucesso!' : 'Erro ou cancelado na exportação.'),
                ));
              },
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.download, color: Colors.orange),
              title: const Text('Restaurar Base de Dados', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Importar ficheiro .db anteriormente guardado'),
              onTap: () async {
                Navigator.pop(context);
                await SettingsModal.executarRestauro(
                  context: context,
                  onAtualizado: _carregarDados,
                  onFeedback: (msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg))),
                );
              },
            ),
            const Divider(height: 20),
            _buildSectionHeader('SISTEMA'),
            ListTile(
              dense: true,
              leading: const Icon(Icons.system_update_rounded, color: Colors.green),
              title: const Text('Atualizar Aplicação', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Verificar novas versões no GitHub'),
              onTap: () async {
                Navigator.pop(context);
                await UpdateService.verificarEForcarAtualizacao(
                  context,
                  manual: true,
                  onFeedback: (msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg))),
                );
              },
            ),
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
              child: Text(
                'Gestão de Horários\nDesenvolvido por Rui Barata © 2026',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  color: Colors.indigo.shade50,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(icon: const Icon(Icons.chevron_left, color: Color(0xFF1A237E)), onPressed: () => _mudarMes(-1)),
                      Text('${mesesNomes[_mesAtual - 1]} $_anoAtual', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                      IconButton(icon: const Icon(Icons.chevron_right, color: Color(0xFF1A237E)), onPressed: () => _mudarMes(1)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildResumoItem(
                                'Saldo Banco',
                                '${saldoBancoHorasLiquido >= 0 ? '+' : ''}${saldoBancoHorasLiquido.toStringAsFixed(1)}h',
                                saldoBancoHorasLiquido >= 0 ? Colors.indigo.shade900 : Colors.orange.shade900,
                              ),
                              _buildResumoItem('H. Extras Banco', '+${bancoHorasMesGanhas.toStringAsFixed(1)}h', Colors.green.shade800),
                              _buildResumoItem('H. Desconto Banco', '-${bancoHorasMesDescontadas.toStringAsFixed(1)}h', Colors.red.shade800),
                            ],
                          ),
                          const Divider(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildResumoItem('Férias', '${diasFeriasMes}d', const Color(0xFF0288D1)),
                              _buildResumoItem('Folgas', '${diasFolgasMes}d', const Color(0xFF7B1FA2)),
                              _buildResumoItem('Faltas', '${diasFaltasMes}d', const Color(0xFFE65100)),
                              _buildResumoItem('Baixas', '${diasBaixasMes}d', const Color(0xFFC62828)),
                            ],
                          ),
                          const Divider(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildResumoItem('Salário Base', '${salarioBase.toStringAsFixed(2)} EUR', Colors.black87),
                              _buildResumoItem('Valor H. Extra', '+${totalValorExtraEuros.toStringAsFixed(2)} EUR', Colors.green.shade900),
                              _buildResumoItem('Descontos Sal.', '-${totalValorDescontosEuros.toStringAsFixed(2)} EUR', Colors.red.shade900),
                              _buildResumoItem('Subs. Alim.', '${totalSubsidioEuros.toStringAsFixed(2)} EUR', Colors.brown),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A237E),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('TOTAL ILÍQUIDO A RECEBER:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                                Text(
                                  '${totalIliquidoAReceber.toStringAsFixed(2)} EUR',
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
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: _construirCalendario(),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 8, bottom: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade600,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildResumoItem(String titulo, String valor, Color cor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(titulo, style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)),
        const SizedBox(height: 1),
        Text(valor, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: cor)),
      ],
    );
  }

  Widget _construirCalendario() {
    final primeiroDiaDoMes = DateTime(_anoAtual, _mesAtual, 1);
    final ultimoDiaDoMes = DateTime(_anoAtual, _mesAtual + 1, 0);
    int diasNoMes = ultimoDiaDoMes.day;
    int diaSemanaInicio = primeiroDiaDoMes.weekday - 1;

    List<Widget> cabecalhos = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom']
        .map((d) => Center(
              child: Text(
                d,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey),
              ),
            ))
        .toList();

    List<Widget> celulas = [];

    for (int i = 0; i < diaSemanaInicio; i++) {
      celulas.add(const SizedBox.shrink());
    }

    for (int dia = 1; dia <= diasNoMes; dia++) {
      final dataAtual = DateTime(_anoAtual, _mesAtual, dia);
      String chaveData = "$_anoAtual-${_mesAtual.toString().padLeft(2, '0')}-${dia.toString().padLeft(2, '0')}";
      final reg = _registosMes[chaveData];

      String tipoDia = reg?['tipoDia'] ?? '';
      double hEfetivas = (reg?['horasEfetivas'] as num?)?.toDouble() ?? 0.0;
      double hContratadas = (reg?['horasContratadas'] as num?)?.toDouble() ?? 8.0;
      double diff = hEfetivas - hContratadas;

      Color corFundo = Colors.white;
      Color corBorda = Colors.grey.shade300;
      IconData? iconeSituacao;
      Color corIcone = Colors.black;

      if (tipoDia == 'Trabalho') {
        corFundo = const Color(0xFFE8F5E9);
        corBorda = const Color(0xFF81C784);
        iconeSituacao = Icons.work;
        corIcone = const Color(0xFF2E7D32);
      } else if (tipoDia == 'Férias') {
        corFundo = const Color(0xFFE1F5FE);
        corBorda = const Color(0xFF4FC3F7);
        iconeSituacao = Icons.beach_access;
        corIcone = const Color(0xFF0288D1);
      } else if (tipoDia == 'Folga') {
        corFundo = const Color(0xFFF3E5F5);
        corBorda = const Color(0xFFBA68C8);
        iconeSituacao = Icons.weekend;
        corIcone = const Color(0xFF7B1FA2);
      } else if (tipoDia == 'Folga Trabalhada') {
        corFundo = const Color(0xFFE0F2F1);
        corBorda = const Color(0xFF4DB6AC);
        iconeSituacao = Icons.work_history;
        corIcone = const Color(0xFF00796B);
      } else if (tipoDia == 'Falta') {
        corFundo = const Color(0xFFFFF3E0);
        corBorda = const Color(0xFFFFB74D);
        iconeSituacao = Icons.warning_amber_rounded;
        corIcone = const Color(0xFFE65100);
      } else if (tipoDia == 'Baixa') {
        corFundo = const Color(0xFFFFEBEE);
        corBorda = const Color(0xFFE57373);
        iconeSituacao = Icons.local_hospital;
        corIcone = const Color(0xFFC62828);
      }

      celulas.add(
        InkWell(
          onTap: () {
            DayModal.abrirRegistoDia(
              context: context,
              dia: dataAtual,
              perfil: _perfil,
              onAtualizado: _carregarDados,
            );
          },
          borderRadius: BorderRadius.circular(6),
          child: Container(
            margin: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              color: corFundo,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: corBorda, width: 1),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$dia',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                    if (iconeSituacao != null)
                      Icon(iconeSituacao, size: 12, color: corIcone),
                  ],
                ),
                if ((tipoDia == 'Trabalho' || tipoDia == 'Folga Trabalhada') && diff.abs() > 0.01)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      diff > 0 ? '+${diff.toStringAsFixed(1)}h' : '${diff.toStringAsFixed(1)}h',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: diff > 0 ? Colors.green.shade900 : Colors.red.shade900,
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 10),
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
        const SizedBox(height: 2),
        Expanded(
          child: GridView.count(
            crossAxisCount: 7,
            childAspectRatio: 0.85,
            physics: const BouncingScrollPhysics(),
            children: celulas,
          ),
        ),
      ],
    );
  }
}