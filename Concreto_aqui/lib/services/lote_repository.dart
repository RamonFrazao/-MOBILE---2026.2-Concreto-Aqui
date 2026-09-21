import 'dart:convert';
import 'dart:io';
import 'api_config.dart';
import 'session.dart';

/// Resultado de uma busca de lote na API real.
class LoteApiResultado {
  final Map<String, dynamic>? lote;
  final String? erro;

  const LoteApiResultado.encontrado(Map<String, dynamic> this.lote)
      : erro = null;
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
      final client = HttpClient();
      try {
        final request = await client
            .getUrl(Uri.parse('${ApiConfig.baseUrl}/lotes/$codigo'))
            .timeout(const Duration(seconds: 8));
        if (token != null) {
          request.headers.set('Authorization', 'Bearer $token');
        }
        final response = await request.close().timeout(
              const Duration(seconds: 8),
            );
        final body = await response.transform(utf8.decoder).join();

        final data = jsonDecode(body) as Map<String, dynamic>;

        if (response.statusCode == 200) {
          return LoteApiResultado.encontrado(data);
        }
        return LoteApiResultado.problema(
          data['erro'] as String? ?? 'Não foi possível buscar este lote.',
        );
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      return const LoteApiResultado.problema(
        'Não foi possível falar com o servidor. Confira se a API está no ar.',
      );
    }
  }
}
