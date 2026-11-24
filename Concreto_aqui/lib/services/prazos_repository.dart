import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'session.dart';

/// A configuração do prazo de descarga da construtora. O prazo NÃO é um
/// número escrito no app: vem desta configuração, guardada no servidor.
class ConfigPrazo {
  /// Minutos, contados do primeiro contato do cimento com a água.
  final int prazoDescargaMinutos;

  /// Prazo para concreto com aditivo retardador. Nulo = ainda não
  /// configurado (vale o prazo normal).
  final int? prazoRetardadorMinutos;

  /// Quantos minutos antes do fim o app começa a avisar.
  final int avisoMinutos;

  const ConfigPrazo({
    required this.prazoDescargaMinutos,
    required this.prazoRetardadorMinutos,
    required this.avisoMinutos,
  });

  factory ConfigPrazo.fromJson(Map<String, dynamic> j) => ConfigPrazo(
        prazoDescargaMinutos: j['prazo_descarga_minutos'] as int,
        prazoRetardadorMinutos: j['prazo_retardador_minutos'] as int?,
        avisoMinutos: j['aviso_minutos'] as int,
      );
}

/// Resultado de uma chamada: ou deu certo (com dados), ou deu errado com
/// a mensagem que a própria API devolveu.
class PrazosResultado<T> {
  final T? dados;
  final String? erro;

  const PrazosResultado.sucesso([this.dados]) : erro = null;
  const PrazosResultado.falha(String this.erro) : dados = null;

  bool get ok => erro == null;
}

class PrazosRepository {
  static const _timeout = Duration(seconds: 8);

  Future<PrazosResultado<ConfigPrazo>> _chamar(String metodo, {Map<String, dynamic>? corpo}) async {
    final token = Session.instance.token;
    final uri = Uri.parse('${ApiConfig.baseUrl}/configuracoes/prazos');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    try {
      final http.Response resp;
      if (metodo == 'PUT') {
        resp = await http.put(uri, headers: headers, body: jsonEncode(corpo ?? {})).timeout(_timeout);
      } else {
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
        try {
          return PrazosResultado.sucesso(ConfigPrazo.fromJson(dados as Map<String, dynamic>));
        } catch (_) {
          return const PrazosResultado.falha('Resposta inesperada do servidor.');
        }
      }
      final mensagem = (dados is Map && dados['erro'] is String)
          ? dados['erro'] as String
          : 'Não foi possível concluir a operação (código ${resp.statusCode}).';
      return PrazosResultado.falha(mensagem);
    } catch (_) {
      return PrazosResultado.falha(
        'Não foi possível falar com o servidor. Confira se a API está no ar.',
      );
    }
  }

  Future<PrazosResultado<ConfigPrazo>> ler() => _chamar('GET');

  /// Vale para os caminhões que chegarem depois: cada caminhão guarda o
  /// prazo que valia quando chegou. Regras (retardador não menor que o
  /// normal, aviso dentro do prazo) são conferidas pela API.
  Future<PrazosResultado<ConfigPrazo>> salvar({
    required int prazoDescargaMinutos,
    int? prazoRetardadorMinutos,
    required int avisoMinutos,
  }) =>
      _chamar('PUT', corpo: {
        'prazo_descarga_minutos': prazoDescargaMinutos,
        'prazo_retardador_minutos': prazoRetardadorMinutos,
        'aviso_minutos': avisoMinutos,
      });
}
