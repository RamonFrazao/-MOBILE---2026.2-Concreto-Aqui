import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'session.dart';

String _rotuloTipoPeca(String tipo) {
  switch (tipo) {
    case 'pilar':
      return 'Pilar';
    case 'viga':
      return 'Viga';
    case 'laje':
      return 'Laje';
    case 'fundacao':
      return 'Fundação';
    default:
      return tipo;
  }
}

/// Um pedido como a API devolve: já com a obra, a peça, a central, a
/// classe e o volume que já foi entregue.
class Pedido {
  final int id;
  final int numero;
  final String status; // 'aberto' | 'cancelado'
  final num volume;
  final num volumeEntregue;
  final int qtdCaminhoes;
  final DateTime previstaPara;
  final int obraId;
  final String obraNome;
  final String pavimentoNome;
  final String pecaTipo;
  final String pecaIdentificacao;
  final String centralNome;
  final String classeNome;
  final int fck;
  final int abatimentoAlvo;
  final int abatimentoTolerancia;

  const Pedido({
    required this.id,
    required this.numero,
    required this.status,
    required this.volume,
    required this.volumeEntregue,
    required this.qtdCaminhoes,
    required this.previstaPara,
    required this.obraId,
    required this.obraNome,
    required this.pavimentoNome,
    required this.pecaTipo,
    required this.pecaIdentificacao,
    required this.centralNome,
    required this.classeNome,
    required this.fck,
    required this.abatimentoAlvo,
    required this.abatimentoTolerancia,
  });

  bool get cancelado => status == 'cancelado';

  /// "Pilar P7"
  String get pecaRotulo => '${_rotuloTipoPeca(pecaTipo)} $pecaIdentificacao';

  /// O formato usual da classe: "C25, abatimento 100 ± 20 mm".
  String get classeResumo => '$classeNome, abatimento $abatimentoAlvo ± $abatimentoTolerancia mm';

  factory Pedido.fromJson(Map<String, dynamic> j) => Pedido(
        id: j['id'] as int,
        numero: j['numero'] as int,
        status: j['status'] as String,
        volume: j['volume'] as num,
        volumeEntregue: j['volume_entregue'] as num,
        qtdCaminhoes: (j['qtd_caminhoes'] as int?) ?? 0,
        previstaPara: DateTime.parse(j['prevista_para'] as String).toLocal(),
        obraId: j['obra_id'] as int,
        obraNome: j['obra_nome'] as String,
        pavimentoNome: j['pavimento_nome'] as String,
        pecaTipo: j['peca_tipo'] as String,
        pecaIdentificacao: j['peca_identificacao'] as String,
        centralNome: j['central_nome'] as String,
        classeNome: j['classe_nome'] as String,
        fck: j['fck'] as int,
        abatimentoAlvo: j['abatimento_alvo'] as int,
        abatimentoTolerancia: j['abatimento_tolerancia'] as int,
      );
}

class OpcaoCentral {
  final int id;
  final String nome;
  const OpcaoCentral({required this.id, required this.nome});

  factory OpcaoCentral.fromJson(Map<String, dynamic> j) =>
      OpcaoCentral(id: j['id'] as int, nome: j['nome'] as String);
}

class OpcaoClasse {
  final int id;
  final String nome;
  final int fck;
  final int abatimentoAlvo;
  final int abatimentoTolerancia;

  const OpcaoClasse({
    required this.id,
    required this.nome,
    required this.fck,
    required this.abatimentoAlvo,
    required this.abatimentoTolerancia,
  });

  String get resumo => '$nome, abatimento $abatimentoAlvo ± $abatimentoTolerancia mm';

  factory OpcaoClasse.fromJson(Map<String, dynamic> j) => OpcaoClasse(
        id: j['id'] as int,
        nome: j['nome'] as String,
        fck: j['fck'] as int,
        abatimentoAlvo: j['abatimento_alvo'] as int,
        abatimentoTolerancia: j['abatimento_tolerancia'] as int,
      );
}

class OpcaoPeca {
  final int id;
  final String tipo;
  final String identificacao;
  final String pavimentoNome;
  final String obraNome;

  const OpcaoPeca({
    required this.id,
    required this.tipo,
    required this.identificacao,
    required this.pavimentoNome,
    required this.obraNome,
  });

  /// "Residencial Bom Conselho · 3º pavimento · Pilar P7"
  String get rotulo => '$obraNome · $pavimentoNome · ${_rotuloTipoPeca(tipo)} $identificacao';

