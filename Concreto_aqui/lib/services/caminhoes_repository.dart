import 'dart:convert';
import 'package:http/http.dart' as http;
import 'fila_offline.dart';
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

/// Uma linha da comparação entre a nota e o pedido, já calculada pela API.
/// [pedido] é o que foi comprado; [nota] é o que o caminhão trouxe.
class ItemConferencia {
  final String campo; // 'classe' | 'fck' | 'volume' | 'central' | 'destino'
  final String rotulo;
  final String pedido;
  final String nota;
  final bool diverge;
  final String? detalhe;

  const ItemConferencia({
    required this.campo,
    required this.rotulo,
    required this.pedido,
    required this.nota,
    required this.diverge,
    this.detalhe,
  });

  factory ItemConferencia.fromJson(Map<String, dynamic> j) => ItemConferencia(
        campo: j['campo'] as String,
        rotulo: j['rotulo'] as String,
        pedido: j['pedido'] as String,
        nota: j['nota'] as String,
        diverge: j['diverge'] as bool,
        detalhe: j['detalhe'] as String?,
      );
}

/// O caminhão com os dados da nota de entrega. (O nome evita colidir com o
/// `Caminhao` antigo de domain_models.dart, que ainda alimenta o mock.)
class CaminhaoRegistrado {
  final int id;
  final String numeroNota;
  final String placa;
  final num volume;
  final String traco;
  final num? consumoCimento;
  final String? aditivos;
  final bool aditivoRetardador;
  final String classeNota;
  final int fckNota;

  /// Quando o cimento encostou na água, lá na central. É data e hora de
  /// verdade (não texto) porque é dela que sai o prazo de descarga.
  final DateTime primeiroContatoEm;

  /// Quando o caminhão chegou à obra — outro horário, separado do anterior.
  final DateTime chegadaObraEm;

  final String centralNome;
  final String loteNumero;
  final int pedidoNumero;
  final List<ItemConferencia> conferencia;
  final int qtdDivergencias;
  final bool confere;

  // Prazo de descarga. Tudo isto é calculado pelo SERVIDOR (relógio do
  // banco), nunca pelo relógio do aparelho.
  /// Prazo que valia quando o caminhão chegou (maior com aditivo retardador).
  final int prazoMinutos;

  /// Quantos minutos antes do fim o app começa a avisar.
  final int avisoMinutos;
  final DateTime limiteEm;

  /// Segundos que faltam (negativo = estourou). Nulo quando a descarga já
  /// foi encerrada.
  final int? restanteSegundos;
  final DateTime? descargaInicioEm;
  final DateTime? descargaFimEm;
  /// Volume efetivamente descarregado (quando a descarga já encerrou).
  final num? volumeEfetivo;
  final bool recusado;

  /// 'no_prazo' | 'atencao' | 'estourado' (descarga aberta) |
  /// 'encerrada_no_prazo' | 'encerrada_fora_do_prazo'.
  final String situacaoPrazo;
  final bool foraDoPrazo;
  final int excedeuMinutos;

  bool get descargaAberta => descargaFimEm == null;

  const CaminhaoRegistrado({
    required this.id,
    required this.numeroNota,
    required this.placa,
    required this.volume,
    required this.traco,
    required this.consumoCimento,
    required this.aditivos,
    required this.aditivoRetardador,
    required this.classeNota,
    required this.fckNota,
    required this.primeiroContatoEm,
    required this.chegadaObraEm,
    required this.centralNome,
    required this.loteNumero,
    required this.pedidoNumero,
    required this.conferencia,
    required this.qtdDivergencias,
    required this.confere,
    required this.prazoMinutos,
    required this.avisoMinutos,
    required this.limiteEm,
    required this.restanteSegundos,
    required this.descargaInicioEm,
    required this.descargaFimEm,
    required this.volumeEfetivo,
    required this.recusado,
    required this.situacaoPrazo,
    required this.foraDoPrazo,
    required this.excedeuMinutos,
  });

