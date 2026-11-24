import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';
import 'session.dart';

/// Fila offline da obra: caminhão, descarga e moldagem sem rede.
/// Cada item tem client_id gerado no aparelho; reenviar não duplica no servidor.
class FilaOffline extends ChangeNotifier {
  static final FilaOffline instance = FilaOffline._();
  FilaOffline._();

  static const _prefsKey = 'fila_offline_v1';
  List<FilaItem> _itens = [];
  bool _enviando = false;
  Timer? _auto;

  List<FilaItem> get itens => List.unmodifiable(_itens);
  int get pendentes => _itens.where((i) => i.status != FilaStatus.enviado).length;
  int get comErro => _itens.where((i) => i.status == FilaStatus.erro).length;
  bool get enviando => _enviando;

  Future<void> carregar() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      _itens = [];
    } else {
      final list = jsonDecode(raw) as List;
      _itens = list.map((e) => FilaItem.fromJson(e as Map<String, dynamic>)).toList();
    }
    notifyListeners();
    _agendarAuto();
  }

  Future<void> _persistir() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_itens.map((e) => e.toJson()).toList()));
  }

  /// UUID v4 gerado no aparelho.
  static String novoClientId() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  Future<FilaItem> enfileirar({
    required String tipo,
    required String metodo,
    required String path,
    required Map<String, dynamic> corpo,
    String? rotulo,
  }) async {
    final item = FilaItem(
      clientId: novoClientId(),
      tipo: tipo,
      metodo: metodo,
      path: path,
      corpo: Map<String, dynamic>.from(corpo)..['client_id'] = null, // preenchido abaixo
      rotulo: rotulo ?? tipo,
      criadoEm: DateTime.now().toUtc(),
      status: FilaStatus.pendente,
    );
    item.corpo['client_id'] = item.clientId;
    _itens = [..._itens, item];
    await _persistir();
    notifyListeners();
    // tenta enviar em background
    unawaited(enviarPendentes());
    return item;
  }

  void _agendarAuto() {
    _auto?.cancel();
    _auto = Timer.periodic(const Duration(seconds: 30), (_) {
      if (pendentes > 0) unawaited(enviarPendentes());
    });
  }

  /// Sobe a fila: automático ou por comando do usuário.
  Future<void> enviarPendentes({bool forcar = false}) async {
    if (_enviando) return;
    _enviando = true;
    notifyListeners();
    try {
      final token = Session.instance.token;
      final base = ApiConfig.baseUrl;
      if (token == null || token.isEmpty) return;

      // cópia para iterar
      final copia = List<FilaItem>.from(_itens);
      for (final item in copia) {
        if (item.status == FilaStatus.enviado) continue;
        // itens em erro só reenviam se forcar
        if (item.status == FilaStatus.erro && !forcar) continue;

        try {
          final uri = Uri.parse('$base${item.path}');
          final headers = {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
            'X-Client-Id': item.clientId,
          };
          http.Response r;
          if (item.metodo == 'POST') {
            r = await http
                .post(uri, headers: headers, body: jsonEncode(item.corpo))
                .timeout(const Duration(seconds: 25));
          } else if (item.metodo == 'PUT') {
            r = await http
                .put(uri, headers: headers, body: jsonEncode(item.corpo))
                .timeout(const Duration(seconds: 25));
          } else {
            continue;
          }

          if (r.statusCode >= 200 && r.statusCode < 300) {
            item.status = FilaStatus.enviado;
            item.erro = null;
            item.enviadoEm = DateTime.now().toUtc();
          } else {
            // 4xx de negócio: fica na fila com motivo (não some)
            String motivo = 'Erro ${r.statusCode}';
            try {
              final j = jsonDecode(r.body);
              if (j is Map && j['erro'] != null) motivo = j['erro'].toString();
            } catch (_) {}
            item.status = FilaStatus.erro;
            item.erro = motivo;
          }
        } catch (e) {
          // sem rede: permanece pendente
          item.status = FilaStatus.pendente;
          item.erro = null;
        }
        await _persistir();
        notifyListeners();
      }
      // limpa enviados antigos (mantém últimos 20 para auditoria local)
      final enviados = _itens.where((i) => i.status == FilaStatus.enviado).toList();
      if (enviados.length > 20) {
        final remover = enviados.take(enviados.length - 20).map((e) => e.clientId).toSet();
        _itens = _itens.where((i) => !remover.contains(i.clientId)).toList();
        await _persistir();
      }
    } finally {
      _enviando = false;
      notifyListeners();
    }
  }

  Future<void> tentarDeNovo(String clientId) async {
    final i = _itens.indexWhere((e) => e.clientId == clientId);
    if (i < 0) return;
    _itens[i].status = FilaStatus.pendente;
    _itens[i].erro = null;
    await _persistir();
    notifyListeners();
    await enviarPendentes(forcar: true);
  }
}

enum FilaStatus { pendente, enviado, erro }

class FilaItem {
  final String clientId;
  final String tipo;
  final String metodo;
  final String path;
  final Map<String, dynamic> corpo;
  final String rotulo;
  final DateTime criadoEm;
  FilaStatus status;
  String? erro;
  DateTime? enviadoEm;

  FilaItem({
    required this.clientId,
    required this.tipo,
    required this.metodo,
    required this.path,
    required this.corpo,
    required this.rotulo,
    required this.criadoEm,
    required this.status,
    this.erro,
    this.enviadoEm,
  });

  Map<String, dynamic> toJson() => {
        'client_id': clientId,
        'tipo': tipo,
        'metodo': metodo,
        'path': path,
        'corpo': corpo,
        'rotulo': rotulo,
        'criado_em': criadoEm.toIso8601String(),
        'status': status.name,
        'erro': erro,
        'enviado_em': enviadoEm?.toIso8601String(),
      };

  factory FilaItem.fromJson(Map<String, dynamic> j) => FilaItem(
        clientId: j['client_id'] as String,
        tipo: j['tipo'] as String,
        metodo: j['metodo'] as String,
        path: j['path'] as String,
        corpo: Map<String, dynamic>.from(j['corpo'] as Map),
        rotulo: j['rotulo'] as String? ?? j['tipo'] as String,
        criadoEm: DateTime.parse(j['criado_em'] as String),
        status: FilaStatus.values.firstWhere(
          (s) => s.name == j['status'],
          orElse: () => FilaStatus.pendente,
        ),
        erro: j['erro'] as String?,
        enviadoEm: j['enviado_em'] != null ? DateTime.tryParse(j['enviado_em'] as String) : null,
      );
}
