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

/// Um lote na listagem: obra, data, fck de projeto e o que já chegou.
/// (Os nomes terminam em "Resumo", "Completo" etc. para não colidir com
/// o `Lote` antigo de domain_models.dart, que ainda alimenta o mock.)
class LoteResumo {
  final int id;
  final String numero;
  final String status; // 'em_andamento' | 'encerrado'
  final int? fckProjeto;
  final int obraId;
  final String obraNome;
  final String dataConcretagem; // AAAA-MM-DD
  final int qtdPecas;
  final int qtdCaminhoes;
  final num volumeTotal;

  const LoteResumo({
    required this.id,
    required this.numero,
    required this.status,
    required this.fckProjeto,
    required this.obraId,
    required this.obraNome,
    required this.dataConcretagem,
    required this.qtdPecas,
    required this.qtdCaminhoes,
    required this.volumeTotal,
  });

  bool get encerrado => status == 'encerrado';

  factory LoteResumo.fromJson(Map<String, dynamic> j) => LoteResumo(
        id: j['id'] as int,
        numero: j['numero'] as String,
        status: j['status'] as String,
        fckProjeto: j['fck_projeto'] as int?,
        obraId: j['obra_id'] as int,
        obraNome: j['obra_nome'] as String,
        dataConcretagem: j['data_concretagem'] as String,
        qtdPecas: (j['qtd_pecas'] as int?) ?? 0,
        qtdCaminhoes: (j['qtd_caminhoes'] as int?) ?? 0,
        volumeTotal: (j['volume_total'] as num?) ?? 0,
      );
}

class PecaDoLote {
  final int id;
  final String tipo;
  final String identificacao;
  final String pavimentoNome;

  const PecaDoLote({
    required this.id,
    required this.tipo,
    required this.identificacao,
    required this.pavimentoNome,
  });

  /// "Pilar P7"
  String get rotulo => '${_rotuloTipoPeca(tipo)} $identificacao';

  factory PecaDoLote.fromJson(Map<String, dynamic> j) => PecaDoLote(
        id: j['id'] as int,
        tipo: j['tipo'] as String,
        identificacao: j['identificacao'] as String,
        pavimentoNome: j['pavimento_nome'] as String,
      );
}

class CaminhaoDoLote {
  final int id;
  final String? placa;
  final num? volume;
  final String centralNome;
  final int? pedidoNumero;
  final DateTime criadoEm;

  const CaminhaoDoLote({
    required this.id,
    required this.placa,
    required this.volume,
    required this.centralNome,
    required this.pedidoNumero,
    required this.criadoEm,
  });

  factory CaminhaoDoLote.fromJson(Map<String, dynamic> j) => CaminhaoDoLote(
        id: j['id'] as int,
        placa: j['placa'] as String?,
        volume: j['volume'] as num?,
        centralNome: j['central_nome'] as String,
        pedidoNumero: j['pedido_numero'] as int?,
        criadoEm: DateTime.parse(j['criado_em'] as String).toLocal(),
      );
}

/// O lote aberto: peças que abrange, caminhões recebidos e volume total.
class LoteCompleto {
  final int id;
  final String numero;
  final String status;
  final int? fckProjeto;
  final String? obraNome;
  final String? dataConcretagem; // AAAA-MM-DD
  final List<PecaDoLote> pecas;
  final List<CaminhaoDoLote> caminhoes;
  final int qtdCaminhoes;
  final num volumeTotal;

  const LoteCompleto({
    required this.id,
    required this.numero,
    required this.status,
    required this.fckProjeto,
    required this.obraNome,
    required this.dataConcretagem,
    required this.pecas,
    required this.caminhoes,
    required this.qtdCaminhoes,
    required this.volumeTotal,
  });

  bool get emAndamento => status == 'em_andamento';
  bool get encerrado => status == 'encerrado';

  factory LoteCompleto.fromJson(Map<String, dynamic> j) => LoteCompleto(
        id: j['id'] as int,
        numero: j['numero'] as String,
        status: j['status'] as String,
        fckProjeto: j['fck_projeto'] as int?,
        obraNome: j['obra_nome'] as String?,
        dataConcretagem: j['data_concretagem'] as String?,
        pecas: (j['pecas'] as List).map((e) => PecaDoLote.fromJson(e as Map<String, dynamic>)).toList(),
        caminhoes: (j['caminhoes'] as List).map((e) => CaminhaoDoLote.fromJson(e as Map<String, dynamic>)).toList(),
        qtdCaminhoes: (j['qtd_caminhoes'] as int?) ?? 0,
        volumeTotal: (j['volume_total'] as num?) ?? 0,
      );
}

class OpcaoObra {
  final int id;
  final String nome;
  const OpcaoObra({required this.id, required this.nome});

  factory OpcaoObra.fromJson(Map<String, dynamic> j) =>
      OpcaoObra(id: j['id'] as int, nome: j['nome'] as String);
}

class OpcaoPecaLote {
  final int id;
  final int obraId;
  final String tipo;
  final String identificacao;
  final String pavimentoNome;

  const OpcaoPecaLote({
    required this.id,
    required this.obraId,
    required this.tipo,
    required this.identificacao,
    required this.pavimentoNome,
  });