  factory CaminhaoRegistrado.fromJson(Map<String, dynamic> j) => CaminhaoRegistrado(
        id: j['id'] as int,
        numeroNota: j['numero_nota'] as String,
        placa: j['placa'] as String,
        volume: j['volume'] as num,
        traco: j['traco'] as String,
        consumoCimento: j['consumo_cimento'] as num?,
        aditivos: j['aditivos'] as String?,
        aditivoRetardador: (j['aditivo_retardador'] as bool?) ?? false,
        classeNota: j['classe_nota'] as String,
        fckNota: j['fck_nota'] as int,
        primeiroContatoEm: DateTime.parse(j['primeiro_contato_em'] as String).toLocal(),
        chegadaObraEm: DateTime.parse(j['chegada_obra_em'] as String).toLocal(),
        centralNome: j['central_nome'] as String,
        loteNumero: j['lote_numero'] as String,
        pedidoNumero: j['pedido_numero'] as int,
        conferencia: (j['conferencia'] as List)
            .map((e) => ItemConferencia.fromJson(e as Map<String, dynamic>))
            .toList(),
        qtdDivergencias: (j['qtd_divergencias'] as int?) ?? 0,
        confere: (j['confere'] as bool?) ?? false,
        prazoMinutos: (j['prazo_minutos'] as int?) ?? 0,
        avisoMinutos: (j['aviso_minutos'] as int?) ?? 0,
        limiteEm: DateTime.parse(j['limite_em'] as String).toLocal(),
        restanteSegundos: j['restante_segundos'] as int?,
        descargaInicioEm: j['descarga_inicio_em'] == null
            ? null
            : DateTime.parse(j['descarga_inicio_em'] as String).toLocal(),
        descargaFimEm: j['descarga_fim_em'] == null
            ? null
            : DateTime.parse(j['descarga_fim_em'] as String).toLocal(),
        volumeEfetivo: j['volume_efetivo'] as num?,
        recusado: (j['recusado'] as bool?) ?? false,
        situacaoPrazo: (j['situacao_prazo'] as String?) ?? 'no_prazo',
        foraDoPrazo: (j['fora_do_prazo'] as bool?) ?? false,
        excedeuMinutos: (j['excedeu_minutos'] as int?) ?? 0,
      );
}

/// Contagem do relatório do prazo de descarga.
class ResumoPrazo {
  final int total;
  final int noPrazo;
  final int atencao;
  final int estourado;
  final int encerradaNoPrazo;
  final int encerradaForaDoPrazo;

  /// Estourados (descarga ainda aberta) + encerrados fora do prazo.
  final int foraDoPrazo;

  const ResumoPrazo({
    required this.total,
    required this.noPrazo,
    required this.atencao,
    required this.estourado,
    required this.encerradaNoPrazo,
    required this.encerradaForaDoPrazo,
    required this.foraDoPrazo,
  });

  factory ResumoPrazo.fromJson(Map<String, dynamic> j) => ResumoPrazo(
        total: j['total'] as int,
        noPrazo: j['no_prazo'] as int,
        atencao: j['atencao'] as int,
        estourado: j['estourado'] as int,
        encerradaNoPrazo: j['encerrada_no_prazo'] as int,
        encerradaForaDoPrazo: j['encerrada_fora_do_prazo'] as int,
        foraDoPrazo: j['fora_do_prazo'] as int,
      );
}

/// O resumo de todos os caminhões e a lista dos que ficaram fora do prazo.
class RelatorioPrazo {
  final ResumoPrazo resumo;
  final List<CaminhaoRegistrado> foraDoPrazo;

  const RelatorioPrazo({required this.resumo, required this.foraDoPrazo});

