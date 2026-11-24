import 'package:flutter/material.dart';
import '../../services/lotes_api_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

const _accent = AppColors.accentConstrutora;

/// Lista exemplares do lote por idade.
/// Cálculo no servidor: maior valor entre os dois CPs — nunca a média.
class ExemplaresLoteScreen extends StatefulWidget {
  final int loteId;
  final String? loteNumero;

  const ExemplaresLoteScreen({super.key, required this.loteId, this.loteNumero});

  @override
  State<ExemplaresLoteScreen> createState() => _ExemplaresLoteScreenState();
}

class _ExemplaresLoteScreenState extends State<ExemplaresLoteScreen> {
  final _repo = LotesApiRepository();
  bool _loading = true;
  String? _erro;
  Map<String, dynamic>? _dados;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    final r = await _repo.exemplaresDoLote(widget.loteId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _dados = r.dados;
      } else {
        _erro = r.erro;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lote = _dados?['lote'] as Map<String, dynamic>?;
    final exemplares = (_dados?['exemplares'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final porIdade = _dados?['por_idade'] as Map<String, dynamic>? ?? {};

    final titulo = widget.loteNumero != null
        ? 'Exemplares · lote ${widget.loteNumero}'
        : (lote != null ? 'Exemplares · lote ${lote['numero']}' : 'Exemplares do lote');

    return AppShell(
      title: titulo,
      accent: _accent,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? AppBanner(titulo: 'Erro', texto: _erro!, tom: BannerTom.vermelho)
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    children: [
                      if (lote?['fck_projeto'] != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'fck projeto: ${lote!['fck_projeto']} MPa',
                            style: const TextStyle(fontSize: 13, color: AppColors.inkSoft),
                          ),
                        ),
                      if (exemplares.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'Nenhum corpo de prova neste lote ainda.',
                            style: TextStyle(color: AppColors.inkSoft),
                          ),
                        )
                      else
                        ..._secoesPorIdade(porIdade, exemplares),
                    ],
                  ),
                ),
    );
  }

  List<Widget> _secoesPorIdade(Map<String, dynamic> porIdade, List<Map<String, dynamic>> todos) {
    final idades = porIdade.keys.map((k) => int.tryParse(k) ?? 0).toList()..sort();
    if (idades.isEmpty) {
      // fallback: agrupa localmente só para exibição (valores já vieram do servidor)
      final map = <int, List<Map<String, dynamic>>>{};
      for (final e in todos) {
        final idade = e['idade'] as int? ?? 0;
        map.putIfAbsent(idade, () => []).add(e);
      }
      return [
        for (final idade in map.keys.toList()..sort()) ...[
          _tituloIdade(idade),
          for (final e in map[idade]!) _ExemplarCard(e),
        ],
      ];
    }
    return [
      for (final idade in idades) ...[
        _tituloIdade(idade),
        for (final e in (porIdade[idade.toString()] as List).cast<Map<String, dynamic>>()) _ExemplarCard(e),
      ],
    ];
  }

  Widget _tituloIdade(int idade) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Text(
        'Idade nominal: $idade dias',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.inkSoft),
      ),
    );
  }
}

class _ExemplarCard extends StatelessWidget {
  final Map<String, dynamic> e;
  const _ExemplarCard(this.e);

  @override
  Widget build(BuildContext context) {
    final valor = e['valor'];
    final incompleto = e['sinalizado'] == true || e['incompleto'] == true;
    final pendente = e['pendente'] == true || valor == null;
    final corpos = (e['corpos'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final nota = e['numero_nota'] as String? ?? '—';
    final placa = e['placa'] as String? ?? '';

    Color borda = AppColors.line;
    if (!pendente && incompleto) borda = AppColors.amber;
    if (!pendente && !incompleto) borda = AppColors.green;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: borda),
        borderRadius: BorderRadius.circular(11),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Amostra · nota $nota${placa.isNotEmpty ? ' · $placa' : ''}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
              if (pendente)
                const StatusBadge(texto: 'pendente', cor: AppColors.inkSoft, fundo: AppColors.line)
              else if (incompleto)
                const StatusBadge(texto: 'incompleto', cor: Color(0xFF7A551A), fundo: AppColors.amberSoft)
              else
                StatusBadge(
                  texto: '${_fmt(valor)} MPa',
                  cor: const Color(0xFF245A3E),
                  fundo: AppColors.greenSoft,
                ),
            ],
          ),
          if (!pendente && valor != null) ...[
            const SizedBox(height: 6),
            Text(
              'Exemplar: ${_fmt(valor)} MPa',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ],
          if (incompleto && !pendente)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Um corpo foi descartado ou falta resultado: usou-se o que restou.',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF7A551A)),
              ),
            ),
          const SizedBox(height: 8),
          const Text('Corpos de prova', style: TextStyle(fontSize: 11, color: AppColors.inkSoft)),
          const SizedBox(height: 4),
          for (final c in corpos) _linhaCorpo(c),
        ],
      ),
    );
  }

  Widget _linhaCorpo(Map<String, dynamic> c) {
    final usado = c['usado_no_exemplar'] == true;
    final descartado = c['descartado'] == true || c['situacao'] == 'descartado';
    final res = c['resultado'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            usado ? Icons.check_circle : (descartado ? Icons.block : Icons.circle_outlined),
            size: 16,
            color: usado
                ? AppColors.green
                : (descartado ? AppColors.red : AppColors.inkSoft),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${c['identificacao'] ?? '—'}'
              '${res != null ? ' · ${_fmt(res)} MPa' : ' · sem resultado'}'
              '${descartado ? ' · descartado' : ''}'
              '${usado ? ' · usado no exemplar' : ''}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: usado ? FontWeight.w700 : FontWeight.w400,
                color: descartado ? AppColors.inkSoft : AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(dynamic v) {
    if (v == null) return '—';
    final n = v is num ? v : num.tryParse(v.toString());
    if (n == null) return v.toString();
    return n.toStringAsFixed(1).replaceAll('.', ',');
  }
}
