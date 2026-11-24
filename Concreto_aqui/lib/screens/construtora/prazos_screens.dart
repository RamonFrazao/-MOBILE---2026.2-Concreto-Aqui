import 'package:flutter/material.dart';
import '../../services/caminhoes_repository.dart';
import '../../services/prazos_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';
import '../obra/caminhoes_screens.dart' show CaminhaoDetalheScreen;

const _accent = AppColors.accentConstrutora;

String _dois(int n) => n.toString().padLeft(2, '0');
String _fmtDataHora(DateTime d) => '${_dois(d.day)}/${_dois(d.month)} ${_dois(d.hour)}:${_dois(d.minute)}';

class _Titulo extends StatelessWidget {
  final String texto;
  const _Titulo(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(
        texto,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.inkSoft),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Relatório do prazo de descarga
// ---------------------------------------------------------------------

class RelatorioPrazoScreen extends StatefulWidget {
  const RelatorioPrazoScreen({super.key});

  @override
  State<RelatorioPrazoScreen> createState() => _RelatorioPrazoScreenState();
}

class _RelatorioPrazoScreenState extends State<RelatorioPrazoScreen> {
  final _repo = CaminhoesRepository();

  RelatorioPrazo? _relatorio;
  String? _erroCarga;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final r = await _repo.relatorioPrazo();
    if (!mounted) return;
    setState(() {
      if (r.ok) _relatorio = r.dados;
      _erroCarga = r.ok ? null : r.erro;
    });
  }

  Future<void> _ver(CaminhaoRegistrado c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CaminhaoDetalheScreen(caminhaoId: c.id)),
    );
    if (mounted) await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final rel = _relatorio;
    final carregando = rel == null && _erroCarga == null;

    return AppShell(
      title: 'Relatório de prazo',
      accent: _accent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const NoteText(
              'Caminhão fora do prazo não é apagado nem bloqueado: fica registrado aqui e no lote, porque é o dado que explica um resultado ruim 28 dias depois.'),
          const SizedBox(height: 10),
          if (_erroCarga != null)
            AppBanner(titulo: 'Não foi possível carregar', texto: _erroCarga!, tom: BannerTom.vermelho),
          if (carregando)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (rel != null) ...[
            if (rel.resumo.foraDoPrazo == 0)
              const AppBanner(
                titulo: 'Nenhum caminhão fora do prazo',
                texto: 'Todas as descargas registradas terminaram, ou estão correndo, dentro do prazo.',
                tom: BannerTom.verde,
              )
            else
              AppBanner(
                titulo: rel.resumo.foraDoPrazo == 1
                    ? '1 caminhão fora do prazo'
                    : '${rel.resumo.foraDoPrazo} caminhões fora do prazo',
                texto: 'Descarga encerrada depois do prazo, ou ainda aberta com o prazo já estourado.',
                tom: BannerTom.vermelho,
              ),
            InfoCard(children: [
              KvRow(label: 'Caminhões com nota', value: '${rel.resumo.total}'),
              KvRow(label: 'Descarregando, no prazo', value: '${rel.resumo.noPrazo}'),
              KvRow(label: 'Descarregando, falta pouco', value: '${rel.resumo.atencao}'),
              KvRow(label: 'Prazo estourado (descarga aberta)', value: '${rel.resumo.estourado}'),
              KvRow(label: 'Encerrados dentro do prazo', value: '${rel.resumo.encerradaNoPrazo}'),
              KvRow(label: 'Encerrados fora do prazo', value: '${rel.resumo.encerradaForaDoPrazo}'),
            ]),
            if (rel.foraDoPrazo.isNotEmpty) const _Titulo('Caminhões fora do prazo'),
            ...rel.foraDoPrazo.map((c) => _TileForaDoPrazo(caminhao: c, onTap: () => _ver(c))),
          ],
        ],
      ),
    );
  }
}

class _TileForaDoPrazo extends StatelessWidget {
  final CaminhaoRegistrado caminhao;
  final VoidCallback onTap;

  const _TileForaDoPrazo({required this.caminhao, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = caminhao;
    final aberta = c.descargaAberta;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.red),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Nota ${c.numeroNota}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                    ),
                    StatusBadge(
                      texto: aberta ? 'Estourado' : 'Fora do prazo',
                      cor: AppColors.red,
                      fundo: AppColors.redSoft,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${c.centralNome} · ${c.placa} · Lote ${c.loteNumero} · Pedido nº ${c.pedidoNumero}',
                  style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
                ),
                const SizedBox(height: 2),
                Text(
                  'Primeiro contato ${_fmtDataHora(c.primeiroContatoEm)} · prazo de ${c.prazoMinutos} min',
                  style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
                ),
                const SizedBox(height: 6),
                Text(
                  aberta
                      ? 'Descarga ainda aberta: o prazo estourou há ${c.excedeuMinutos} min.'
                      : 'Descarga encerrada às ${_fmtDataHora(c.descargaFimEm!)}: passou ${c.excedeuMinutos} min do prazo.',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.red),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Configuração do prazo
// ---------------------------------------------------------------------

class ConfigPrazosScreen extends StatefulWidget {
  const ConfigPrazosScreen({super.key});