  factory RelatorioPrazo.fromJson(Map<String, dynamic> j) => RelatorioPrazo(
        resumo: ResumoPrazo.fromJson(j['resumo'] as Map<String, dynamic>),
        foraDoPrazo: (j['caminhoes'] as List)
            .map((e) => CaminhaoRegistrado.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class OpcaoLoteCaminhao {
  final int id;
  final String numero;
  final int obraId;
  final String obraNome;
  final String dataConcretagem; // AAAA-MM-DD
  final int? fckProjeto;

  const OpcaoLoteCaminhao({
    required this.id,
    required this.numero,
    required this.obraId,
    required this.obraNome,
    required this.dataConcretagem,
    required this.fckProjeto,
  });

  String get rotulo => 'Lote $numero · $obraNome';

  factory OpcaoLoteCaminhao.fromJson(Map<String, dynamic> j) => OpcaoLoteCaminhao(
        id: j['id'] as int,
        numero: j['numero'] as String,
        obraId: j['obra_id'] as int,
        obraNome: j['obra_nome'] as String,
        dataConcretagem: j['data_concretagem'] as String,
        fckProjeto: j['fck_projeto'] as int?,
      );
}

class OpcaoPedidoCaminhao {
  final int id;
  final int numero;
  final int obraId;
  final String obraNome;
  final int centralId;
  final String centralNome;
  final String classeNome;
  final int fck;
  final num volume;
  final num volumeEntregue;
  final String pecaTipo;
  final String pecaIdentificacao;

  const OpcaoPedidoCaminhao({
    required this.id,
    required this.numero,
    required this.obraId,
    required this.obraNome,
    required this.centralId,
    required this.centralNome,
    required this.classeNome,
    required this.fck,
    required this.volume,
    required this.volumeEntregue,
    required this.pecaTipo,
    required this.pecaIdentificacao,
  });

  num get saldo => (volume - volumeEntregue) < 0 ? 0 : (volume - volumeEntregue);

  String get pecaRotulo => '${_rotuloTipoPeca(pecaTipo)} $pecaIdentificacao';

  /// "Pedido nº 4 · C25 · Pilar P7 · saldo 6,00 m³"
  String get rotulo =>
      'Pedido nº $numero · $classeNome · $pecaRotulo · saldo ${saldo.toStringAsFixed(2).replaceAll('.', ',')} m³';

  factory OpcaoPedidoCaminhao.fromJson(Map<String, dynamic> j) => OpcaoPedidoCaminhao(
        id: j['id'] as int,
        numero: j['numero'] as int,
        obraId: j['obra_id'] as int,
        obraNome: j['obra_nome'] as String,
        centralId: j['central_id'] as int,
        centralNome: j['central_nome'] as String,
        classeNome: j['classe_nome'] as String,
        fck: j['fck'] as int,
        volume: j['volume'] as num,
        volumeEntregue: j['volume_entregue'] as num,
        pecaTipo: j['peca_tipo'] as String,
        pecaIdentificacao: j['peca_identificacao'] as String,
      );
}

class OpcaoCentralCaminhao {
  final int id;
  final String nome;
  const OpcaoCentralCaminhao({required this.id, required this.nome});

  factory OpcaoCentralCaminhao.fromJson(Map<String, dynamic> j) =>
      OpcaoCentralCaminhao(id: j['id'] as int, nome: j['nome'] as String);
}

/// As escolhas do formulário de registro: lotes em andamento, pedidos
/// abertos e centrais ativas.
class OpcoesCaminhao {
  final List<OpcaoLoteCaminhao> lotes;
  final List<OpcaoPedidoCaminhao> pedidos;
  final List<OpcaoCentralCaminhao> centrais;

  const OpcoesCaminhao({required this.lotes, required this.pedidos, required this.centrais});

  factory OpcoesCaminhao.fromJson(Map<String, dynamic> j) => OpcoesCaminhao(
        lotes: (j['lotes'] as List).map((e) => OpcaoLoteCaminhao.fromJson(e as Map<String, dynamic>)).toList(),
        pedidos: (j['pedidos'] as List).map((e) => OpcaoPedidoCaminhao.fromJson(e as Map<String, dynamic>)).toList(),
        centrais: (j['centrais'] as List).map((e) => OpcaoCentralCaminhao.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

/// Resultado de uma chamada: ou deu certo (com dados), ou deu errado com
/// a mensagem que a própria API devolveu.
class CaminhoesResultado<T> {
  final T? dados;
  final String? erro;

  const CaminhoesResultado.sucesso([this.dados]) : erro = null;
  const CaminhoesResultado.falha(String this.erro) : dados = null;

  bool get ok => erro == null;
}

/// Toda regra (nota não se repete na mesma central, lote encerrado, pedido
/// cancelado, horários coerentes) e a comparação da nota com o pedido são
/// decididas pela API; aqui só se envia o registro e se repassa a resposta.
class CaminhoesRepository {
  static const _timeout = Duration(seconds: 8);

  Future<CaminhoesResultado<dynamic>> _chamar(
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
        return CaminhoesResultado.sucesso(dados);
      }
      final mensagem = (dados is Map && dados['erro'] is String)
          ? dados['erro'] as String
          : 'Não foi possível concluir a operação (código ${resp.statusCode}).';
      return CaminhoesResultado.falha(mensagem);
    } catch (_) {
      return CaminhoesResultado.falha(
        'Não foi possível falar com o servidor. Confira se a API está no ar.',
      );
    }
  }

  /// Os caminhões com nota registrada, os que chegaram por último primeiro.
  Future<CaminhoesResultado<List<CaminhaoRegistrado>>> listar() async {
    final r = await _chamar('GET', '/caminhoes');
    if (!r.ok) return CaminhoesResultado.falha(r.erro!);
    try {
      final itens =
          (r.dados as List).map((e) => CaminhaoRegistrado.fromJson(e as Map<String, dynamic>)).toList();
      return CaminhoesResultado.sucesso(itens);
    } catch (_) {
      return const CaminhoesResultado.falha('Resposta inesperada do servidor.');
    }
  }

  Future<CaminhoesResultado<OpcoesCaminhao>> opcoes() async {
    final r = await _chamar('GET', '/caminhoes/opcoes');
    if (!r.ok) return CaminhoesResultado.falha(r.erro!);
    try {
      return CaminhoesResultado.sucesso(OpcoesCaminhao.fromJson(r.dados as Map<String, dynamic>));
    } catch (_) {
      return const CaminhoesResultado.falha('Resposta inesperada do servidor.');
    }
  }

  Future<CaminhoesResultado<CaminhaoRegistrado>> detalhe(int id) async {
    final r = await _chamar('GET', '/caminhoes/$id');
    if (!r.ok) return CaminhoesResultado.falha(r.erro!);
    try {
      return CaminhoesResultado.sucesso(CaminhaoRegistrado.fromJson(r.dados as Map<String, dynamic>));
    } catch (_) {
      return const CaminhoesResultado.falha('Resposta inesperada do servidor.');
    }
  }

  /// Encerra a descarga. O instante do fim e a comparação com o prazo são
  /// do servidor: o app não envia horário nenhum. Passou do prazo? O
  /// caminhão não some nem é bloqueado: volta marcado como fora do prazo.
  /// Encerra a descarga registrando hora de início, hora de fim e volume
  /// efetivamente descarregado. A API valida fim >= início e grava se ficou
  /// dentro ou fora do prazo. Caminhão já encerrado é recusado (409).
  Future<CaminhoesResultado<CaminhaoRegistrado>> encerrarDescarga(
    int id, {
    required DateTime descargaInicioEm,
    required DateTime descargaFimEm,
    required num volumeEfetivo,
  }) async {
    final r = await _chamar(
      'POST',
      '/caminhoes/$id/encerrar-descarga',
      corpo: {
        'descarga_inicio_em': descargaInicioEm.toUtc().toIso8601String(),
        'descarga_fim_em': descargaFimEm.toUtc().toIso8601String(),
        'volume_efetivo': volumeEfetivo,
      },
    );
    if (!r.ok) return CaminhoesResultado.falha(r.erro!);
    try {
      return CaminhoesResultado.sucesso(CaminhaoRegistrado.fromJson(r.dados as Map<String, dynamic>));
    } catch (_) {
      return const CaminhoesResultado.falha('Resposta inesperada do servidor.');
    }
  }

  /// Relatório do prazo de descarga: resumo e caminhões fora do prazo.
  Future<CaminhoesResultado<RelatorioPrazo>> relatorioPrazo() async {
    final r = await _chamar('GET', '/caminhoes/relatorio/prazo');
    if (!r.ok) return CaminhoesResultado.falha(r.erro!);
    try {
      return CaminhoesResultado.sucesso(RelatorioPrazo.fromJson(r.dados as Map<String, dynamic>));
    } catch (_) {
      return const CaminhoesResultado.falha('Resposta inesperada do servidor.');
    }
  }

  /// Registra o caminhão com os dados da nota. Os dois horários vão em UTC,
  /// com o "Z" no fim, para o servidor nunca interpretar a hora no fuso
  /// dele em vez do da obra.
  Future<CaminhoesResultado<CaminhaoRegistrado>> registrar({
    required int loteId,
    required int pedidoId,
    required int centralId,
    required String numeroNota,
    required String placa,
    required num volume,
    required String traco,
    num? consumoCimento,
    String? aditivos,
    required bool aditivoRetardador,
    required String classeNota,
    required int fckNota,
    required DateTime primeiroContatoEm,
    required DateTime chegadaObraEm,
  }) async {
    final r = await _chamar('POST', '/caminhoes', corpo: {
      'lote_id': loteId,
      'pedido_id': pedidoId,
      'central_id': centralId,
      'numero_nota': numeroNota,
      'placa': placa,
      'volume': volume,
      'traco': traco,
      'consumo_cimento': consumoCimento,
      'aditivos': aditivos,
      'aditivo_retardador': aditivoRetardador,
      'classe_nota': classeNota,
      'fck_nota': fckNota,
      'primeiro_contato_em': primeiroContatoEm.toUtc().toIso8601String(),
      'chegada_obra_em': chegadaObraEm.toUtc().toIso8601String(),
    });
    if (!r.ok) return CaminhoesResultado.falha(r.erro!);
    try {
      return CaminhoesResultado.sucesso(CaminhaoRegistrado.fromJson(r.dados as Map<String, dynamic>));
    } catch (_) {
      return const CaminhoesResultado.falha('Resposta inesperada do servidor.');
    }
  }

  /// Tenta online; se falhar por rede, enfileira e devolve sucesso local.
  Future<CaminhoesResultado<CaminhaoRegistrado?>> encerrarDescargaComFila({
    required int caminhaoId,
    required DateTime descargaInicioEm,
    required DateTime descargaFimEm,
    required num volumeEfetivo,
  }) async {
    final r = await encerrarDescarga(
      caminhaoId,
      descargaInicioEm: descargaInicioEm,
      descargaFimEm: descargaFimEm,
      volumeEfetivo: volumeEfetivo,
    );
    if (r.ok) return CaminhoesResultado.sucesso(r.dados);
    final msg = r.erro ?? '';
    final lower = msg.toLowerCase();
    final rede = lower.contains('rede') ||
        lower.contains('servidor') ||
        lower.contains('socket') ||
        lower.contains('timed out') ||
        lower.contains('timeout') ||
        lower.contains('connection') ||
        lower.contains('conexão') ||
        lower.contains('failed host') ||
        lower.contains('falar com o servidor');
    if (!rede) return CaminhoesResultado.falha(msg);

    await FilaOffline.instance.enfileirar(
      tipo: 'encerrar_descarga',
      metodo: 'POST',
      path: '/caminhoes/$caminhaoId/encerrar-descarga',
      rotulo: 'Encerrar descarga #$caminhaoId',
      corpo: {
        'descarga_inicio_em': descargaInicioEm.toUtc().toIso8601String(),
        'descarga_fim_em': descargaFimEm.toUtc().toIso8601String(),
        'volume_efetivo': volumeEfetivo,
      },
    );
    return const CaminhoesResultado.sucesso(null); // null = ficou na fila
  }
}
