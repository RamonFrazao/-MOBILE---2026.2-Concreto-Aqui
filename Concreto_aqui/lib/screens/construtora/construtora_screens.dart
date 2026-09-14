import 'package:flutter/material.dart';
import '../../data/mock_db.dart';
import '../../models/domain_models.dart';
import '../../services/lote_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

const _accent = AppColors.accentConstrutora;

class HomeConstrutoraScreen extends StatelessWidget {
  const HomeConstrutoraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pendentes =
        MockDb.lotes.where((l) => l.status == StatusLote.aguardandoAceitacao).length;
    return AppShell(
      title: 'Construtora',
      accent: _accent,
      isHome: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SessionLine(),
          MenuRow(
            titulo: 'Obras e peças',
            subtitulo: 'Pavimentos e peças de destino',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ObrasPecasScreen())),
          ),
          MenuRow(
            titulo: 'Centrais e laboratórios',
            subtitulo: 'Cadastro de fornecedores',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CadastrosScreen())),
          ),
          MenuRow(
            titulo: 'Classes de concreto',
            subtitulo: 'fck, abatimento, agregado',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClassesScreen())),
          ),
          MenuRow(
            titulo: 'Pedidos e lotes',
            subtitulo: '${MockDb.lotes.length} registrados',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LotesScreen())),
          ),
          MenuRow(
            titulo: 'Aceitação de lotes',
            subtitulo: pendentes > 0 ? '$pendentes aguardando decisão' : 'nenhum pendente',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AceitacaoScreen())),
          ),
        ],
      ),
    );
  }
}

class ObrasPecasScreen extends StatefulWidget {
  const ObrasPecasScreen({super.key});

  @override
  State<ObrasPecasScreen> createState() => _ObrasPecasScreenState();
}

class _ObrasPecasScreenState extends State<ObrasPecasScreen> {
  final _novaPecaCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Obras e peças',
      accent: _accent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoCard(children: [
            KvRow(label: 'Obra', value: MockDb.nomeObra),
            KvRow(label: 'Pavimento', value: MockDb.pavimento),
          ]),
          const Text('Peças cadastradas',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.inkSoft)),
          const SizedBox(height: 8),
          ...MockDb.pecas.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.line),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(p, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                ),
              )),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _novaPecaCtrl,
                  decoration: const InputDecoration(hintText: 'ex.: Viga V-04'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  final v = _novaPecaCtrl.text.trim();
                  if (v.isEmpty) return;
                  setState(() {
                    MockDb.pecas.add(v);
                    _novaPecaCtrl.clear();
                  });
                },
                child: const Text('Adicionar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class CadastrosScreen extends StatelessWidget {
  const CadastrosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Centrais e laboratórios',
      accent: _accent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Centrais',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.inkSoft)),
          const SizedBox(height: 8),
          ...MockDb.centrais.map((c) => _linhaSimples(c)),
          const SizedBox(height: 16),
          const Text('Laboratórios',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.inkSoft)),
          const SizedBox(height: 8),
          ...MockDb.laboratorios.map((c) => _linhaSimples(c)),
          const NoteText('A central de concreto é apenas cadastro — não tem acesso ao aplicativo.'),
        ],
      ),
    );
  }

  Widget _linhaSimples(String texto) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(11)),
        child: Text(texto, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
      );
}

class ClassesScreen extends StatefulWidget {
  const ClassesScreen({super.key});

  @override
  State<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends State<ClassesScreen> {
  final _nomeCtrl = TextEditingController();
  final _fckCtrl = TextEditingController();
  final _abatCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Classes de concreto',
      accent: _accent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...MockDb.classes.map((c) => InfoCard(children: [
                KvRow(label: 'Classe', value: '${c.nome} · ${c.fck} MPa'),
                KvRow(label: 'Abatimento', value: c.abatimento),
                KvRow(label: 'Agregado', value: c.agregado),
              ])),
          const SizedBox(height: 8),
          const Text('Nova classe',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.inkSoft)),
          const SizedBox(height: 8),
          TextField(controller: _nomeCtrl, decoration: const InputDecoration(hintText: 'ex.: C35')),
          const SizedBox(height: 8),
          TextField(controller: _fckCtrl, decoration: const InputDecoration(hintText: 'fck de projeto (MPa)')),
          const SizedBox(height: 8),
          TextField(controller: _abatCtrl, decoration: const InputDecoration(hintText: '80 ± 20 mm')),
          const SizedBox(height: 10),
          PrimaryButton(
            texto: 'Adicionar classe',
            onPressed: () {
              final nome = _nomeCtrl.text.trim();
              final fck = int.tryParse(_fckCtrl.text.trim());
              final abat = _abatCtrl.text.trim().isEmpty ? '—' : _abatCtrl.text.trim();
              if (nome.isEmpty || fck == null) return;
              setState(() {
                MockDb.classes.add(ClasseConcreto(
                  id: 'c${DateTime.now().millisecondsSinceEpoch}',
                  nome: nome,
                  fck: fck,
                  abatimento: abat,
                  agregado: '19 mm',
                ));
                _nomeCtrl.clear();
                _fckCtrl.clear();
                _abatCtrl.clear();
              });
            },
          ),
        ],
      ),
    );
  }
}

