import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'session.dart';

/// Resultado de uma busca de lote na API real.
class LoteApiResultado {
  final Map<String, dynamic>? lote;
  final String? erro;

  const LoteApiResultado.encontrado(Map<String, dynamic> this.lote) : erro = null;
  const LoteApiResultado.problema(String mensagem)
      : lote = null,
        erro = mensagem;

  bool get ok => lote != null;
}

/// Fala com a rota GET /lotes/:codigo da API. É aqui que a recusa de
/// dados de outra construtora acontece de verdade — o servidor decide,
/// não o app.
class LoteRepository {
  Future<LoteApiResultado> buscarPorCodigo(String codigo) async {
    final token = Session.instance.token;
    try {
      final resp = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/lotes/$codigo'),
            headers: {if (token != null) 'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 8));

      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      if (resp.statusCode == 200) {
        return LoteApiResultado.encontrado(data);
      }
      return LoteApiResultado.problema(
        data['erro'] as String? ?? 'Não foi possível buscar este lote.',
      );
    } catch (_) {
      return const LoteApiResultado.problema(
        'Não foi possível falar com o servidor. Confira se a API está no ar.',
      );
    }
  }
}