  /// "3º pavimento · Pilar P7"
  String get rotulo => '$pavimentoNome · ${_rotuloTipoPeca(tipo)} $identificacao';

  factory OpcaoPecaLote.fromJson(Map<String, dynamic> j) => OpcaoPecaLote(
        id: j['id'] as int,
        obraId: j['obra_id'] as int,
        tipo: j['tipo'] as String,
        identificacao: j['identificacao'] as String,
        pavimentoNome: j['pavimento_nome'] as String,
      );
}

/// As escolhas do formulário de abertura de lote.
class OpcoesLote {
  final List<OpcaoObra> obras;
  final List<OpcaoPecaLote> pecas;

  const OpcoesLote({required this.obras, required this.pecas});

  factory OpcoesLote.fromJson(Map<String, dynamic> j) => OpcoesLote(
        obras: (j['obras'] as List).map((e) => OpcaoObra.fromJson(e as Map<String, dynamic>)).toList(),
        pecas: (j['pecas'] as List).map((e) => OpcaoPecaLote.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

/// Resultado de uma chamada: ou deu certo (com dados), ou deu errado com
/// a mensagem que a própria API devolveu.
class LotesResultado<T> {
  final T? dados;
  final String? erro;

  const LotesResultado.sucesso([this.dados]) : erro = null;
  const LotesResultado.falha(String this.erro) : dados = null;

  bool get ok => erro == null;
}

/// Toda regra (uma peça por lote por concretagem, fck válido, lote
/// encerrado, lote com caminhão não se exclui) é decidida pela API; aqui
/// só se envia o pedido e se repassa a resposta.
class LotesApiRepository {
  static const _timeout = Duration(seconds: 8);

  Future<LotesResultado<dynamic>> _chamar(
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
        return LotesResultado.sucesso(dados);
      }
      final mensagem = (dados is Map && dados['erro'] is String)
          ? dados['erro'] as String
          : 'Não foi possível concluir a operação (código ${resp.statusCode}).';
      return LotesResultado.falha(mensagem);
    } catch (_) {
      return LotesResultado.falha(
        'Não foi possível falar com o servidor. Confira se a API está no ar.',
      );
    }
  }

  /// Os lotes da construtora (os mais recentes primeiro).
  Future<LotesResultado<List<LoteResumo>>> listar() async {
    final r = await _chamar('GET', '/lotes');
    if (!r.ok) return LotesResultado.falha(r.erro!);
    try {
      final itens = (r.dados as List).map((e) => LoteResumo.fromJson(e as Map<String, dynamic>)).toList();
      return LotesResultado.sucesso(itens);
    } catch (_) {
      return const LotesResultado.falha('Resposta inesperada do servidor.');
    }
  }

  Future<LotesResultado<OpcoesLote>> opcoes() async {
    final r = await _chamar('GET', '/lotes/opcoes');
    if (!r.ok) return LotesResultado.falha(r.erro!);
    try {
      return LotesResultado.sucesso(OpcoesLote.fromJson(r.dados as Map<String, dynamic>));
    } catch (_) {
      return const LotesResultado.falha('Resposta inesperada do servidor.');
    }
  }

  Future<LotesResultado<LoteCompleto>> detalhe(int id) async {
    final r = await _chamar('GET', '/lotes/$id');
    if (!r.ok) return LotesResultado.falha(r.erro!);
    try {
      return LotesResultado.sucesso(LoteCompleto.fromJson(r.dados as Map<String, dynamic>));
    } catch (_) {
      return const LotesResultado.falha('Resposta inesperada do servidor.');
    }
  }

  /// [dataConcretagem] no formato AAAA-MM-DD.
  Future<LotesResultado<LoteCompleto>> abrir({
    required int obraId,
    required String dataConcretagem,
    required int fckProjeto,
    required List<int> pecaIds,
  }) async {
    final r = await _chamar('POST', '/lotes', corpo: {
      'obra_id': obraId,
      'data_concretagem': dataConcretagem,
      'fck_projeto': fckProjeto,
      'peca_ids': pecaIds,
    });
    if (!r.ok) return LotesResultado.falha(r.erro!);
    try {
      return LotesResultado.sucesso(LoteCompleto.fromJson(r.dados as Map<String, dynamic>));
    } catch (_) {
      return const LotesResultado.falha('Resposta inesperada do servidor.');
    }
  }

  Future<LotesResultado<LoteCompleto>> encerrar(int id) async {
    final r = await _chamar('POST', '/lotes/$id/encerrar');
    if (!r.ok) return LotesResultado.falha(r.erro!);
    try {
      return LotesResultado.sucesso(LoteCompleto.fromJson(r.dados as Map<String, dynamic>));
    } catch (_) {
      return const LotesResultado.falha('Resposta inesperada do servidor.');
    }
  }

  /// Se o lote já recebeu caminhão, a API recusa e o motivo vem em
  /// [LotesResultado.erro].
  Future<LotesResultado<bool>> excluir(int id) async {
    final r = await _chamar('DELETE', '/lotes/$id');
    if (!r.ok) return LotesResultado.falha(r.erro!);
    return const LotesResultado.sucesso(true);
  }
}
