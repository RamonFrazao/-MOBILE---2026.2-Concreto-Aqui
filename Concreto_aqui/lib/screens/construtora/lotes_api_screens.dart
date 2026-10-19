import 'package:flutter/material.dart';
import '../../services/lotes_api_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

const _accent = AppColors.accentConstrutora;

String _dois(int n) => n.toString().padLeft(2, '0');

/// "2026-10-12" -> "12/10/2026"
String _fmtDataIso(String s) => '${s.substring(8, 10)}/${s.substring(5, 7)}/${s.substring(0, 4)}';

/// DateTime -> "2026-10-12" (o formato que a API espera)
String _paraDataIso(DateTime d) => '${d.year}-${_dois(d.month)}-${_dois(d.day)}';

String _fmtDataHora(DateTime d) => '${_dois(d.day)}/${_dois(d.month)} ${_dois(d.hour)}:${_dois(d.minute)}';
String _fmtVolume(num v) => v.toStringAsFixed(2).replaceAll('.', ',');

class _Rotulo extends StatelessWidget {
  final String texto;
  const _Rotulo(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(
        texto,
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.inkSoft),
      ),
    );
  }
}

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

/// "Em andamento" / "Encerrado" (e o texto cru, para lotes do desenho antigo).
class _SituacaoLote extends StatelessWidget {
  final String status;
  const _SituacaoLote(this.status);

  @override
  Widget build(BuildContext context) {
    if (status == 'em_andamento') {
      return const StatusBadge(texto: 'Em andamento', cor: AppColors.amber, fundo: AppColors.amberSoft);
    }
    if (status == 'encerrado') {
      return const StatusBadge(texto: 'Encerrado', cor: AppColors.inkSoft, fundo: Color(0xFFEDEEE8));
    }
    return StatusBadge(texto: status, cor: AppColors.inkSoft, fundo: const Color(0xFFEDEEE8));
  }
}

// ---------------------------------------------------------------------
// Lista de lotes
// ---------------------------------------------------------------------

class LotesListaScreen extends StatefulWidget {
  const LotesListaScreen({super.key});

  @override
  State<LotesListaScreen> createState() => _LotesListaScreenState();
}

class _LotesListaScreenState extends State<LotesListaScreen> {
  final _repo = LotesApiRepository();

  List<LoteResumo>? _lotes;
  String? _erroCarga;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final r = await _repo.listar();
    if (!mounted) return;
    setState(() {
      if (r.ok) _lotes = r.dados;
      _erroCarga = r.ok ? null : r.erro;
    });
  }

  Future<void> _abrir() async {
    final criou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const NovoLoteScreen()),
    );
    if (criou == true) await _carregar();
  }

  Future<void> _ver(LoteResumo l) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LoteAcompanhamentoScreen(loteId: l.id)),
    );
    // O lote pode ter sido encerrado ou excluído lá dentro.
    if (mounted) await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final lotes = _lotes;
    final carregando = lotes == null && _erroCarga == null;

    return AppShell(
      title: 'Lotes',
      accent: _accent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const NoteText(
              'O lote é a unidade de julgamento: reúne as peças concretadas na mesma condição e guarda o fck de projeto. A aceitação é do lote, nunca de um caminhão isolado.'),
          const SizedBox(height: 10),
          PrimaryButton(texto: 'Abrir lote', onPressed: _abrir),
          const SizedBox(height: 12),
          if (_erroCarga != null)
            AppBanner(titulo: 'Não foi possível carregar', texto: _erroCarga!, tom: BannerTom.vermelho),
          if (carregando)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (lotes != null && lotes.isEmpty) const NoteText('Nenhum lote aberto ainda.'),
          if (lotes != null) ...lotes.map((l) => _LoteTile(lote: l, onTap: () => _ver(l))),
        ],
      ),
    );
  }
}

class _LoteTile extends StatelessWidget {
  final LoteResumo lote;
  final VoidCallback onTap;

