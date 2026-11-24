import 'package:flutter/material.dart';
import '../../services/lotes_api_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

const _accent = AppColors.accentConstrutora;

class AceitacaoLoteScreen extends StatefulWidget {
  final int loteId;
  final String? loteNumero;

  const AceitacaoLoteScreen({super.key, required this.loteId, this.loteNumero});

  @override
  State<AceitacaoLoteScreen> createState() => _AceitacaoLoteScreenState();
}

class _AceitacaoLoteScreenState extends State<AceitacaoLoteScreen> {
  final _repo = LotesApiRepository();
  bool _loading = true;
  bool _salvando = false;
  String? _erro;
  Map<String, dynamic>? _dados;
  String? _decisao;

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
    final r = await _repo.aceitacaoDoLote(widget.loteId);
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

  Future<void> _confirmar() async {
    final veredito = _dados?['veredito_sugerido'] as String?;
    if (veredito == 'reprovado' && _decisao == null) {
      setState(() => _erro = 'Lote reprovado exige a decisão do engenheiro.');
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
    final r = await _repo.confirmarAceitacao(
      widget.loteId,
      decisao: veredito == 'reprovado' ? _decisao : null,
    );
    if (!mounted) return;
    setState(() => _salvando = false);
    if (r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lote ${r.dados?['situacao_aceitacao']}.')),
      );
      await _carregar();
    } else {
      setState(() => _erro = r.erro);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lote = _dados?['lote'] as Map<String, dynamic>?;
    final calc = _dados?['calculo'] as Map<String, dynamic>?;
    final exemplares = (_dados?['exemplares_28'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final alertas7 = (_dados?['alertas_7_dias'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final veredito = _dados?['veredito_sugerido'] as String?;
    final ja = lote?['situacao_aceitacao'] as String?;

    return AppShell(
      title: widget.loteNumero != null
          ? 'Aceitação · lote ${widget.loteNumero}'
          : 'Aceitação do lote',
      accent: _accent,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _erro != null && _dados == null
              ? AppBanner(titulo: 'Erro', texto: _erro!, tom: BannerTom.vermelho)
              : ListView(
                  children: [
                    if (lote != null) ...[
                      Text(
                        'fck projeto: ${lote['fck_projeto'] ?? '—'} MPa · '
                        'condição de preparo: ${lote['condicao_preparo'] ?? 'A'}',
                        style: const TextStyle(fontSize: 13, color: AppColors.inkSoft),
                      ),
                      if (ja != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: AppBanner(
                            titulo: 'Lote $ja',
                            texto: 'fck,est gravado: ${lote['fck_est_gravado'] ?? '—'} MPa'
                                '${lote['aceitacao_em'] != null ? ' · ${lote['aceitacao_em']}' : ''}',
                            tom: ja == 'aceito' ? BannerTom.verde : BannerTom.vermelho,
                          ),
                        ),
                    ],
                    const SizedBox(height: 12),
                    const Text('Exemplares de 28 dias (ordenados no servidor)',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 6),
                    if (exemplares.isEmpty)
                      const Text('Nenhum exemplar de 28 dias com resultado.',
                          style: TextStyle(color: AppColors.inkSoft))
                    else
                      for (final e in exemplares)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '${e['valor']} MPa · nota ${e['numero_nota'] ?? '—'}'
                            '${e['sinalizado'] == true ? ' · incompleto' : ''}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                    if (calc != null && calc['ok'] == true) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.greenSoft,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'fck,est = ${calc['fck_est']} MPa',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                            ),
                            Text(
                              'n = ${calc['n']} · Ψ6 = ${calc['psi6']} · '
                              'regra ${calc['regra']} · piso Ψ6·f1 = ${calc['minimo_psi']} MPa',
                              style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
                            ),
                            if (calc['ordenados'] is List)
                              Text(
                                'Ordenados: ${(calc['ordenados'] as List).join(', ')}',
                                style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
                              ),
                          ],
                        ),
                      ),
                      if (veredito != null) ...[
                        const SizedBox(height: 8),
                        AppBanner(
                          titulo: veredito == 'aceito' ? 'Sugestão: ACEITO' : 'Sugestão: REPROVADO',
                          texto: veredito == 'aceito'
                              ? 'fck,est ≥ fck de projeto.'
                              : 'fck,est abaixo do fck de projeto. Registre a decisão do engenheiro.',
                          tom: veredito == 'aceito' ? BannerTom.verde : BannerTom.vermelho,
                        ),
                      ],
                    ] else if (calc != null && calc['ok'] != true) ...[
                      const SizedBox(height: 8),
                      AppBanner(
                        titulo: 'Cálculo indisponível',
                        texto: calc['erro'] as String? ?? 'Não foi possível calcular o fck,est.',
                        tom: BannerTom.ambar,
                      ),
                    ],
                    if (alertas7.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const Text('Alerta — 7 dias (não julga o lote)',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(height: 4),
                      for (final a in alertas7)
                        Text(
                          '${a['valor'] ?? 'pendente'} · nota ${a['numero_nota'] ?? '—'}',
                          style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                        ),
                    ],
                    if (ja == null && veredito == 'reprovado') ...[
                      const SizedBox(height: 14),
                      const Text('Decisão do engenheiro', style: TextStyle(fontWeight: FontWeight.w600)),
                      for (final opt in [
                        ('revisao_projeto', 'Revisão de projeto'),
                        ('extracao_testemunhos', 'Extração de testemunhos'),
                        ('prova_de_carga', 'Prova de carga'),
                        ('outra', 'Outra'),
                      ])
                        RadioListTile<String>(
                          dense: true,
                          title: Text(opt.$2, style: const TextStyle(fontSize: 13)),
                          value: opt.$1,
                          groupValue: _decisao,
                          onChanged: (v) => setState(() => _decisao = v),
                        ),
                    ],
                    if (_erro != null) ...[
                      const SizedBox(height: 8),
                      Text(_erro!, style: const TextStyle(color: AppColors.red)),
                    ],
                    if (ja == null && calc != null && calc['ok'] == true) ...[
                      const SizedBox(height: 12),
                      PrimaryButton(
                        texto: _salvando
                            ? 'Gravando…'
                            : (veredito == 'aceito' ? 'Confirmar aceitação' : 'Registrar reprovação'),
                        onPressed: _salvando ? null : _confirmar,
                      ),
                    ],
                  ],
                ),
    );
  }
}
