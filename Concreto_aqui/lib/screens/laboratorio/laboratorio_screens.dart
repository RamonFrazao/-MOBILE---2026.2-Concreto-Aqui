import 'package:concreto_aqui/models/domain_models.dart';
import 'package:flutter/material.dart';
import '../../data/mock_db.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';
import '../shared/corpo_prova_screens.dart';
import '../../services/amostras_repository.dart';

const _accent = AppColors.accentLaboratorio;

class HomeLaboratorioScreen extends StatelessWidget {
  const HomeLaboratorioScreen({super.key});

  int _pendentes() {
    var n = 0;
    for (final l in MockDb.lotes) {
      for (final am in l.amostras) {
        for (final idade in [7, 28]) {
          final temIdade = am.corposDeProva.any((c) => c.idade == idade);
          if (temIdade && am.valorExemplar(idade) == null) n++;
        }
      }
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Laboratório',
      accent: _accent,
      isHome: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SessionLine(),
          MenuRow(
            titulo: 'Corpos de prova recebidos',
            subtitulo: '${_pendentes()} exemplar(es) pendente(s)',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LabListaScreen())),
          ),
          MenuRow(
            titulo: 'Consultar por identificação',
            subtitulo: 'CP-AAAA-NNNNN → peça, lote, caminhão e nota',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ConsultaCorpoProvaScreen(accent: _accent),
              ),
            ),
          ),
          MenuRow(
            titulo: 'Remessas recebidas',
            subtitulo: 'Corpos de prova enviados pela obra',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LabRemessasScreen()),
            ),
          ),
          const NoteText(
              'O laboratório só lança o resultado do rompimento — não decide a aceitação do lote. A consulta pela identificação do corpo de prova está disponível para localizar a peça de origem.'),
        ],
      ),
    );
  }
}

class LabListaScreen extends StatelessWidget {
  const LabListaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final linhas = <Widget>[];
    for (final l in MockDb.lotes) {
      for (var i = 0; i < l.amostras.length; i++) {
        final am = l.amostras[i];
        final pend7 = am.valorExemplar(7) == null && am.corposDeProva.any((c) => c.idade == 7);
        final pend28 = am.valorExemplar(28) == null && am.corposDeProva.any((c) => c.idade == 28);
        if (pend7 || pend28) {
          linhas.add(MenuRow(
            titulo: am.identificacao,
            subtitulo: 'Lote ${l.numero} · ${am.peca}',
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => LabLancarScreen(loteId: l.id, amostraIndex: i))),
          ));
        }
      }
    }

    return AppShell(
      title: 'Corpos de prova',
      accent: _accent,
      body: linhas.isEmpty
          ? Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(11)),
              alignment: Alignment.center,
              child: const Text('Nenhum corpo de prova aguardando lançamento.',
                  style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5)),
            )
          : Column(children: linhas),
    );
  }
}

class LabLancarScreen extends StatefulWidget {
  final String loteId;
  final int amostraIndex;
  const LabLancarScreen({super.key, required this.loteId, required this.amostraIndex});

  @override
  State<LabLancarScreen> createState() => _LabLancarScreenState();
}

class _LabLancarScreenState extends State<LabLancarScreen> {
  final Map<int, TextEditingController> _controllers = {};

  TextEditingController _ctrlFor(int index) =>
      _controllers.putIfAbsent(index, () => TextEditingController());

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = MockDb.lotePorId(widget.loteId);
    final am = l.amostras[widget.amostraIndex];
    final cps7 = am.corposDeProva.where((c) => c.idade == 7).toList();
    final cps28 = am.corposDeProva.where((c) => c.idade == 28).toList();

