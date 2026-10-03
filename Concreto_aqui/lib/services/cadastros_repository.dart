import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'session.dart';

class Central {
  final int id;
  final String nome;
  final String cnpj;
  final String contato;
  final bool ativo;
  final int qtdCaminhoes;

  const Central({
    required this.id,
    required this.nome,
    required this.cnpj,
    required this.contato,
    required this.ativo,
    this.qtdCaminhoes = 0,
  });

  factory Central.fromJson(Map<String, dynamic> j) => Central(
        id: j['id'] as int,
        nome: j['nome'] as String,
        cnpj: j['cnpj'] as String,
        contato: j['contato'] as String,
        ativo: j['ativo'] as bool,
        qtdCaminhoes: (j['qtd_caminhoes'] as int?) ?? 0,
      );
}

class Laboratorio {
  final int id;
  final String nome;
  final String cnpj;
  final String contato;
  final bool ativo;
  final int qtdUsuarios;

  const Laboratorio({
    required this.id,
    required this.nome,
    required this.cnpj,
    required this.contato,
    required this.ativo,
    this.qtdUsuarios = 0,
  });

  factory Laboratorio.fromJson(Map<String, dynamic> j) => Laboratorio(
        id: j['id'] as int,
        nome: j['nome'] as String,
        cnpj: j['cnpj'] as String,
        contato: j['contato'] as String,
        ativo: j['ativo'] as bool,
        qtdUsuarios: (j['qtd_usuarios'] as int?) ?? 0,
      );
}

class UsuarioLab {
  final int id;
  final String username;
  final String nome;

  const UsuarioLab({required this.id, required this.username, required this.nome});

  factory UsuarioLab.fromJson(Map<String, dynamic> j) => UsuarioLab(
        id: j['id'] as int,
        username: j['username'] as String,
        nome: j['nome'] as String,
      );
}

/// Resultado de uma chamada à API: ou deu certo (com dados), ou deu
/// errado (com a mensagem que a própria API devolveu, para a tela
/// sempre mostrar o motivo real).
class ApiResultado<T> {
  final T? dados;
  final String? erro;

  const ApiResultado.sucesso([this.dados]) : erro = null;
  const ApiResultado.falha(String this.erro) : dados = null;

  bool get ok => erro == null;
}

/// Centrais, laboratórios e o usuário de acesso do laboratório. Toda
/// regra (dono do dado, CNPJ único, central/laboratório com movimento
/// não pode ser excluído) é decidida pela API; aqui só se envia o
/// pedido e se repassa a resposta.
class CadastrosRepository {
  static const _timeout = Duration(seconds: 8);

