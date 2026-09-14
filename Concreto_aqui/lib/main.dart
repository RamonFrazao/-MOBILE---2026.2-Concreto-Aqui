import 'package:flutter/material.dart';
import 'models/domain_models.dart';
import 'screens/construtora/construtora_screens.dart';
import 'screens/laboratorio/laboratorio_screens.dart';
import 'screens/login_screen.dart';
import 'screens/obra/obra_screens.dart';
import 'services/session.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const ConcretoAquiApp());
}

class ConcretoAquiApp extends StatelessWidget {
  const ConcretoAquiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Concreto Aqui',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const _Bootstrap(),
    );
  }
}

/// Primeira coisa que roda ao abrir o app: confere se já existe uma
/// sessão salva no aparelho. Se sim, pula o login direto para a home do
/// perfil — é o que faz o usuário não entrar de novo a cada abertura.
class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  @override
  void initState() {
    super.initState();
    _checarSessao();
  }

  Future<void> _checarSessao() async {
    final usuario = await Session.instance.restaurar();
    if (!mounted) return;

    if (usuario == null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    final tela = switch (usuario.perfil) {
      Perfil.construtora => const HomeConstrutoraScreen(),
      Perfil.obra => const HomeObraScreen(),
      Perfil.laboratorio => const HomeLaboratorioScreen(),
    };
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => tela));
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.ink,
      body: Center(child: CircularProgressIndicator(color: Colors.white)),
    );
  }
}