class LotesScreen extends StatefulWidget {
  const LotesScreen({super.key});

  @override
  State<LotesScreen> createState() => _LotesScreenState();
}

class _LotesScreenState extends State<LotesScreen> {
  final _numeroCtrl = TextEditingController();
  final _pecaCtrl = TextEditingController();
  final _volumeCtrl = TextEditingController();
  final _buscaCtrl = TextEditingController();
  final _loteRepository = LoteRepository();
  String? _erroBusca;
  Map<String, dynamic>? _loteEncontrado;
  bool _buscando = false;

  Future<void> _buscar() async {
    setState(() {
      _buscando = true;
      _erroBusca = null;
      _loteEncontrado = null;
    });
    // Esta busca vai na API de verdade — é o servidor quem decide se o
    // lote pedido é desta construtora ou não, não o app.
    final resultado = await _loteRepository.buscarPorCodigo(_buscaCtrl.text.trim());
    if (!mounted) return;
    setState(() {
      _buscando = false;
      if (resultado.ok) {
        _loteEncontrado = resultado.lote;
      } else {
        _erroBusca = resultado.erro;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Pedidos e lotes',
      accent: _accent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...MockDb.lotes.map((l) {
            final st = statusInfoFor(l.status);
            final cl = MockDb.classePorId(l.classeId);
            return MenuRow(
              titulo: 'Lote ${l.numero} · ${l.peca}',
              subtitulo: '${cl.nome} · ${l.volume} m³',
              trailing: StatusBadge(texto: st.label, cor: st.cor, fundo: st.fundo),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LoteDetalheScreen(loteId: l.id))),
            );
          }),
          const SizedBox(height: 8),
          const Text('Novo pedido',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.inkSoft)),
          const SizedBox(height: 8),
          TextField(controller: _numeroCtrl, decoration: const InputDecoration(hintText: 'ex.: 20/03')),
          const SizedBox(height: 8),
          TextField(controller: _pecaCtrl, decoration: const InputDecoration(hintText: 'ex.: Viga V-04')),
          const SizedBox(height: 8),
          TextField(controller: _volumeCtrl, decoration: const InputDecoration(hintText: 'Volume (m³)')),
          const SizedBox(height: 10),
          PrimaryButton(
            texto: 'Abrir lote',
            onPressed: () {
              final numero = _numeroCtrl.text.trim();
              final peca = _pecaCtrl.text.trim();
              final volume = double.tryParse(_volumeCtrl.text.trim()) ?? 0;
              if (numero.isEmpty || peca.isEmpty) return;
              setState(() {
                MockDb.lotes.add(Lote(
                  id: 'l${DateTime.now().millisecondsSinceEpoch}',
                  numero: numero,
                  peca: peca,
                  classeId: MockDb.classes.first.id,
                  volume: volume,
                  caminhoesPlanejados: 1,
                  status: StatusLote.aguardandoCaminhao,
                ));
                _numeroCtrl.clear();
                _pecaCtrl.clear();
                _volumeCtrl.clear();
              });
            },
          ),
          const SizedBox(height: 20),
          const Text('Buscar lote por código (via API)',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.inkSoft)),
          const SizedBox(height: 8),
          TextField(controller: _buscaCtrl, decoration: const InputDecoration(hintText: 'ex.: 19/07')),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _buscando ? null : _buscar,
            child: _buscando
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Buscar'),
          ),
          if (_erroBusca != null) AppBanner(titulo: 'Não foi possível abrir', texto: _erroBusca!, tom: BannerTom.vermelho),
          if (_loteEncontrado != null)
            InfoCard(children: [
              KvRow(label: 'Lote', value: '${_loteEncontrado!['numero']}'),
              KvRow(label: 'Peça', value: '${_loteEncontrado!['peca']}'),
              KvRow(label: 'Status', value: '${_loteEncontrado!['status']}'),
            ]),
          const NoteText(
              'Esta busca fala com a API de verdade. Logado como esta construtora, tente 12/03 ou 14/03 (seus) e depois 19/07 (de outra construtora, no seed) para ver a recusa.'),
        ],
      ),
    );
  }
}

class LoteDetalheScreen extends StatelessWidget {
  final String loteId;
  const LoteDetalheScreen({super.key, required this.loteId});