  Future<ApiResultado<dynamic>> _chamar(
    String metodo,
    String caminho, {
    Map<String, dynamic>? corpo,
  }) async {
    final token = Session.instance.token;
    final uri = Uri.parse('${ApiConfig.baseUrl}$caminho');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    try {
      final http.Response resp;
      switch (metodo) {
        case 'POST':
          resp = await http.post(uri, headers: headers, body: jsonEncode(corpo ?? {})).timeout(_timeout);
        case 'PATCH':
          resp = await http.patch(uri, headers: headers, body: jsonEncode(corpo ?? {})).timeout(_timeout);
        case 'DELETE':
          resp = await http.delete(uri, headers: headers).timeout(_timeout);
        default:
          resp = await http.get(uri, headers: headers).timeout(_timeout);
      }

      dynamic dados;
      if (resp.body.isNotEmpty) {
        try {
          dados = jsonDecode(resp.body);
        } catch (_) {
          dados = null;
        }
      }

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return ApiResultado.sucesso(dados);
      }
      final mensagem = (dados is Map && dados['erro'] is String)
          ? dados['erro'] as String
          : 'Não foi possível concluir a operação (código ${resp.statusCode}).';
      return ApiResultado.falha(mensagem);
    } catch (_) {
      return ApiResultado.falha(
        'Não foi possível falar com o servidor. Confira se a API está no ar.',
      );
    }
  }

  ApiResultado<List<T>> _lista<T>(ApiResultado<dynamic> r, T Function(Map<String, dynamic>) fromJson) {
    if (!r.ok) return ApiResultado.falha(r.erro!);
    try {
      final itens = (r.dados as List).map((e) => fromJson(e as Map<String, dynamic>)).toList();
      return ApiResultado.sucesso(itens);
    } catch (_) {
      return ApiResultado.falha('Resposta inesperada do servidor.');
    }
  }

  ApiResultado<T> _um<T>(ApiResultado<dynamic> r, T Function(Map<String, dynamic>) fromJson) {
    if (!r.ok) return ApiResultado.falha(r.erro!);
    try {
      return ApiResultado.sucesso(fromJson(r.dados as Map<String, dynamic>));
    } catch (_) {
      return ApiResultado.falha('Resposta inesperada do servidor.');
    }
  }

  // ---- Centrais

  Future<ApiResultado<List<Central>>> listarCentrais() async =>
      _lista(await _chamar('GET', '/centrais'), Central.fromJson);

  Future<ApiResultado<Central>> criarCentral({
    required String nome,
    required String cnpj,
    required String contato,
  }) async =>
      _um(
        await _chamar('POST', '/centrais', corpo: {'nome': nome, 'cnpj': cnpj, 'contato': contato}),
        Central.fromJson,
      );

  Future<ApiResultado<Central>> definirAtivoCentral(int id, bool ativo) async =>
      _um(await _chamar('PATCH', '/centrais/$id/ativo', corpo: {'ativo': ativo}), Central.fromJson);

  /// Se a central já tem movimento, a API recusa e o motivo vem em
  /// [ApiResultado.erro].
  Future<ApiResultado<bool>> excluirCentral(int id) async {
    final r = await _chamar('DELETE', '/centrais/$id');
    if (!r.ok) return ApiResultado.falha(r.erro!);
    return const ApiResultado.sucesso(true);
  }

  // ---- Laboratórios

  Future<ApiResultado<List<Laboratorio>>> listarLaboratorios() async =>
      _lista(await _chamar('GET', '/laboratorios'), Laboratorio.fromJson);

  Future<ApiResultado<Laboratorio>> criarLaboratorio({
    required String nome,
    required String cnpj,
    required String contato,
  }) async =>
      _um(
        await _chamar('POST', '/laboratorios', corpo: {'nome': nome, 'cnpj': cnpj, 'contato': contato}),
        Laboratorio.fromJson,
      );

  Future<ApiResultado<Laboratorio>> definirAtivoLaboratorio(int id, bool ativo) async =>
      _um(await _chamar('PATCH', '/laboratorios/$id/ativo', corpo: {'ativo': ativo}), Laboratorio.fromJson);

  /// Se o laboratório já tem usuário de acesso vinculado, a API recusa
  /// e o motivo vem em [ApiResultado.erro].
  Future<ApiResultado<bool>> excluirLaboratorio(int id) async {
    final r = await _chamar('DELETE', '/laboratorios/$id');
    if (!r.ok) return ApiResultado.falha(r.erro!);
    return const ApiResultado.sucesso(true);
  }

  Future<ApiResultado<List<UsuarioLab>>> listarUsuariosLaboratorio(int laboratorioId) async =>
      _lista(await _chamar('GET', '/laboratorios/$laboratorioId/usuarios'), UsuarioLab.fromJson);

  Future<ApiResultado<UsuarioLab>> criarUsuarioLaboratorio({
    required int laboratorioId,
    required String username,
    required String senha,
    required String nome,
  }) async =>
      _um(
        await _chamar(
          'POST',
          '/laboratorios/$laboratorioId/usuarios',
          corpo: {'username': username, 'senha': senha, 'nome': nome},
        ),
        UsuarioLab.fromJson,
      );
}