    Widget grid(List<dynamic> cps, int offset) {
      return GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.2,
        children: List.generate(cps.length, (i) {
          final cp = cps[i];
          final idxGlobal = offset + i;
          final letra = i == 0 ? 'A' : 'B';
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(9)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${cp.idade} dias · CP $letra', style: const TextStyle(fontSize: 10.5, color: AppColors.inkSoft)),
                const SizedBox(height: 4),
                cp.resultado != null
                    ? Text('${cp.resultado} MPa',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.w600))
                    : SizedBox(
                        height: 26,
                        child: TextField(
                          controller: _ctrlFor(idxGlobal),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                          decoration: const InputDecoration(hintText: 'MPa', isDense: true, contentPadding: EdgeInsets.zero, border: InputBorder.none),
                        ),
                      ),
              ],
            ),
          );
        }),
      );
    }

    return AppShell(
      title: 'Lançar rompimento',
      accent: _accent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoCard(children: [
            KvRow(label: 'Lote', value: l.numero),
            KvRow(label: 'Peça', value: am.peca),
          ]),
          const Text('7 dias — alerta, não decide',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.inkSoft)),
          const SizedBox(height: 8),
          grid(cps7, 0),
          const SizedBox(height: 14),
          const Text('28 dias — decide a aceitação',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.inkSoft)),
          const SizedBox(height: 8),
          grid(cps28, cps7.length),
        ],
      ),
      footer: PrimaryButton(
        texto: 'Salvar resultados',
        onPressed: () {
          final todosCps = [...cps7, ...cps28];
          for (var i = 0; i < todosCps.length; i++) {
            final ctrl = _controllers[i];
            if (ctrl != null && ctrl.text.trim().isNotEmpty) {
              final v = double.tryParse(ctrl.text.trim());
              if (v != null) todosCps[i].resultado = v;
            }
          }
          if (am.valorExemplar(28) != null) {
            l.status = StatusLote.aguardandoAceitacao;
          }
          Navigator.pop(context);
        },
      ),
    );
  }
}


class LabRemessasScreen extends StatefulWidget {
  const LabRemessasScreen({super.key});

  @override
  State<LabRemessasScreen> createState() => _LabRemessasScreenState();
}

class _LabRemessasScreenState extends State<LabRemessasScreen> {
  final _repo = AmostrasRepository();
  bool _loading = true;
  String? _erro;
  List<Map<String, dynamic>> _itens = [];

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
    final r = await _repo.listarRemessas();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _itens = r.dados ?? [];
      } else {
        _erro = r.erro;
      }
    });
  }

  Future<void> _receber(int id) async {
    final r = await _repo.receberRemessa(id);
    if (!mounted) return;
    if (r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Remessa recebida. Corpos de prova no laboratório.')),
      );
      _carregar();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.erro ?? 'Erro')));
    }
  }


  Future<void> _abrirRemessa(Map<String, dynamic> r) async {
    final id = r['id'] as int;
    if (r['status'] == 'enviada') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Receber remessa?'),
          content: Text('Confirmar recebimento da remessa #$id no laboratório.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Receber')),
          ],
        ),
      );
      if (ok == true) await _receber(id);
    }
    final det = await _repo.buscarRemessa(id);
    if (!mounted) return;
    if (!det.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(det.erro ?? 'Erro')));
      return;
    }
    final corpos = (det.dados?['corpos_prova'] as List?) ?? [];
    if (corpos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Remessa sem corpos de prova.')),
      );
      return;
    }
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Corpos da remessa')),
            for (final c in corpos)
              ListTile(
                title: Text('${c['identificacao']} · ${c['idade']} dias'),
                subtitle: Text(c['resultado'] != null ? '${c['resultado']} MPa' : (c['situacao'] as String? ?? '')),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LancarResultadoScreen(corpoProvaId: c['id'] as int),
                    ),
                  ).then((_) => _carregar());
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Remessas',
      accent: _accent,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? AppBanner(titulo: 'Erro', texto: _erro!, tom: BannerTom.vermelho)
              : _itens.isEmpty
                  ? const Text('Nenhuma remessa disponível.', style: TextStyle(color: AppColors.inkSoft))
                  : Column(
                      children: [

                        for (final r in _itens)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: MenuRow(
                              titulo: 'Remessa #${r['id']} · ${r['status']}',
                              subtitulo:
                                  '${r['qtd_corpos'] ?? 0} corpo(s) · ${r['enviada_em'] ?? ''}',
                              onTap: () => _abrirRemessa(r),
                            ),
                          ),
                      ],
                    ),
    );
  }
}


class LancarResultadoScreen extends StatefulWidget {
  final int corpoProvaId;
  const LancarResultadoScreen({super.key, required this.corpoProvaId});

  @override
  State<LancarResultadoScreen> createState() => _LancarResultadoScreenState();
}

