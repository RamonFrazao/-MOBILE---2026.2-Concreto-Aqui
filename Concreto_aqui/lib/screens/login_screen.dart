import 'package:flutter/material.dart';
import '../models/domain_models.dart';
import '../services/auth_service.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';
import 'construtora/construtora_screens.dart';
import 'obra/obra_screens.dart';
import 'laboratorio/laboratorio_screens.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Login de verdade, contra a API. Troque por MockAuthService() só se
  // precisar navegar pelas telas sem a API no ar.
  final AuthService _auth = ApiAuthService();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  String? _erro;
  bool _carregando = false;

  Future<void> _entrar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    final resultado = await _auth.login(_userCtrl.text.trim(), _passCtrl.text.trim());
    if (!mounted) return;
    setState(() => _carregando = false);

    if (!resultado.ok) {
      setState(() => _erro = resultado.erro);
      return;
    }

    final usuario = resultado.usuario!;
    await Session.instance.salvar(usuario, resultado.token!);
    if (!mounted) return;
    final tela = switch (usuario.perfil) {
      Perfil.construtora => const HomeConstrutoraScreen(),
      Perfil.obra => const HomeObraScreen(),
      Perfil.laboratorio => const HomeLaboratorioScreen(),
    };
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => tela),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    alignment: Alignment.center,
                    child: const Text('CA', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                  ),
                  const SizedBox(height: 16),
                  const Text('Concreto Aqui',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  const Text(
                    'Controle tecnológico do concreto — do caminhão que chega à aceitação do lote.',
                    style: TextStyle(color: Color(0xFFD7DCE3), fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 26),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Usuário',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.inkSoft)),
                        const SizedBox(height: 5),
                        TextField(
                          controller: _userCtrl,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        const Text('Senha',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.inkSoft)),
                        const SizedBox(height: 5),
                        TextField(
                          controller: _passCtrl,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _entrar(),
                        ),
                        if (_erro != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(11),
                            decoration: BoxDecoration(
                              color: AppColors.redSoft,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text(
                              _erro!,
                              style: const TextStyle(color: Color(0xFF7C3020), fontSize: 12.5),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.ink,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                            ),
                            onPressed: _carregando ? null : _entrar,
                            child: _carregando
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Entrar', style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'A senha é conferida no servidor, nunca no aparelho — e o erro não diz se o usuário existe ou se foi a senha.',
                    style: TextStyle(color: Color(0xFFAAB4C4), fontSize: 11.5, height: 1.5),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Perfis de teste: construtora · tecnico · lab — senha 1234',
                    style: TextStyle(color: Color(0xFFAAB4C4), fontSize: 11.5, height: 1.5),
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
