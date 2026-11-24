import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/lotes_api_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

const _accent = AppColors.accentConstrutora;

class RelatorioLoteScreen extends StatefulWidget {
  final int loteId;
  final String? loteNumero;

  const RelatorioLoteScreen({super.key, required this.loteId, this.loteNumero});

  @override
  State<RelatorioLoteScreen> createState() => _RelatorioLoteScreenState();
}

class _RelatorioLoteScreenState extends State<RelatorioLoteScreen> {
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
    final r = await _repo.relatorioDoLote(widget.loteId);
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

  String _textoCompartilhar() {
    final d = _dados!;
    final lote = d['lote'] as Map<String, dynamic>;
    final buf = StringBuffer();
    buf.writeln('RELATÓRIO DE CONTROLE DO CONCRETO');
    buf.writeln('Lote ${lote['numero']} · fck projeto ${lote['fck_projeto'] ?? '—'} MPa');
    buf.writeln('Obra: ${lote['obra'] ?? '—'} · Classe: ${lote['classe'] ?? '—'}');
    buf.writeln('fck,est: ${lote['fck_est'] ?? '—'} · Aceitação: ${lote['situacao_aceitacao'] ?? 'pendente'}');
    buf.writeln('');
    buf.writeln('PEÇAS');
    for (final p in (d['pecas'] as List? ?? [])) {
      buf.writeln('- ${p['identificacao']} (${p['pavimento']}/${p['obra']})');
    }
    buf.writeln('');
    buf.writeln('CAMINHÕES');
    for (final c in (d['caminhoes'] as List? ?? [])) {
      final flags = <String>[];
      if (c['recusado'] == true) flags.add('RECUSADO');
      if (c['fora_do_prazo'] == true) flags.add('FORA DO PRAZO');
      final flag = flags.isEmpty ? '' : ' [${flags.join(', ')}]';
      buf.writeln(
        '- Nota ${c['numero_nota']} · ${c['central_nome']} · '
        'vol ${c['volume_efetivo'] ?? c['volume']} m³ · '
        '${c['situacao_prazo']}$flag',
      );
      final e = c['ensaio_abatimento'] as Map?;
      if (e != null) {
        buf.writeln('  Abatimento: ${e['medido_mm'] ?? '—'} mm · ${e['aceite']}');
      }
    }
    buf.writeln('');
    buf.writeln('EXEMPLARES');
    for (final e in (d['exemplares'] as List? ?? [])) {
      buf.writeln(
        '- ${e['idade']}d · ${e['valor'] ?? 'pendente'} MPa'
        '${e['sinalizado'] == true ? ' (incompleto)' : ''} · nota ${e['numero_nota'] ?? '—'}',
      );
    }
    buf.writeln('');
    buf.writeln(d['observacao'] ?? '');
    buf.writeln('Gerado em ${d['gerado_em']}');
    return buf.toString();
  }

  Future<void> _compartilhar() async {
    if (_dados == null) return;
    await Share.share(
      _textoCompartilhar(),
      subject: 'Relatório lote ${widget.loteNumero ?? widget.loteId}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final lote = _dados?['lote'] as Map<String, dynamic>?;
    final caminhoes = (_dados?['caminhoes'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final pecas = (_dados?['pecas'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final exemplares = (_dados?['exemplares'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final resumo = _dados?['resumo_caminhoes'] as Map<String, dynamic>?;

    return AppShell(
      title: widget.loteNumero != null
          ? 'Relatório · lote ${widget.loteNumero}'
          : 'Relatório do lote',
      accent: _accent,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? AppBanner(titulo: 'Erro', texto: _erro!, tom: BannerTom.vermelho)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PrimaryButton(
                      texto: 'Compartilhar relatório',
                      onPressed: _dados == null ? null : _compartilhar,
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView(
                        children: [
                          if (lote != null) ...[
                            Text(
                              'Lote ${lote['numero']}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                            Text(
                              'fck projeto ${lote['fck_projeto'] ?? '—'} MPa · '
                              'fck,est ${lote['fck_est'] ?? '—'} · '
                              'aceitação ${lote['situacao_aceitacao'] ?? 'pendente'}',
                              style: const TextStyle(fontSize: 13),
                            ),
                            Text(
                              'Obra: ${lote['obra'] ?? '—'} · Classe: ${lote['classe'] ?? '—'}',
                              style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                            ),
                          ],
                          if (resumo != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Caminhões: ${resumo['total']} · '
                              'no prazo ${resumo['no_prazo']} · '
                              'fora ${resumo['fora_do_prazo']} · '
                              'recusados ${resumo['recusados']}',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ],
                          const SizedBox(height: 12),
                          const Text('Peças abrangidas', style: TextStyle(fontWeight: FontWeight.w700)),
                          if (pecas.isEmpty)
                            const Text('—', style: TextStyle(color: AppColors.inkSoft))
                          else
                            for (final p in pecas)
                              Text('• ${p['identificacao']} · ${p['pavimento']} · ${p['obra']}',
                                  style: const TextStyle(fontSize: 13)),
                          const SizedBox(height: 14),
                          const Text('Caminhões', style: TextStyle(fontWeight: FontWeight.w700)),
                          for (final c in caminhoes) _cardCaminhao(c),
                          const SizedBox(height: 14),
                          const Text('Exemplares (7 e 28 dias)', style: TextStyle(fontWeight: FontWeight.w700)),
                          if (exemplares.isEmpty)
                            const Text('Nenhum exemplar ainda.', style: TextStyle(color: AppColors.inkSoft))
                          else
                            for (final e in exemplares)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  '${e['idade']} dias · ${e['valor'] ?? 'pendente'} MPa · '
                                  'nota ${e['numero_nota'] ?? '—'}'
                                  '${e['sinalizado'] == true ? ' · incompleto' : ''}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _cardCaminhao(Map<String, dynamic> c) {
    final destaque = c['destaque'] == true;
    final ensaio = c['ensaio_abatimento'] as Map<String, dynamic>?;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: destaque ? AppColors.red : AppColors.line),
        borderRadius: BorderRadius.circular(10),
        color: destaque ? AppColors.redSoft : Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nota ${c['numero_nota']} · ${c['central_nome'] ?? '—'} · ${c['placa'] ?? ''}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          Text(
            'Volume ${c['volume_efetivo'] ?? c['volume'] ?? '—'} m³ · '
            '${c['situacao_prazo']}'
            '${c['recusado'] == true ? ' · RECUSADO' : ''}'
            '${c['fora_do_prazo'] == true ? ' · FORA DO PRAZO' : ''}',
            style: const TextStyle(fontSize: 12.5),
          ),
          if (ensaio != null)
            Text(
              'Abatimento: ${ensaio['medido_mm'] ?? '—'} mm · ${ensaio['aceite']}',
              style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
            ),
        ],
      ),
    );
  }
}
