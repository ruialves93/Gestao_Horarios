import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/main_screen.dart';
import 'services/database_helper.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Forçar orientação retrato para melhor visualização dos calendários e relatórios
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const GestaoHorariosApp());
}

class GestaoHorariosApp extends StatelessWidget {
  const GestaoHorariosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gestão de Horários',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: Colors.grey.shade50,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A237E),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const AutenticacaoInicialScreen(),
    );
  }
}

class AutenticacaoInicialScreen extends StatefulWidget {
  const AutenticacaoInicialScreen({super.key});

  @override
  State<AutenticacaoInicialScreen> createState() => _AutenticacaoInicialScreenState();
}

class _AutenticacaoInicialScreenState extends State<AutenticacaoInicialScreen> {
  bool _aVerificar = true;
  bool _requerPin = false;
  final TextEditingController _pinController = TextEditingController();
  String _pinGuardado = '';

  @override
  void initState() {
    super.initState();
    // Aguardar o primeiro frame ser renderizado para disparar a biometria com segurança
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verificarSegurancaNoArranque();
    });
  }

  Future<void> _verificarSegurancaNoArranque() async {
    final perfil = await DatabaseHelper.instance.getPerfil();
    int pinAtivo = (perfil['pinAtivo'] as num?)?.toInt() ?? 0;
    int biometriaAtiva = (perfil['biometriaAtiva'] as num?)?.toInt() ?? 0;
    _pinGuardado = perfil['codigoPin']?.toString() ?? '';

    if (pinAtivo == 1) {
      if (biometriaAtiva == 1) {
        // Tentar autenticar por biometria de imediato ao abrir
        bool sucessoBiometria = await AuthService.autenticarComBiometria();
        if (sucessoBiometria) {
          _entrarNaApp();
          return;
        }
      }
      
      // Se a biometria estiver desligada, falhar ou for cancelada, mostra o ecrã do PIN
      if (mounted) {
        setState(() {
          _aVerificar = false;
          _requerPin = true;
        });
      }
    } else {
      _entrarNaApp();
    }
  }

  void _entrarNaApp() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const MainScreen()),
    );
  }

  void _validarPin() {
    if (_pinController.text == _pinGuardado) {
      _entrarNaApp();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN incorreto. Tente novamente.'), backgroundColor: Colors.red),
      );
      _pinController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_aVerificar && !_requerPin) {
      return Scaffold(
        backgroundColor: const Color(0xFF1A237E),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipOval(
                child: Image.asset(
                  'assets/logo_rb.png',
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.access_time, size: 80, color: Colors.white),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Gestão de Horários',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(color: Colors.amberAccent),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1A237E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline, size: 64, color: Colors.amberAccent),
                  const SizedBox(height: 16),
                  const Text(
                    'Aplicação Protegida',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Insira o PIN ou utilize a impressão digital',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: TextField(
                      controller: _pinController,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      obscureText: true,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 24, letterSpacing: 8, color: Colors.white, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        counterText: '',
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.1),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _validarPin(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: 220,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amberAccent,
                        foregroundColor: const Color(0xFF1A237E),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _validarPin,
                      child: const Text('Desbloquear com PIN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.white70),
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Tentar Impressão Digital'),
                    onPressed: () async {
                      bool sucesso = await AuthService.autenticarComBiometria();
                      if (sucesso) {
                        _entrarNaApp();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}