import 'package:flutter/material.dart';
import '../../data/mock_db.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

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
          const NoteText(
              'O laboratório só lança o resultado do rompimento — não decide a aceitação do lote. Este perfil não tem, e nunca vai ter, acesso a pedido, lote ou aceitação: é a única tela que existe aqui.'),
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
