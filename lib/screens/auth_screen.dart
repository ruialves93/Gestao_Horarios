import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import 'main_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _pinController = TextEditingController();
  bool _carregando = true;
  bool _temPin = false;
  String _pinCorreto = '';

  @override
  void initState() {
    super.initState();
    _verificarPin();
  }

  Future<void> _verificarPin() async {
    final perfil = await DatabaseHelper.instance.getPerfil();
    final pin = perfil['codigoPin']?.toString().trim() ?? '';
    final pinAtivo = (perfil['pinAtivo'] as num?)?.toInt() ?? 0;

    if (!mounted) return;

    if (pinAtivo == 1 && pin.isNotEmpty) {
      setState(() {
        _temPin = true;
        _pinCorreto = pin;
        _carregando = false;
      });
    } else {
      // Se não tem PIN ativo, avança diretamente para o ecrã principal
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    }
  }

  void _validarPin() {
    final messenger = ScaffoldMessenger.of(context);
    if (_pinController.text.trim() == _pinCorreto) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    } else {
      _pinController.clear();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Código PIN incorreto! Tente novamente.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _adicionarDigito(String digito) {
    if (_pinController.text.length < 4) {
      _pinController.text += digito;
      if (_pinController.text.length == 4) {
        _validarPin();
      }
    }
  }

  void _removerDigito() {
    if (_pinController.text.isNotEmpty) {
      _pinController.text = _pinController.text.substring(0, _pinController.text.length - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_temPin) {
      return const Scaffold();
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1A237E),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ClipOval(
                    child: Image.asset(
                      'assets/logo_rb.png',
                      height: 80,
                      width: 80,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.lock,
                        size: 60,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Gestão de Horários',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Introduza o seu código PIN para aceder',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.8), // Atualizado aqui
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Mostrador dos 4 dígitos
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _pinController,
                    builder: (context, value, child) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(4, (index) {
                          bool preenchido = index < value.text.length;
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 10),
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: preenchido ? Colors.amberAccent : Colors.white24,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                          );
                        }),
                      );
                    },
                  ),
                  const SizedBox(height: 40),
                  // Teclado Numérico
                  _construirTeclado(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _construirTeclado() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _botaoTeclado('1'),
            _botaoTeclado('2'),
            _botaoTeclado('3'),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _botaoTeclado('4'),
            _botaoTeclado('5'),
            _botaoTeclado('6'),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _botaoTeclado('7'),
            _botaoTeclado('8'),
            _botaoTeclado('9'),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            const SizedBox(width: 70, height: 70),
            _botaoTeclado('0'),
            SizedBox(
              width: 70,
              height: 70,
              child: IconButton(
                icon: const Icon(Icons.backspace_outlined, color: Colors.white, size: 26),
                onPressed: _removerDigito,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _botaoTeclado(String numero) {
    return InkWell(
      onTap: () => _adicionarDigito(numero),
      borderRadius: BorderRadius.circular(35),
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.12),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        alignment: Alignment.center,
        child: Text(
          numero,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
    );
  }
}