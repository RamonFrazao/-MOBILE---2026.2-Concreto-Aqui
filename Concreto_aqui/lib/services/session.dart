import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/domain_models.dart';

/// Sessão do usuário logado. Guardada no armazenamento seguro do
/// aparelho — por isso não se pede login de novo a cada abertura do app.
/// O que fica salvo é o token de sessão (JWT) e os dados do usuário que
/// a API já devolveu; a senha nunca passa por aqui.
class Session {
  Session._();
  static final Session instance = Session._();

  static const _storage = FlutterSecureStorage();
  static const _chaveToken = 'concreto_aqui_token';
  static const _chaveUsuario = 'concreto_aqui_usuario';

  Usuario? usuarioAtual;
  String? token;

  bool get logado => usuarioAtual != null;

  Future<void> salvar(Usuario usuario, String token) async {
    usuarioAtual = usuario;
    this.token = token;
    await _storage.write(key: _chaveToken, value: token);
    await _storage.write(
      key: _chaveUsuario,
      value: jsonEncode({
        'username': usuario.username,
        'perfil': usuario.perfil.name,
        'nome': usuario.nome,
        'construtora': usuario.construtora,
      }),
    );
  }

  /// Chamado na abertura do app: se houver sessão salva, restaura sem
  /// pedir login de novo. Retorna null se não houver nada salvo.
  Future<Usuario?> restaurar() async {
    final token = await _storage.read(key: _chaveToken);
    final usuarioJson = await _storage.read(key: _chaveUsuario);
    if (token == null || usuarioJson == null) return null;

    final map = jsonDecode(usuarioJson) as Map<String, dynamic>;
    final usuario = Usuario(
      username: map['username'] as String,
      senha: '',
      perfil: Perfil.values.firstWhere((p) => p.name == map['perfil']),
      nome: map['nome'] as String,
      construtora: map['construtora'] as String?,
    );
    this.token = token;
    usuarioAtual = usuario;
    return usuario;
  }

  Future<void> encerrar() async {
    usuarioAtual = null;
    token = null;
    await _storage.delete(key: _chaveToken);
    await _storage.delete(key: _chaveUsuario);
  }
}