  @override
  State<ConfigPrazosScreen> createState() => _ConfigPrazosScreenState();
}

class _ConfigPrazosScreenState extends State<ConfigPrazosScreen> {
  final _repo = PrazosRepository();

  bool _carregado = false;
  String? _erroCarga;

  final _prazoCtrl = TextEditingController();
  final _retardadorCtrl = TextEditingController();
  final _avisoCtrl = TextEditingController();

  String? _erroForm;
  String? _sucesso;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _prazoCtrl.dispose();
    _retardadorCtrl.dispose();
    _avisoCtrl.dispose();
    super.dispose();
  }

  void _preencher(ConfigPrazo c) {
    _prazoCtrl.text = '${c.prazoDescargaMinutos}';
    _retardadorCtrl.text = c.prazoRetardadorMinutos == null ? '' : '${c.prazoRetardadorMinutos}';
    _avisoCtrl.text = '${c.avisoMinutos}';
  }

  Future<void> _carregar() async {
    final r = await _repo.ler();
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _preencher(r.dados!);
        _carregado = true;
        _erroCarga = null;
      } else {
        _erroCarga = r.erro;
      }
    });
  }

  Future<void> _salvar() async {
    final prazo = int.tryParse(_prazoCtrl.text.trim());
    final aviso = int.tryParse(_avisoCtrl.text.trim());
    final retardadorTexto = _retardadorCtrl.text.trim();
    final retardador = retardadorTexto.isEmpty ? null : int.tryParse(retardadorTexto);

    if (prazo == null || aviso == null || (retardadorTexto.isNotEmpty && retardador == null)) {
      setState(() {
        _sucesso = null;
        _erroForm = 'Informe os minutos como números inteiros (o prazo com retardador pode ficar em branco).';
      });
      return;
    }

    setState(() {
      _erroForm = null;
      _sucesso = null;
      _salvando = true;
    });
    // Regras (retardador não menor que o normal, aviso dentro do prazo)
    // são conferidas pela API, que devolve a mensagem.
    final r = await _repo.salvar(
      prazoDescargaMinutos: prazo,
      prazoRetardadorMinutos: retardador,
      avisoMinutos: aviso,
    );
    if (!mounted) return;
    setState(() {
      _salvando = false;
      if (r.ok) {
        _preencher(r.dados!);
        _sucesso = 'Configuração salva. Vale para os caminhões que chegarem a partir de agora.';
      } else {
        _erroForm = r.erro;
      }
    });
  }

  Widget _campo(String rotulo, TextEditingController c, String dica) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(rotulo,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.inkSoft)),
          const SizedBox(height: 5),
          TextField(
            controller: c,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(hintText: dica),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final carregando = !_carregado && _erroCarga == null;

    return AppShell(
      title: 'Prazo de descarga',
      accent: _accent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const NoteText(
              'A descarga tem de terminar dentro de um prazo, contado do primeiro contato do cimento com a água. O prazo vem desta configuração, não do código.'),
          const SizedBox(height: 12),
          if (_erroCarga != null)
            AppBanner(titulo: 'Não foi possível carregar', texto: _erroCarga!, tom: BannerTom.vermelho),
          if (carregando)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_carregado) ...[
            _campo('Prazo de descarga (minutos)', _prazoCtrl, 'ex.: o da norma'),
            _campo('Prazo com aditivo retardador (minutos) — opcional', _retardadorCtrl, 'em branco = vale o prazo normal'),
            const NoteText(
                'A equipe busca na norma qual é o prazo com retardador e em que condição ele vale. Enquanto estiver em branco, vale o prazo normal.'),
            const SizedBox(height: 12),
            _campo('Avisar quando faltarem (minutos)', _avisoCtrl, 'ex.: 15'),
            if (_erroForm != null)
              AppBanner(titulo: 'Não foi possível salvar', texto: _erroForm!, tom: BannerTom.vermelho),
            if (_sucesso != null) AppBanner(titulo: 'Salvo', texto: _sucesso!, tom: BannerTom.verde),
            PrimaryButton(
              texto: _salvando ? 'Salvando...' : 'Salvar configuração',
              onPressed: _salvando ? null : _salvar,
            ),
            const NoteText('Cada caminhão guarda o prazo que valia quando chegou: mudar aqui não altera os que já chegaram.'),
          ],
        ],
      ),
    );
  }
}
