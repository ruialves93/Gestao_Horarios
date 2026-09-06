import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../services/database_helper.dart';
import 'main_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _autenticado = false;
  bool _isLoading = true;
  final LocalAuthentication _auth = LocalAuthentication();
  final TextEditingController _pinController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _verificarSegurancaInicial();
  }

  Future<void> _verificarSegurancaInicial() async {
    final perfil = await DatabaseHelper.instance.getPerfil();
    final pinSalvo = perfil['pinSeguranca']?.toString() ?? '';
    final biometriaAtiva = perfil['biometriaAtiva'] == 1;

    if (pinSalvo.isEmpty && !biometriaAtiva) {
      setState(() {
        _autenticado = true;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
      if (biometriaAtiva) {
        Future.delayed(const Duration(milliseconds: 300), () {
          _tentarBiometria();
        });
      }
    }
  }

  Future<void> _tentarBiometria() async {
    try {
      bool canCheck = await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
      if (canCheck) {
        bool didAuthenticate = await _auth.authenticate(
          localizedReason: 'Autentique-se por Impressão Digital ou Reconhecimento Facial',
          options: const AuthenticationOptions(biometricOnly: false),
        );
        if (didAuthenticate && mounted) {
          setState(() {
            _autenticado = true;
          });
        }
      }
    } catch (_) {}
  }

  void _validarPinInserido() async {
    final perfil = await DatabaseHelper.instance.getPerfil();
    final pinSalvo = perfil['pinSeguranca']?.toString() ?? '';

    if (_pinController.text.trim() == pinSalvo) {
      setState(() {
        _autenticado = true;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN incorreto. Tente novamente.'), backgroundColor: Colors.red),
      );
      _pinController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF1A237E))),
      );
    }

    if (_autenticado) {
      return const MainScreen();
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1A237E),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipOval(
                  child: Image.asset(
                    'assets/logo_rb.png',
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (c, o, s) => const Icon(Icons.lock, size: 60, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Gestão de Horários',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const Text(
                  'Desenvolvimento por Rui Barata © 2026',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 30),
                ElevatedButton.icon(
                  onPressed: () => _tentarBiometria(),
                  icon: const Icon(Icons.fingerprint, size: 28),
                  label: const Text('Usar Impressão Digital / Facial', style: TextStyle(fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF1A237E),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                ),
                const SizedBox(height: 30),
                const Text(
                  'Ou introduza o seu PIN de acesso:',
                  style: TextStyle(fontSize: 13, color: Colors.white70),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _pinController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, letterSpacing: 8, color: Colors.white),
                    decoration: InputDecoration(
                      counterText: '',
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.1),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      hintText: '••••',
                      hintStyle: const TextStyle(color: Colors.white54),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                TextButton(
                  onPressed: _validarPinInserido,
                  child: const Text('Desbloquear com PIN', style: TextStyle(color: Colors.white70, decoration: TextDecoration.underline)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}