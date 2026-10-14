import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'session.dart';

/// Classe de concreto como a API devolve. O nome é diferente de
/// `ClasseConcreto` (o modelo antigo, em domain_models.dart, que ainda
/// alimenta as telas de pedido e lote enquanto elas não migram para a
/// API) para as duas poderem existir no mesmo projeto sem conflito.
class ClasseCadastro {
  final int id;
  final String nome;
  final int fck;
  final int abatimentoAlvo;
  final int abatimentoTolerancia;
  final num agregadoMm;
  final bool aditivoRetardador;
  final String? aditivosOutros;
  final int qtdPedidos;

  const ClasseCadastro({
    required this.id,
    required this.nome,
    required this.fck,
    required this.abatimentoAlvo,
    required this.abatimentoTolerancia,
    required this.agregadoMm,
    required this.aditivoRetardador,
    this.aditivosOutros,
    this.qtdPedidos = 0,
  });

  /// O formato usual de falar da classe: "C25, abatimento 100 ± 20 mm".
  String get resumo => '$nome, abatimento $abatimentoAlvo ± $abatimentoTolerancia mm';

  factory ClasseCadastro.fromJson(Map<String, dynamic> j) => ClasseCadastro(
        id: j['id'] as int,
        nome: j['nome'] as String,
        fck: j['fck'] as int,
        abatimentoAlvo: j['abatimento_alvo'] as int,
        abatimentoTolerancia: j['abatimento_tolerancia'] as int,
        agregadoMm: j['agregado_mm'] is String
            ? num.parse(j['agregado_mm'] as String)
            : j['agregado_mm'] as num,
        aditivoRetardador: j['aditivo_retardador'] as bool,
        aditivosOutros: j['aditivos_outros'] as String?,
        qtdPedidos: (j['qtd_pedidos'] as int?) ?? 0,
      );
}

/// Resultado de uma chamada: ou deu certo (com dados), ou deu errado
/// com a mensagem que a própria API devolveu.
class ClassesResultado<T> {
  final T? dados;
  final String? erro;

  const ClassesResultado.sucesso([this.dados]) : erro = null;
  const ClassesResultado.falha(String this.erro) : dados = null;

  bool get ok => erro == null;
}

/// Toda regra (tolerância obrigatória e não negativa, classe com pedido
/// não pode ser excluída) é decidida pela API; aqui só se envia o pedido
/// e se repassa a resposta.
class ClassesRepository {
  static const _timeout = Duration(seconds: 8);

  Future<ClassesResultado<dynamic>> _chamar(
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
        return ClassesResultado.sucesso(dados);
      }
      final mensagem = (dados is Map && dados['erro'] is String)
          ? dados['erro'] as String
          : 'Não foi possível concluir a operação (código ${resp.statusCode}).';
      return ClassesResultado.falha(mensagem);
    } catch (_) {
      return ClassesResultado.falha(
        'Não foi possível falar com o servidor. Confira se a API está no ar.',
      );
    }
  }

  Future<ClassesResultado<List<ClasseCadastro>>> listar() async {
    final r = await _chamar('GET', '/classes');
    if (!r.ok) return ClassesResultado.falha(r.erro!);
    try {
      final itens = (r.dados as List)
          .map((e) => ClasseCadastro.fromJson(e as Map<String, dynamic>))
          .toList();
      return ClassesResultado.sucesso(itens);
    } catch (_) {
      return const ClassesResultado.falha('Resposta inesperada do servidor.');
    }
  }

  Future<ClassesResultado<ClasseCadastro>> criar({
    required String nome,
    required int fck,
    required int abatimentoAlvo,
    required int abatimentoTolerancia,
    required num agregadoMm,
    required bool aditivoRetardador,
    String? aditivosOutros,
  }) async {
    final r = await _chamar('POST', '/classes', corpo: {
      'nome': nome,
      'fck': fck,
      'abatimento_alvo': abatimentoAlvo,
      'abatimento_tolerancia': abatimentoTolerancia,
      'agregado_mm': agregadoMm,
      'aditivo_retardador': aditivoRetardador,
      'aditivos_outros': aditivosOutros,
    });
    if (!r.ok) return ClassesResultado.falha(r.erro!);
    try {
      return ClassesResultado.sucesso(ClasseCadastro.fromJson(r.dados as Map<String, dynamic>));
    } catch (_) {
      return const ClassesResultado.falha('Resposta inesperada do servidor.');
    }
  }

  /// Se a classe já tem pedido feito, a API recusa e o motivo vem em
  /// [ClassesResultado.erro].
  Future<ClassesResultado<bool>> excluir(int id) async {
    final r = await _chamar('DELETE', '/classes/$id');
    if (!r.ok) return ClassesResultado.falha(r.erro!);
    return const ClassesResultado.sucesso(true);
  }
}