  @override
  Widget build(BuildContext context) {
    final l = MockDb.lotePorId(loteId);
    final cl = MockDb.classePorId(l.classeId);
    final st = statusInfoFor(l.status);

    Widget corpo;
    if (l.status == StatusLote.aceito || l.status == StatusLote.reprovado) {
      final fckEst = l.calcularFckEst();
      corpo = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoCard(children: [
            KvRow(label: 'Exemplares (28 dias)', value: '${l.amostras.length}'),
            KvRow(label: 'fck de projeto', value: '${cl.fck} MPa'),
            KvRow(label: 'fck,est', value: fckEst != null ? '$fckEst MPa' : '—'),
          ]),
          if (l.amostras.isNotEmpty)
            NoteText('Amostra de referência: ${l.amostras.first.identificacao} (${l.amostras.first.peca}).'),
        ],
      );
    } else if (l.caminhoes.isNotEmpty) {
      corpo = const NoteText('Aguardando o técnico da obra concluir o recebimento do caminhão e a moldagem dos corpos de prova.');
    } else {
      corpo = const NoteText('Aguardando o técnico da obra registrar a chegada do caminhão. A construtora não executa etapas de campo.');
    }

    return AppShell(
      title: 'Lote ${l.numero}',
      accent: _accent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoCard(children: [
            KvRow(label: 'Lote', value: l.numero),
            KvRow(label: 'Peça', value: l.peca),
            KvRow(label: 'Classe', value: '${cl.nome} · ${cl.fck} MPa'),
            KvRow(label: 'Volume', value: '${l.volume} m³'),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Status', style: TextStyle(color: AppColors.inkSoft, fontSize: 13)),
                  StatusBadge(texto: st.label, cor: st.cor, fundo: st.fundo),
                ],
              ),
            ),
          ]),
          corpo,
        ],
      ),
    );
  }
}

class AceitacaoScreen extends StatelessWidget {
  const AceitacaoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pendentes = MockDb.lotes.where((l) => l.status == StatusLote.aguardandoAceitacao).toList();
    final decididos =
        MockDb.lotes.where((l) => l.status == StatusLote.aceito || l.status == StatusLote.reprovado).toList();

    return AppShell(
      title: 'Aceitação de lotes',
      accent: _accent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Aguardando decisão',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.inkSoft)),
          const SizedBox(height: 8),
          if (pendentes.isEmpty)
            _vazio('Nenhum lote aguardando aceitação no momento.')
          else
            ...pendentes.map((l) => MenuRow(
                  titulo: 'Lote ${l.numero}',
                  subtitulo: l.peca,
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => AceitacaoDetalheScreen(loteId: l.id))),
                )),
          const SizedBox(height: 16),
          const Text('Histórico',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.inkSoft)),
          const SizedBox(height: 8),
          ...decididos.map((l) => MenuRow(
                titulo: 'Lote ${l.numero}',
                subtitulo: l.peca,
                onTap: () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => LoteDetalheScreen(loteId: l.id))),
              )),
        ],
      ),
    );
  }

  Widget _vazio(String texto) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.line, style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(11),
        ),
        alignment: Alignment.center,
        child: Text(texto, style: const TextStyle(color: AppColors.inkSoft, fontSize: 12.5), textAlign: TextAlign.center),
      );
}

class AceitacaoDetalheScreen extends StatefulWidget {
  final String loteId;
  const AceitacaoDetalheScreen({super.key, required this.loteId});

  @override
  State<AceitacaoDetalheScreen> createState() => _AceitacaoDetalheScreenState();
}

class _AceitacaoDetalheScreenState extends State<AceitacaoDetalheScreen> {
  @override
  Widget build(BuildContext context) {
    final l = MockDb.lotePorId(widget.loteId);
    final cl = MockDb.classePorId(l.classeId);
    final fckEst = l.calcularFckEst();
    final aceito = fckEst != null && fckEst >= cl.fck;

    return AppShell(
      title: 'Lote ${l.numero}',
      accent: _accent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoCard(children: [
            KvRow(label: 'fck de projeto', value: '${cl.fck} MPa'),
            KvRow(label: 'fck,est', value: fckEst != null ? '$fckEst MPa' : '—'),
          ]),
          AppBanner(
            titulo: aceito ? 'Lote aceito' : 'Lote reprovado',
            texto: 'fck,est ${aceito ? 'igual ou acima' : 'abaixo'} do fck de projeto (${cl.fck} MPa).',
            tom: aceito ? BannerTom.verde : BannerTom.vermelho,
          ),
          const NoteText(
              'Cálculo simplificado para fins de protótipo (a regra completa da NBR 12655 varia conforme o número de exemplares). O sistema calcula — a construtora só registra a decisão.'),
          const SizedBox(height: 12),
          PrimaryButton(
            texto: 'Registrar ${aceito ? 'aceitação' : 'reprovação'}',
            perigo: !aceito,
            onPressed: () {
              setState(() {
                l.status = aceito ? StatusLote.aceito : StatusLote.reprovado;
              });
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}
