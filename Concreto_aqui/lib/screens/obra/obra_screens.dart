import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/mock_db.dart';
import '../../models/domain_models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

const _accent = AppColors.accentObra;

class HomeObraScreen extends StatelessWidget {
  const HomeObraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final abertos = MockDb.lotes.where((l) => l.status == StatusLote.aguardandoCaminhao).length;
    return AppShell(
      title: 'Obra',
      accent: _accent,
      isHome: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SessionLine(),
          MenuRow(
            titulo: 'Caminhões a receber',
            subtitulo: '$abertos lote(s) aguardando',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ObraLotesScreen())),
          ),
          const NoteText(
              'O técnico da obra recebe o caminhão, confere a nota, faz o ensaio de abatimento, molda os corpos de prova e envia ao laboratório. Não altera resultado de ensaio — isso é só do laboratório.'),
        ],
      ),
    );
  }
}

class ObraLotesScreen extends StatelessWidget {
  const ObraLotesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lotes = MockDb.lotes.where((l) => l.status == StatusLote.aguardandoCaminhao).toList();
    return AppShell(
      title: 'Caminhões a receber',
      accent: _accent,
      body: lotes.isEmpty
          ? Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(11)),
              alignment: Alignment.center,
              child: const Text('Nenhum caminhão aguardado no momento.',
                  style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5)),
            )
          : Column(
              children: lotes
                  .map((l) => MenuRow(
                        titulo: 'Lote ${l.numero}',
                        subtitulo: '${l.peca} · ${MockDb.classePorId(l.classeId).nome}',
                        onTap: () =>
                            Navigator.push(context, MaterialPageRoute(builder: (_) => ChegadaScreen(loteId: l.id))),
                      ))
                  .toList(),
            ),
    );
  }
}

class ChegadaScreen extends StatelessWidget {
  final String loteId;
  const ChegadaScreen({super.key, required this.loteId});

  @override
  Widget build(BuildContext context) {
    final l = MockDb.lotePorId(loteId);
    final cl = MockDb.classePorId(l.classeId);
    return AppShell(
      title: 'Nota de entrega',
      accent: _accent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const InfoCard(children: [
            KvRow(label: 'Nota', value: '45.820'),
            KvRow(label: 'Placa', value: 'QRZ-4C18'),
            KvRow(label: 'Cimento + água', value: '08:05'),
            KvRow(label: 'Classe na nota', value: 'C20'),
          ]),
          AppBanner(
            titulo: 'Divergência',
            texto: 'Nota veio C20; o pedido do lote ${l.numero} era ${cl.nome}. Fica registrado — não é corrigido no canteiro.',
            tom: BannerTom.ambar,
          ),
          InfoCard(children: [
            KvRow(label: 'Pedido', value: '${cl.nome} · ${cl.fck} MPa'),
            KvRow(label: 'Peça de destino', value: l.peca),
          ]),
        ],
      ),
      footer: PrimaryButton(
        texto: 'Confirmar chegada e iniciar prazo',
        onPressed: () {
          l.caminhoes.add(Caminhao(placa: 'QRZ-4C18', nota: '45.820', horaContato: '08:05', status: 'chegando'));
          Navigator.push(context, MaterialPageRoute(builder: (_) => Janela90Screen(loteId: l.id)));
        },
      ),
    );
  }
}

class Janela90Screen extends StatefulWidget {
  final String loteId;
  const Janela90Screen({super.key, required this.loteId});

  @override
  State<Janela90Screen> createState() => _Janela90ScreenState();
}

class _Janela90ScreenState extends State<Janela90Screen> {
  static const _inicio = 21 * 60; // segundos — mesmo ponto de partida do protótipo
  int _restante = _inicio;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        if (_restante > 0) _restante--;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = MockDb.lotePorId(widget.loteId);
    final m = (_restante ~/ 60).toString().padLeft(2, '0');
    final s = (_restante % 60).toString().padLeft(2, '0');
    final estourado = _restante <= 0;
    final quaseNoLimite = !estourado && _restante < _inicio * 0.25;
    final pct = (_restante / _inicio).clamp(0.0, 1.0);

    String mensagem;
    if (estourado) {
      mensagem = 'Prazo estourado. Fica marcado, não apagado.';
    } else if (quaseNoLimite) {
      mensagem = 'Restam $m min $s s — quase no limite.';
    } else {
      mensagem = 'Restam $m minutos para terminar a descarga.';
    }

    return AppShell(
      title: 'Janela de 90 minutos',
      accent: _accent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoCard(children: [
            KvRow(label: 'Lote', value: l.numero),
            const KvRow(label: 'Primeiro contato', value: '08:05'),
            const KvRow(label: 'Prazo', value: '90 min'),
          ]),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              children: [
                Text('$m:$s',
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 38,
                        fontWeight: FontWeight.w600,
                        color: estourado || quaseNoLimite ? AppColors.red : AppColors.ink)),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 8,
                    backgroundColor: const Color(0xFFEBEBE4),
                    color: estourado || quaseNoLimite ? AppColors.red : AppColors.amber,
                  ),
                ),
                const SizedBox(height: 10),
                Text(mensagem, style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
              ],
            ),
          ),
          const NoteText('O prazo estourado fica marcado no registro — não é apagado, mesmo que a descarga continue.'),
        ],
      ),
      footer: PrimaryButton(
        texto: 'Ir para o ensaio de abatimento',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SlumpScreen(loteId: l.id))),
      ),
    );
  }
}