  const _LoteTile({required this.lote, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = lote;
    final pecas = l.qtdPecas == 1 ? '1 peça' : '${l.qtdPecas} peças';
    final caminhoes = l.qtdCaminhoes == 1 ? '1 caminhão' : '${l.qtdCaminhoes} caminhões';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.line),
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
                      child: Text(
                        'Lote ${l.numero}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                      ),
                    ),
                    _SituacaoLote(l.status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${l.obraNome} · concretagem em ${_fmtDataIso(l.dataConcretagem)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
                ),
                const SizedBox(height: 2),
                Text(
                  'fck de projeto ${l.fckProjeto ?? '—'} MPa',
                  style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
                ),
                const SizedBox(height: 8),
                Text(
                  '$pecas · $caminhoes · ${_fmtVolume(l.volumeTotal)} m³',
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
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
// Abertura de lote
// ---------------------------------------------------------------------

class NovoLoteScreen extends StatefulWidget {
  const NovoLoteScreen({super.key});

  @override
  State<NovoLoteScreen> createState() => _NovoLoteScreenState();
}

class _NovoLoteScreenState extends State<NovoLoteScreen> {
  final _repo = LotesApiRepository();

  OpcoesLote? _opcoes;
  String? _erroCarga;

  int? _obraId;
  DateTime? _data;
  final _fckCtrl = TextEditingController();
  final Set<int> _pecasEscolhidas = {};

  String? _erroForm;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _fckCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final r = await _repo.opcoes();
    if (!mounted) return;
    setState(() {
      if (r.ok) _opcoes = r.dados;
      _erroCarga = r.ok ? null : r.erro;
    });
  }

  Future<void> _escolherData() async {
    final hoje = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _data ?? hoje,
      firstDate: DateTime(hoje.year - 1),
      lastDate: DateTime(hoje.year + 2),
    );
    if (d != null && mounted) setState(() => _data = d);
  }

  Future<void> _salvar() async {
    final obraId = _obraId;
    final data = _data;
    final fck = int.tryParse(_fckCtrl.text.trim());

    if (obraId == null || data == null || fck == null || _pecasEscolhidas.isEmpty) {
      setState(() => _erroForm =
          'Escolha a obra, a data da concretagem e ao menos uma peça, e informe o fck de projeto (em MPa).');
      return;
    }

    setState(() {
      _erroForm = null;
      _salvando = true;
    });

    // fck zero ou negativo, ou peça que já está em outro lote da mesma data,
    // seguem para a API de propósito: é ela quem decide e devolve a mensagem.
    final r = await _repo.abrir(
      obraId: obraId,
      dataConcretagem: _paraDataIso(data),
      fckProjeto: fck,
      pecaIds: _pecasEscolhidas.toList(),
    );
    if (!mounted) return;
    setState(() => _salvando = false);

    if (!r.ok) {
      setState(() => _erroForm = r.erro);
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final o = _opcoes;
    final carregando = o == null && _erroCarga == null;
    final pecasDaObra = (o == null || _obraId == null)
        ? <OpcaoPecaLote>[]
        : o.pecas.where((p) => p.obraId == _obraId).toList();

    return AppShell(
      title: 'Abrir lote',
      accent: _accent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_erroCarga != null)
            AppBanner(titulo: 'Não foi possível carregar', texto: _erroCarga!, tom: BannerTom.vermelho),
          if (carregando)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (o != null) ...[
            const _Rotulo('Obra'),
            if (o.obras.isEmpty)
              const NoteText('Nenhuma obra cadastrada. Cadastre uma em "Obras e peças".')
            else
              DropdownButtonFormField<int>(
                value: _obraId,
                isExpanded: true,
                hint: const Text('Escolha a obra'),
                items: o.obras
                    .map((ob) => DropdownMenuItem<int>(
                          value: ob.id,
                          child: Text(ob.nome, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setState(() {
                  _obraId = v;
                  _pecasEscolhidas.clear(); // as peças são da obra escolhida
                }),
              ),
            const SizedBox(height: 14),
            const _Rotulo('Data da concretagem'),
            OutlinedButton(
              onPressed: _escolherData,
              child: Text(_data == null ? 'Escolher data' : _fmtDataIso(_paraDataIso(_data!))),
            ),
            const SizedBox(height: 14),
            const _Rotulo('fck de projeto (MPa)'),
            TextField(
              controller: _fckCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'ex.: 25'),
            ),
            const SizedBox(height: 14),
            const _Rotulo('Peças abrangidas'),
            if (_obraId == null)
              const NoteText('Escolha a obra para ver as peças dela.')
            else if (pecasDaObra.isEmpty)
              const NoteText('Esta obra ainda não tem peças cadastradas.')
            else
              ...pecasDaObra.map((p) => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(p.rotulo, style: const TextStyle(fontSize: 13)),
                    value: _pecasEscolhidas.contains(p.id),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _pecasEscolhidas.add(p.id);
                      } else {
                        _pecasEscolhidas.remove(p.id);
                      }
                    }),
                  )),
            const NoteText('Um lote abrange uma ou mais peças, e uma peça pertence a um só lote por concretagem.'),
            const SizedBox(height: 14),
            if (_erroForm != null)
              AppBanner(titulo: 'Não foi possível abrir o lote', texto: _erroForm!, tom: BannerTom.vermelho),
            PrimaryButton(
              texto: _salvando ? 'Abrindo...' : 'Abrir lote',
              onPressed: _salvando ? null : _salvar,
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Tela do lote: peças, caminhões recebidos e volume total
// ---------------------------------------------------------------------

class LoteAcompanhamentoScreen extends StatefulWidget {
  final int loteId;
  const LoteAcompanhamentoScreen({super.key, required this.loteId});

  @override
  State<LoteAcompanhamentoScreen> createState() => _LoteAcompanhamentoScreenState();
}

class _LoteAcompanhamentoScreenState extends State<LoteAcompanhamentoScreen> {
  final _repo = LotesApiRepository();

  LoteCompleto? _lote;
  String? _erroCarga;
  String? _aviso; // motivo, quando a API recusa encerrar ou excluir

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final r = await _repo.detalhe(widget.loteId);
    if (!mounted) return;
    setState(() {
      if (r.ok) _lote = r.dados;
      _erroCarga = r.ok ? null : r.erro;
    });
  }

  Future<void> _encerrar(LoteCompleto l) async {
    setState(() => _aviso = null);
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Encerrar lote?'),
        content: Text('O lote ${l.numero} deixa de receber caminhão novo. Isso não pode ser desfeito.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Encerrar')),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    final r = await _repo.encerrar(l.id);
    if (!mounted) return;
    if (r.ok) {
      setState(() => _lote = r.dados);
    } else {
      setState(() => _aviso = r.erro);
    }
  }

  Future<void> _excluir(LoteCompleto l) async {
    setState(() => _aviso = null);
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir lote?'),
        content: Text('O lote ${l.numero} será excluído. Isso não pode ser desfeito.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    final r = await _repo.excluir(l.id);
    if (!mounted) return;
    if (r.ok) {
      Navigator.pop(context);
    } else {
      // Se o lote já recebeu caminhão, a API recusa e a tela mostra o motivo.
      setState(() => _aviso = r.erro);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = _lote;
    final carregando = l == null && _erroCarga == null;

    return AppShell(
      title: l == null ? 'Lote' : 'Lote ${l.numero}',
      accent: _accent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_erroCarga != null)
            AppBanner(titulo: 'Não foi possível carregar', texto: _erroCarga!, tom: BannerTom.vermelho),
          if (_aviso != null)
            AppBanner(titulo: 'Não foi possível concluir', texto: _aviso!, tom: BannerTom.vermelho),
          if (carregando)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (l != null) ...[
            InfoCard(children: [
              KvRow(label: 'Obra', value: l.obraNome ?? '—'),
              KvRow(
                label: 'Concretagem',
                value: l.dataConcretagem == null ? '—' : _fmtDataIso(l.dataConcretagem!),
              ),
              KvRow(label: 'fck de projeto', value: l.fckProjeto == null ? '—' : '${l.fckProjeto} MPa'),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Situação', style: TextStyle(color: AppColors.inkSoft, fontSize: 13)),
                    _SituacaoLote(l.status),
                  ],
                ),
              ),
            ]),

            _Titulo('Peças abrangidas (${l.pecas.length})'),
            if (l.pecas.isEmpty) const NoteText('Este lote não tem peças registradas.'),
            ...l.pecas.map((p) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.line),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(p.rotulo, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                      Text(p.pavimentoNome, style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
                    ],
                  ),
                )),

            _Titulo('Caminhões recebidos (${l.qtdCaminhoes})'),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.greenSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Volume total: ${_fmtVolume(l.volumeTotal)} m³ em ${l.qtdCaminhoes == 1 ? '1 caminhão' : '${l.qtdCaminhoes} caminhões'}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF245A3E)),
              ),
            ),
            if (l.caminhoes.isEmpty) const NoteText('Nenhum caminhão recebido ainda.'),
            ...l.caminhoes.map((c) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.line),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              c.placa ?? 'sem placa',
                              style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                          ),
                          Text(
                            c.volume == null ? 'volume não informado' : '${_fmtVolume(c.volume!)} m³',
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${c.centralNome}${c.pedidoNumero == null ? '' : ' · pedido nº ${c.pedidoNumero}'} · ${_fmtDataHora(c.criadoEm)}',
                        style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                      ),
                    ],
                  ),
                )),

            if (l.encerrado) const NoteText('Lote encerrado: não recebe caminhão novo.'),
            const SizedBox(height: 16),
            if (l.emAndamento) PrimaryButton(texto: 'Encerrar lote', onPressed: () => _encerrar(l)),
            if (l.emAndamento) const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _excluir(l),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.red,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: Text(l.qtdCaminhoes > 0 ? 'Excluir lote (com caminhão)' : 'Excluir lote'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
