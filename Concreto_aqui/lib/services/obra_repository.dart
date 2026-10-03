import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'session.dart';

/// Tipos de peça aceitos pela API (valor) e como aparecem na tela (rótulo).
const Map<String, String> tiposPeca = {
  'pilar': 'Pilar',
  'viga': 'Viga',
  'laje': 'Laje',
  'fundacao': 'Fundação',
};

class Obra {
  final int id;
  final String nome;
  final String endereco;
  final String responsavelTecnico;
  final int qtdPavimentos;
  final int qtdPecas;

  const Obra({
    required this.id,
    required this.nome,
    required this.endereco,
    required this.responsavelTecnico,
    this.qtdPavimentos = 0,
    this.qtdPecas = 0,
  });

  factory Obra.fromJson(Map<String, dynamic> j) => Obra(
        id: j['id'] as int,
        nome: j['nome'] as String,
        endereco: j['endereco'] as String,
        responsavelTecnico: j['responsavel_tecnico'] as String,
        qtdPavimentos: (j['qtd_pavimentos'] as int?) ?? 0,
        qtdPecas: (j['qtd_pecas'] as int?) ?? 0,
      );
}

class Pavimento {
  final int id;
  final String nome;

  const Pavimento({required this.id, required this.nome});

  factory Pavimento.fromJson(Map<String, dynamic> j) =>
      Pavimento(id: j['id'] as int, nome: j['nome'] as String);
}

class Peca {
  final int id;
  final int pavimentoId;
  final String pavimento;
  final String tipo;
  final String identificacao;
  final bool concretoLancado;

  /// Data do lançamento no formato da API (AAAA-MM-DD), ou null.
  final String? dataLancamento;

  const Peca({
    required this.id,
    required this.pavimentoId,
    required this.pavimento,
    required this.tipo,
    required this.identificacao,
    required this.concretoLancado,
    this.dataLancamento,
  });

  factory Peca.fromJson(Map<String, dynamic> j) => Peca(
        id: j['id'] as int,
        pavimentoId: j['pavimento_id'] as int,
        pavimento: (j['pavimento'] as String?) ?? '',
        tipo: j['tipo'] as String,
        identificacao: j['identificacao'] as String,
        concretoLancado: (j['concreto_lancado'] as bool?) ?? false,
        dataLancamento: j['data_lancamento'] as String?,
      );

  String get tipoRotulo => tiposPeca[tipo] ?? tipo;

  /// AAAA-MM-DD -> DD/MM/AAAA (sem depender de pacote de datas).
  String? get dataFormatada {
    final d = dataLancamento;
    if (d == null) return null;
    final partes = d.split('-');
    if (partes.length != 3) return d;
    return '${partes[2]}/${partes[1]}/${partes[0]}';
  }
}

/// Resultado de uma chamada à API: ou deu certo (com dados), ou deu
/// errado (com a mensagem que deve aparecer para o usuário — a mesma
/// que a API devolveu, para a tela sempre dizer o motivo real).
class ApiResultado<T> {
  final T? dados;
  final String? erro;

  const ApiResultado.sucesso([this.dados]) : erro = null;
  const ApiResultado.falha(String this.erro) : dados = null;

  bool get ok => erro == null;
}

/// Obras, pavimentos e peças. Toda regra (dono do dado, identificação
/// única, peça com concreto não pode ser excluída) é decidida pela API;
/// aqui só se envia o pedido e se repassa a resposta.
class ObraRepository {
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
          resp = await http
              .post(uri, headers: headers, body: jsonEncode(corpo ?? {}))
              .timeout(_timeout);
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
      return const ApiResultado.falha(
        'Não foi possível falar com o servidor. Confira se a API está no ar.',
      );
    }
  }

  ApiResultado<List<T>> _lista<T>(
    ApiResultado<dynamic> r,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (!r.ok) return ApiResultado.falha(r.erro!);
    try {
      final itens = (r.dados as List)
          .map((e) => fromJson(e as Map<String, dynamic>))
          .toList();
      return ApiResultado.sucesso(itens);
    } catch (_) {
      return const ApiResultado.falha('Resposta inesperada do servidor.');
    }
  }

  ApiResultado<T> _um<T>(
    ApiResultado<dynamic> r,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (!r.ok) return ApiResultado.falha(r.erro!);
    try {
      return ApiResultado.sucesso(fromJson(r.dados as Map<String, dynamic>));
    } catch (_) {
      return ApiResultado.falha('Resposta inesperada do servidor.');
    }
  }

  // ---- Obras

  Future<ApiResultado<List<Obra>>> listarObras() async =>
      _lista(await _chamar('GET', '/obras'), Obra.fromJson);

  Future<ApiResultado<Obra>> criarObra({
    required String nome,
    required String endereco,
    required String responsavelTecnico,
  }) async =>
      _um(
        await _chamar('POST', '/obras', corpo: {
          'nome': nome,
          'endereco': endereco,
          'responsavel_tecnico': responsavelTecnico,
        }),
        Obra.fromJson,
      );

  // ---- Pavimentos

  Future<ApiResultado<List<Pavimento>>> listarPavimentos(int obraId) async =>
      _lista(await _chamar('GET', '/obras/$obraId/pavimentos'), Pavimento.fromJson);

  Future<ApiResultado<Pavimento>> criarPavimento(int obraId, String nome) async =>
      _um(
        await _chamar('POST', '/obras/$obraId/pavimentos', corpo: {'nome': nome}),
        Pavimento.fromJson,
      );

  // ---- Peças

  Future<ApiResultado<List<Peca>>> listarPecas(int obraId) async =>
      _lista(await _chamar('GET', '/obras/$obraId/pecas'), Peca.fromJson);

  Future<ApiResultado<Peca>> criarPeca({
    required int obraId,
    required int pavimentoId,
    required String tipo,
    required String identificacao,
  }) async =>
      _um(
        await _chamar(
          'POST',
          '/obras/$obraId/pavimentos/$pavimentoId/pecas',
          corpo: {'tipo': tipo, 'identificacao': identificacao},
        ),
        Peca.fromJson,
      );

  /// Se a peça já recebeu concreto, a API recusa e a mensagem do motivo
  /// vem em [ApiResultado.erro].
  Future<ApiResultado<bool>> excluirPeca(int obraId, int pecaId) async {
    final r = await _chamar('DELETE', '/obras/$obraId/pecas/$pecaId');
    if (!r.ok) return ApiResultado.falha(r.erro!);
    return const ApiResultado.sucesso(true);
  }
}