class SlumpScreen extends StatefulWidget {
  final String loteId;
  const SlumpScreen({super.key, required this.loteId});

  @override
  State<SlumpScreen> createState() => _SlumpScreenState();
}

class _SlumpScreenState extends State<SlumpScreen> {
  final _valorCtrl = TextEditingController();
  bool? _dentroTolerancia;

  void _avaliar(String texto) {
    final l = MockDb.lotePorId(widget.loteId);
    final cl = MockDb.classePorId(l.classeId);
    final (alvo, tol) = cl.toleranciaAbatimento;
    final v = int.tryParse(texto);
    setState(() {
      _dentroTolerancia = v == null ? null : (v >= alvo - tol && v <= alvo + tol);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = MockDb.lotePorId(widget.loteId);
    final cl = MockDb.classePorId(l.classeId);
    final v = int.tryParse(_valorCtrl.text);

    Widget? resultado;
    if (v != null && _dentroTolerancia != null) {
      resultado = _dentroTolerancia!
          ? AppBanner(titulo: 'Dentro da tolerância', texto: 'Medido $v mm (pedido ${cl.abatimento}).')
          : AppBanner(titulo: 'Caminhão recusado', texto: 'Medido $v mm — fora de ${cl.abatimento}.', tom: BannerTom.vermelho);
    }

    return AppShell(
      title: 'Ensaio de abatimento',
      accent: _accent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoCard(children: [KvRow(label: 'Pedido', value: cl.abatimento)]),
          const Text('Abatimento medido (mm)',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.inkSoft)),
          const SizedBox(height: 6),
          TextField(
            controller: _valorCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'ex.: 95'),
            onChanged: _avaliar,
          ),
          const SizedBox(height: 12),
          if (resultado != null) resultado,
          const NoteText('Fora da tolerância, o caminhão volta para a central — não se corrige com água no canteiro.'),
        ],
      ),
      footer: PrimaryButton(
        texto: _dentroTolerancia == false ? 'Registrar recusa e encerrar' : 'Confirmar e seguir para a moldagem',
        perigo: _dentroTolerancia == false,
        onPressed: v == null || _dentroTolerancia == null
            ? null
            : () {
                if (_dentroTolerancia == true) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => MoldagemScreen(loteId: l.id)));
                } else {
                  l.caminhoes.last.status = 'recusado';
                  Navigator.popUntil(context, (route) => route.isFirst);
                }
              },
      ),
    );
  }
}

class MoldagemScreen extends StatelessWidget {
  final String loteId;
  const MoldagemScreen({super.key, required this.loteId});

  @override
  Widget build(BuildContext context) {
    final l = MockDb.lotePorId(loteId);
    final proximoId = MockDb.proximoNumeroCp();
    return AppShell(
      title: 'Moldagem dos corpos de prova',
      accent: _accent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoCard(children: [
            KvRow(label: 'Peça', value: l.peca),
            KvRow(label: 'Identificação', value: 'CP-2026-$proximoId'),
          ]),
          const NoteText(
              'A amostra é retirada de um caminhão. São moldados 2 corpos de prova para 7 dias e 2 para 28 dias — dois não é redundância: é o que forma o exemplar e permite descartar um mal moldado.'),
          const SizedBox(height: 10),
          const Text('Corpos de prova a moldar',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.inkSoft)),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.4,
            children: const [
              _CpSlot('7 dias · CP A'),
              _CpSlot('7 dias · CP B'),
              _CpSlot('28 dias · CP A'),
              _CpSlot('28 dias · CP B'),
            ],
          ),
        ],
      ),
      footer: PrimaryButton(
        texto: 'Confirmar moldagem',
        onPressed: () {
          l.amostras.add(Amostra(
            peca: l.peca,
            identificacao: 'CP-2026-$proximoId',
            corposDeProva: [
              CorpoProva(idade: 7),
              CorpoProva(idade: 7),
              CorpoProva(idade: 28),
              CorpoProva(idade: 28),
            ],
          ));
          Navigator.push(context, MaterialPageRoute(builder: (_) => EnvioLabScreen(loteId: l.id)));
        },
      ),
    );
  }
}

class _CpSlot extends StatelessWidget {
  final String rotulo;
  const _CpSlot(this.rotulo);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(9)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(rotulo, style: const TextStyle(fontSize: 10.5, color: AppColors.inkSoft)),
          const SizedBox(height: 4),
          const Text('em cura', style: TextStyle(fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class EnvioLabScreen extends StatelessWidget {
  final String loteId;
  const EnvioLabScreen({super.key, required this.loteId});

  @override
  Widget build(BuildContext context) {
    final l = MockDb.lotePorId(loteId);
    return AppShell(
      title: 'Envio ao laboratório',
      accent: _accent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppBanner(titulo: 'Corpos de prova moldados', texto: 'Identificados e rastreados até ${l.peca}.'),
          const NoteText('Ao enviar, os corpos de prova entram na fila do laboratório e o lote passa a aguardar os resultados do rompimento.'),
        ],
      ),
      footer: PrimaryButton(
        texto: 'Enviar ao laboratório',
        onPressed: () {
          l.status = StatusLote.aguardandoResultados;
          Navigator.popUntil(context, (route) => route.isFirst);
        },
      ),
    );
  }
}
