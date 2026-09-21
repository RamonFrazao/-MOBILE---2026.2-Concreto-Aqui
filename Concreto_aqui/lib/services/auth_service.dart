import 'dart:convert';
import 'dart:io';
import '../data/mock_db.dart';
import '../models/domain_models.dart';
import 'api_config.dart';

/// Resultado de uma tentativa de login.
/// A mensagem de erro é sempre a mesma, de propósito: o login não pode
/// revelar se o usuário existe ou se foi a senha que errou.
class LoginResult {
  final Usuario? usuario;
  final String? token;
  final String? erro;

  const LoginResult.sucesso(Usuario this.usuario, String this.token)
      : erro = null;
  const LoginResult.falha()
      : usuario = null,
        token = null,
        erro = 'Usuário ou senha inválidos.';

  bool get ok => usuario != null;
}

/// Contrato do login — as telas dependem só disto, nunca de como o login
/// é resolvido por trás.
abstract class AuthService {
  Future<LoginResult> login(String username, String senha);
}

/// Implementação real: chama a API, que confere a senha cifrada
/// (bcrypt) no servidor e devolve um token de sessão (JWT).
class ApiAuthService implements AuthService {
  @override
  Future<LoginResult> login(String username, String senha) async {
    final client = HttpClient();
    try {
      final request = await client
          .postUrl(Uri.parse('${ApiConfig.baseUrl}/auth/login'))
          .timeout(const Duration(seconds: 8));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'username': username, 'senha': senha}));
      final response =
          await request.close().timeout(const Duration(seconds: 8));
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode != HttpStatus.ok) {
        // A API já responde com a mensagem genérica; não repassamos
        // nenhum outro detalhe do erro para a tela de login.
        return const LoginResult.falha();
      }

      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      final u = data['usuario'] as Map<String, dynamic>;
      final usuario = Usuario(
        username: u['username'] as String,
        senha: '', // a senha nunca volta da API
        perfil: Perfil.values.firstWhere((p) => p.name == u['perfil']),
        nome: u['nome'] as String,
        construtora: u['construtora'] as String?,
      );
      return LoginResult.sucesso(usuario, data['token'] as String);
    } catch (_) {
      // Sem rede, API fora do ar, resposta inesperada — tudo isso também
      // não pode virar uma pista sobre usuário/senha para quem tenta entrar.
      return const LoginResult.falha();
    } finally {
      client.close(force: true);
    }
  }
}

/// Implementação local, só para testar as telas sem precisar da API no
/// ar. Não é o que resolve a T01 — fica aqui como atalho de desenvolvimento.
class MockAuthService implements AuthService {
  @override
  Future<LoginResult> login(String username, String senha) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final match = MockDb.usuarios.where(
      (u) => u.username == username && u.senha == senha,
    );
    if (match.isEmpty) return const LoginResult.falha();
    return LoginResult.sucesso(match.first, 'token-local-mock');
  }
}