  factory OpcaoPeca.fromJson(Map<String, dynamic> j) => OpcaoPeca(
        id: j['id'] as int,
        tipo: j['tipo'] as String,
        identificacao: j['identificacao'] as String,
        pavimentoNome: j['pavimento_nome'] as String,
        obraNome: j['obra_nome'] as String,
      );
}

/// As escolhas do formulário de novo pedido: só centrais ativas, as
/// classes e as peças (com a obra e o pavimento delas).
class OpcoesPedido {
  final List<OpcaoCentral> centrais;
  final List<OpcaoClasse> classes;
  final List<OpcaoPeca> pecas;

  const OpcoesPedido({required this.centrais, required this.classes, required this.pecas});

  factory OpcoesPedido.fromJson(Map<String, dynamic> j) => OpcoesPedido(
        centrais: (j['centrais'] as List).map((e) => OpcaoCentral.fromJson(e as Map<String, dynamic>)).toList(),
        classes: (j['classes'] as List).map((e) => OpcaoClasse.fromJson(e as Map<String, dynamic>)).toList(),
        pecas: (j['pecas'] as List).map((e) => OpcaoPeca.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

/// Resultado de uma chamada: ou deu certo (com dados), ou deu errado com
/// a mensagem que a própria API devolveu.
class PedidosResultado<T> {
  final T? dados;
  final String? erro;

  const PedidosResultado.sucesso([this.dados]) : erro = null;
  const PedidosResultado.falha(String this.erro) : dados = null;

  bool get ok => erro == null;
}

/// Toda regra (volume maior que zero, central/classe/peça da própria
/// construtora, número do pedido, cancelamento só sem caminhão) é decidida
/// pela API; aqui só se envia o pedido e se repassa a resposta.
class PedidosRepository {
  static const _timeout = Duration(seconds: 8);

  Future<PedidosResultado<dynamic>> _chamar(
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
        return PedidosResultado.sucesso(dados);
      }
      final mensagem = (dados is Map && dados['erro'] is String)
          ? dados['erro'] as String
          : 'Não foi possível concluir a operação (código ${resp.statusCode}).';
      return PedidosResultado.falha(mensagem);
    } catch (_) {
      return PedidosResultado.falha(
        'Não foi possível falar com o servidor. Confira se a API está no ar.',
      );
    }
  }

  /// Os pedidos da construtora, já ordenados por obra.
  Future<PedidosResultado<List<Pedido>>> listar() async {
    final r = await _chamar('GET', '/pedidos');
    if (!r.ok) return PedidosResultado.falha(r.erro!);
    try {
      final itens = (r.dados as List).map((e) => Pedido.fromJson(e as Map<String, dynamic>)).toList();
      return PedidosResultado.sucesso(itens);
    } catch (_) {
      return const PedidosResultado.falha('Resposta inesperada do servidor.');
    }
  }

  Future<PedidosResultado<OpcoesPedido>> opcoes() async {
    final r = await _chamar('GET', '/pedidos/opcoes');
    if (!r.ok) return PedidosResultado.falha(r.erro!);
    try {
      return PedidosResultado.sucesso(OpcoesPedido.fromJson(r.dados as Map<String, dynamic>));
    } catch (_) {
      return const PedidosResultado.falha('Resposta inesperada do servidor.');
    }
  }

  Future<PedidosResultado<Pedido>> criar({
    required int centralId,
    required int classeId,
    required int pecaId,
    required num volume,
    required DateTime previstaPara,
  }) async {
    final r = await _chamar('POST', '/pedidos', corpo: {
      'central_id': centralId,
      'classe_id': classeId,
      'peca_id': pecaId,
      'volume': volume,
      // Em UTC, com o "Z" no fim, para o servidor não interpretar a hora
      // no fuso dele em vez do seu.
      'prevista_para': previstaPara.toUtc().toIso8601String(),
    });
    if (!r.ok) return PedidosResultado.falha(r.erro!);
    try {
      return PedidosResultado.sucesso(Pedido.fromJson(r.dados as Map<String, dynamic>));
    } catch (_) {
      return const PedidosResultado.falha('Resposta inesperada do servidor.');
    }
  }

  /// Se já chegou caminhão para o pedido, a API recusa e o motivo vem em
  /// [PedidosResultado.erro].
  Future<PedidosResultado<Pedido>> cancelar(int id) async {
    final r = await _chamar('POST', '/pedidos/$id/cancelar');
    if (!r.ok) return PedidosResultado.falha(r.erro!);
    try {
      return PedidosResultado.sucesso(Pedido.fromJson(r.dados as Map<String, dynamic>));
    } catch (_) {
      return const PedidosResultado.falha('Resposta inesperada do servidor.');
    }
  }
}