class _LancarResultadoScreenState extends State<LancarResultadoScreen> {
  final _repo = AmostrasRepository();
  final _mpaCtrl = TextEditingController();
  final _motivoCtrl = TextEditingController();
  bool _loading = true;
  bool _salvando = false;
  String? _erro;
  Map<String, dynamic>? _dados;
  DateTime _rompidoEm = DateTime.now();

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _mpaCtrl.dispose();
    _motivoCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    final r = await _repo.corpoParaRompimento(widget.corpoProvaId);
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

  Future<void> _salvar() async {
    final mpa = num.tryParse(_mpaCtrl.text.trim().replaceAll(',', '.'));
    if (mpa == null || mpa <= 0) {
      setState(() => _erro = 'Informe a resistência em MPa.');
      return;
    }
    final temResultado = _dados?['resultado_vigente'] != null;
    if (temResultado && _motivoCtrl.text.trim().length < 3) {
      setState(() => _erro = 'Correção exige motivo (novo lançamento, sem apagar o anterior).');
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
    final r = await _repo.lancarResultado(
      corpoProvaId: widget.corpoProvaId,
      rompidoEm: _rompidoEm,
      resistenciaMpa: mpa,
      idadeRealDias: (_dados?['idade_real_sugerida_dias'] as num?),
      motivoCorrecao: temResultado ? _motivoCtrl.text.trim() : null,
    );
    if (!mounted) return;
    setState(() => _salvando = false);
    if (r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Resultado gravado. A obra verá ao sincronizar.')),
      );
      Navigator.pop(context, true);
    } else {
      setState(() => _erro = r.erro);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _dados;
    final hist = (d?['historico'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return AppShell(
      title: 'Lançar rompimento',
      accent: _accent,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : d == null
              ? AppBanner(titulo: 'Erro', texto: _erro ?? 'Falha ao carregar', tom: BannerTom.vermelho)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(d['identificacao'] as String? ?? '—',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                      'Idade nominal: ${d['idade_nominal']} dias · '
                      'Idade real sugerida: ${d['idade_real_sugerida_dias'] ?? '—'} dias '
                      '(a partir da moldagem ${d['moldado_em'] ?? '—'})',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                    ),
                    Text(
                      'Lote ${d['lote_numero'] ?? '—'} · Nota ${d['numero_nota'] ?? '—'} · ${d['placa'] ?? ''}',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                    ),
                    if (d['resultado_vigente'] != null) ...[
                      const SizedBox(height: 8),
                      AppBanner(
                        titulo: 'Já existe resultado (${d['resultado_vigente']} MPa)',
                        texto: 'A correção será um novo lançamento, com motivo, sem apagar o anterior.',
                        tom: BannerTom.ambar,
                      ),
                    ],
                    const SizedBox(height: 14),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Data/hora do rompimento'),
                      subtitle: Text(_rompidoEm.toLocal().toString()),
                      trailing: const Icon(Icons.event),
                      onTap: () async {
                        final data = await showDatePicker(
                          context: context,
                          initialDate: _rompidoEm,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (data == null || !mounted) return;
                        final hora = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(_rompidoEm),
                        );
                        if (hora == null || !mounted) return;
                        setState(() {
                          _rompidoEm = DateTime(data.year, data.month, data.day, hora.hour, hora.minute);
                        });
                      },
                    ),
                    TextField(
                      controller: _mpaCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Resistência (MPa)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (d['resultado_vigente'] != null) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _motivoCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Motivo da correção',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    if (_erro != null) ...[
                      const SizedBox(height: 8),
                      Text(_erro!, style: const TextStyle(color: AppColors.red)),
                    ],
                    const SizedBox(height: 12),
                    PrimaryButton(
                      texto: _salvando ? 'Gravando…' : 'Gravar resultado',
                      onPressed: _salvando ? null : _salvar,
                    ),
                    if (hist.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text('Histórico de lançamentos',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                      for (final h in hist)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${h['resistencia_mpa']} MPa · idade real ${h['idade_real_dias']} d · ${h['rompido_em']}'
                            '${h['motivo_correcao'] != null ? ' · correção: ${h['motivo_correcao']}' : ''}',
                            style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
                          ),
                        ),
                    ],
                  ],
                ),
    );
  }
}
