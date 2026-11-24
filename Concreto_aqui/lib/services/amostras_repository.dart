import 'dart:convert';
import 'package:http/http.dart' as http;
import 'fila_offline.dart';
import 'api_config.dart';
import 'session.dart';

class CorpoProvaApi {
  final int id;
  final String? identificacao;
  final int idade;
  final double? resultado;

  const CorpoProvaApi({required this.id, this.identificacao, required this.idade, this.resultado});

  factory CorpoProvaApi.fromJson(Map<String, dynamic> j) => CorpoProvaApi(
        id: j['id'] as int,
        identificacao: j['identificacao'] as String?,
        idade: j['idade'] as int,
        resultado: (j['resultado'] as num?)?.toDouble(),
      );
}

class AmostraApi {
  final int id;
  final int caminhaoId;
  final String? numeroNota;
  final String? placa;
  final int? loteId;
  final String? loteNumero;
  final DateTime coletadaEm;
  final List<CorpoProvaApi> corposProva;

  const AmostraApi({
    required this.id,
    required this.caminhaoId,
    this.numeroNota,
    this.placa,
    this.loteId,
    this.loteNumero,
    required this.coletadaEm,
    required this.corposProva,
  });

  factory AmostraApi.fromJson(Map<String, dynamic> j) => AmostraApi(
        id: j['id'] as int,
        caminhaoId: j['caminhao_id'] as int,
        numeroNota: j['numero_nota'] as String?,
        placa: j['placa'] as String?,
        loteId: j['lote_id'] as int?,
        loteNumero: j['lote_numero'] as String?,
        coletadaEm: DateTime.parse(j['coletada_em'] as String).toLocal(),
        corposProva: (j['corpos_prova'] as List? ?? [])
            .map((e) => CorpoProvaApi.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class AmostrasResultado<T> {
  final bool ok;
  final T? dados;
  final String? erro;

  const AmostrasResultado.sucesso(this.dados)
      : ok = true,
        erro = null;
  const AmostrasResultado.falha(this.erro)
      : ok = false,
        dados = null;
}

class AmostrasRepository {
  static const _timeout = Duration(seconds: 20);

  Future<AmostrasResultado<dynamic>> _chamar(
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
        case 'PUT':
          resp = await http.put(uri, headers: headers, body: jsonEncode(corpo ?? {})).timeout(_timeout);
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
        return AmostrasResultado.sucesso(dados);
      }
      final msg = (dados is Map && dados['erro'] is String)
          ? dados['erro'] as String
          : 'Erro ${resp.statusCode}.';
      return AmostrasResultado.falha(msg);
    } catch (_) {
      return const AmostrasResultado.falha('Não foi possível falar com o servidor.');
    }
  }

  /// Idades de rompimento configuradas (padrão 7 e 28).
  Future<AmostrasResultado<List<int>>> idades() async {
    final r = await _chamar('GET', '/amostras/idades');
    if (!r.ok) return AmostrasResultado.falha(r.erro!);
    try {
      final list = (r.dados as Map)['idades'] as List;
      return AmostrasResultado.sucesso(list.map((e) => e as int).toList());
    } catch (_) {
      return const AmostrasResultado.falha('Resposta inesperada do servidor.');
    }
  }

  Future<AmostrasResultado<List<AmostraApi>>> listar({int? loteId, int? caminhaoId}) async {
    final q = <String>[];
    if (loteId != null) q.add('lote_id=$loteId');
    if (caminhaoId != null) q.add('caminhao_id=$caminhaoId');
    final path = q.isEmpty ? '/amostras' : '/amostras?${q.join('&')}';
    final r = await _chamar('GET', path);
    if (!r.ok) return AmostrasResultado.falha(r.erro!);
    try {
      final itens = (r.dados as List).map((e) => AmostraApi.fromJson(e as Map<String, dynamic>)).toList();
      return AmostrasResultado.sucesso(itens);
    } catch (_) {
      return const AmostrasResultado.falha('Resposta inesperada do servidor.');
    }
  }

  /// Cria amostra ligada a caminhão aceito + molda 2 corpos por idade.
  Future<AmostrasResultado<AmostraApi>> criar({
    required int caminhaoId,
    required DateTime coletadaEm,
  }) async {
    final r = await _chamar(
      'POST',
      '/amostras',
      corpo: {
        'caminhao_id': caminhaoId,
        'coletada_em': coletadaEm.toUtc().toIso8601String(),
      },
    );
    if (!r.ok) return AmostrasResultado.falha(r.erro!);
    try {
      return AmostrasResultado.sucesso(AmostraApi.fromJson(r.dados as Map<String, dynamic>));
    } catch (_) {
      return const AmostrasResultado.falha('Resposta inesperada do servidor.');
    }
  }

  Future<AmostrasResultado<void>> recusarCaminhao(int caminhaoId) async {
    final r = await _chamar('POST', '/amostras/caminhoes/$caminhaoId/recusar');
    if (!r.ok) return AmostrasResultado.falha(r.erro!);
    return const AmostrasResultado.sucesso(null);
  }

  /// Cadeia completa a partir da identificação (obra, construtora e laboratório).
  Future<AmostrasResultado<Map<String, dynamic>>> buscarPorIdentificacao(String identificacao) async {
    final cod = Uri.encodeComponent(identificacao.trim());
    final r = await _chamar('GET', '/amostras/corpos-prova/$cod');
    if (!r.ok) return AmostrasResultado.falha(r.erro!);
    try {
      return AmostrasResultado.sucesso(r.dados as Map<String, dynamic>);
    } catch (_) {
      return const AmostrasResultado.falha('Resposta inesperada do servidor.');
    }
  }

  /// Todos os corpos de prova que cobrem uma peça.
  Future<AmostrasResultado<Map<String, dynamic>>> porPeca(int pecaId) async {
    final r = await _chamar('GET', '/amostras/pecas/$pecaId/corpos-prova');
    if (!r.ok) return AmostrasResultado.falha(r.erro!);
    try {
      return AmostrasResultado.sucesso(r.dados as Map<String, dynamic>);
    } catch (_) {
      return const AmostrasResultado.falha('Resposta inesperada do servidor.');
    }
  }

  Future<AmostrasResultado<Map<String, dynamic>>> iniciarCura({
    required int corpoProvaId,
    DateTime? curaInicioEm,
  }) async {
    final corpo = <String, dynamic>{};
    if (curaInicioEm != null) {
      corpo['cura_inicio_em'] = curaInicioEm.toUtc().toIso8601String();
    }
    final r = await _chamar('POST', '/remessas/corpos-prova/$corpoProvaId/cura', corpo: corpo);
    if (!r.ok) return AmostrasResultado.falha(r.erro!);
    try {
      return AmostrasResultado.sucesso(r.dados as Map<String, dynamic>);
    } catch (_) {
      return const AmostrasResultado.falha('Resposta inesperada do servidor.');
    }
  }

  Future<AmostrasResultado<Map<String, dynamic>>> descartar({
    required int corpoProvaId,
    required String motivo,
  }) async {
    final r = await _chamar(
      'POST',
      '/remessas/corpos-prova/$corpoProvaId/descartar',
      corpo: {'motivo': motivo},
    );
    if (!r.ok) return AmostrasResultado.falha(r.erro!);
    try {
      return AmostrasResultado.sucesso(r.dados as Map<String, dynamic>);
    } catch (_) {
      return const AmostrasResultado.falha('Resposta inesperada do servidor.');
    }
  }

  Future<AmostrasResultado<Map<String, dynamic>>> criarRemessa({
    required int laboratorioId,
    required List<int> corposProvaIds,
    DateTime? enviadaEm,
  }) async {
    final r = await _chamar(
      'POST',
      '/remessas',
      corpo: {
        'laboratorio_id': laboratorioId,
        'corpos_prova_ids': corposProvaIds,
        if (enviadaEm != null) 'enviada_em': enviadaEm.toUtc().toIso8601String(),
      },
    );
    if (!r.ok) return AmostrasResultado.falha(r.erro!);
    try {
      return AmostrasResultado.sucesso(r.dados as Map<String, dynamic>);
    } catch (_) {
      return const AmostrasResultado.falha('Resposta inesperada do servidor.');
    }
  }

  Future<AmostrasResultado<List<Map<String, dynamic>>>> listarRemessas({String? status}) async {
    final path = status != null ? '/remessas?status=$status' : '/remessas';
    final r = await _chamar('GET', path);
    if (!r.ok) return AmostrasResultado.falha(r.erro!);
    try {
      final list = (r.dados as List).cast<Map<String, dynamic>>();
      return AmostrasResultado.sucesso(list);
    } catch (_) {
      return const AmostrasResultado.falha('Resposta inesperada do servidor.');
    }
  }

  Future<AmostrasResultado<Map<String, dynamic>>> receberRemessa(int remessaId) async {
    final r = await _chamar('POST', '/remessas/$remessaId/receber');
    if (!r.ok) return AmostrasResultado.falha(r.erro!);
    try {
      return AmostrasResultado.sucesso(r.dados as Map<String, dynamic>);
    } catch (_) {
      return const AmostrasResultado.falha('Resposta inesperada do servidor.');
    }
  
  Future<AmostrasResultado<Map<String, dynamic>>> corpoParaRompimento(int corpoProvaId) async {
    final r = await _chamar('GET', '/remessas/corpos-prova/$corpoProvaId/para-rompimento');
    if (!r.ok) return AmostrasResultado.falha(r.erro!);
    try {
      return AmostrasResultado.sucesso(r.dados as Map<String, dynamic>);
    } catch (_) {
      return const AmostrasResultado.falha('Resposta inesperada do servidor.');
    }
  }

  /// Lança ou corrige resultado. Correção exige [motivoCorrecao].
  Future<AmostrasResultado<Map<String, dynamic>>> lancarResultado({
    required int corpoProvaId,
    required DateTime rompidoEm,
    required num resistenciaMpa,
    num? idadeRealDias,
    String? motivoCorrecao,
  }) async {
    final r = await _chamar(
      'POST',
      '/remessas/corpos-prova/$corpoProvaId/resultados',
      corpo: {
        'rompido_em': rompidoEm.toUtc().toIso8601String(),
        'resistencia_mpa': resistenciaMpa,
        if (idadeRealDias != null) 'idade_real_dias': idadeRealDias,
        if (motivoCorrecao != null && motivoCorrecao.isNotEmpty) 'motivo_correcao': motivoCorrecao,
      },
    );
    if (!r.ok) return AmostrasResultado.falha(r.erro!);
    try {
      return AmostrasResultado.sucesso(r.dados as Map<String, dynamic>);
    } catch (_) {
      return const AmostrasResultado.falha('Resposta inesperada do servidor.');
    }
  }

  Future<AmostrasResultado<Map<String, dynamic>>> historicoResultados(int corpoProvaId) async {
    final r = await _chamar('GET', '/remessas/corpos-prova/$corpoProvaId/resultados');
    if (!r.ok) return AmostrasResultado.falha(r.erro!);
    try {
      return AmostrasResultado.sucesso(r.dados as Map<String, dynamic>);
    } catch (_) {
      return const AmostrasResultado.falha('Resposta inesperada do servidor.');
    }
  }

  Future<AmostrasResultado<Map<String, dynamic>>> buscarRemessa(int id) async {
    final r = await _chamar('GET', '/remessas/$id');
    if (!r.ok) return AmostrasResultado.falha(r.erro!);
    try {
      return AmostrasResultado.sucesso(r.dados as Map<String, dynamic>);
    } catch (_) {
      return const AmostrasResultado.falha('Resposta inesperada do servidor.');
    }
  }

  Future<AmostrasResultado<AmostraApi?>> moldarAmostraComFila({
    required int caminhaoId,
    required DateTime coletadaEm,
  }) async {
    final r = await criar(caminhaoId: caminhaoId, coletadaEm: coletadaEm);
    if (r.ok) return AmostrasResultado.sucesso(r.dados);
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
    if (!rede) return AmostrasResultado.falha(msg);
    await FilaOffline.instance.enfileirar(
      tipo: 'moldar_amostra',
      metodo: 'POST',
      path: '/amostras',
      rotulo: 'Moldar amostra caminhão #$caminhaoId',
      corpo: {
        'caminhao_id': caminhaoId,
        'coletada_em': coletadaEm.toUtc().toIso8601String(),
      },
    );
    return const AmostrasResultado.sucesso(null);
  }
}
