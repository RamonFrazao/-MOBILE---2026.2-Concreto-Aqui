import 'package:flutter/material.dart';
import '../../services/obra_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

const _accent = AppColors.accentConstrutora;

// ---------------------------------------------------------------------
// Peças auxiliares de layout usadas só neste arquivo
// ---------------------------------------------------------------------

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

class _Campo extends StatelessWidget {
  final String rotulo;
  final TextEditingController controller;
  final String? dica;

  const _Campo({required this.rotulo, required this.controller, this.dica});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(rotulo,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.inkSoft)),
          const SizedBox(height: 5),
          TextField(controller: controller, decoration: InputDecoration(hintText: dica)),
        ],
      ),
    );
  }
}

Widget _dropdown<T>({
  required String rotulo,
  required T? valor,
  required List<DropdownMenuItem<T>> itens,
  required ValueChanged<T?> onChanged,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(rotulo,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.inkSoft)),
        const SizedBox(height: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(9),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              isExpanded: true,
              value: valor,
              items: itens,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------
// Lista de obras + cadastro de obra
// ---------------------------------------------------------------------

class ObrasListScreen extends StatefulWidget {
  const ObrasListScreen({super.key});

  @override
  State<ObrasListScreen> createState() => _ObrasListScreenState();
}

class _ObrasListScreenState extends State<ObrasListScreen> {
  final _repo = ObraRepository();
  final _nomeCtrl = TextEditingController();
  final _enderecoCtrl = TextEditingController();
  final _rtCtrl = TextEditingController();

  List<Obra>? _obras;
  String? _erroLista;
  String? _erroForm;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _enderecoCtrl.dispose();
    _rtCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final r = await _repo.listarObras();
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _obras = r.dados;
        _erroLista = null;
      } else {
        _erroLista = r.erro;
      }
    });
  }

  Future<void> _cadastrar() async {
    setState(() {
      _salvando = true;
      _erroForm = null;
    });
    // A validação (campos obrigatórios, tamanho) é da API; a tela só
    // mostra a mensagem que ela devolver.
    final r = await _repo.criarObra(
      nome: _nomeCtrl.text,
      endereco: _enderecoCtrl.text,
      responsavelTecnico: _rtCtrl.text,
    );
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _salvando = false;
        _erroForm = r.erro;
      });
      return;
    }
    _nomeCtrl.clear();
    _enderecoCtrl.clear();
    _rtCtrl.clear();
    setState(() => _salvando = false);
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final obras = _obras;
    return AppShell(
      title: 'Obras e peças',
      accent: _accent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_erroLista != null)
            AppBanner(titulo: 'Não foi possível carregar', texto: _erroLista!, tom: BannerTom.vermelho),
          if (obras == null && _erroLista == null)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (obras != null && obras.isEmpty)
            const NoteText('Nenhuma obra cadastrada ainda. Cadastre a primeira abaixo.'),
          if (obras != null)
            ...obras.map((o) => MenuRow(
                  titulo: o.nome,
                  subtitulo:
                      '${o.endereco} · RT: ${o.responsavelTecnico}\n${o.qtdPavimentos} pavimento(s) · ${o.qtdPecas} peça(s)',
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ObraDetalheScreen(obra: o)),
                    );
                    if (mounted) _carregar();
                  },
                )),
          const _Titulo('Nova obra'),
          _Campo(rotulo: 'Nome da obra', controller: _nomeCtrl, dica: 'ex.: Residencial Bom Conselho'),
          _Campo(rotulo: 'Endereço', controller: _enderecoCtrl, dica: 'Rua, número, bairro'),
          _Campo(rotulo: 'Responsável técnico', controller: _rtCtrl, dica: 'Nome do engenheiro responsável'),
          if (_erroForm != null)
            AppBanner(titulo: 'Não foi possível cadastrar', texto: _erroForm!, tom: BannerTom.vermelho),
          PrimaryButton(
            texto: _salvando ? 'Salvando...' : 'Cadastrar obra',
            onPressed: _salvando ? null : _cadastrar,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Uma obra: pavimentos e peças
// ---------------------------------------------------------------------

class ObraDetalheScreen extends StatefulWidget {
  final Obra obra;
  const ObraDetalheScreen({super.key, required this.obra});

  @override
  State<ObraDetalheScreen> createState() => _ObraDetalheScreenState();
}

class _ObraDetalheScreenState extends State<ObraDetalheScreen> {
  final _repo = ObraRepository();
  final _pavCtrl = TextEditingController();
  final _identCtrl = TextEditingController();

  List<Pavimento>? _pavimentos;
  List<Peca>? _pecas;
  String? _erroCarga;

  String? _erroPav; // erro do formulário de pavimento
  String? _erroPeca; // erro do formulário de peça
  String? _avisoLista; // motivo de uma exclusão recusada, etc.

  int? _pavSelecionado;
  String _tipoSelecionado = 'pilar';
  bool _salvandoPav = false;
  bool _salvandoPeca = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _pavCtrl.dispose();
    _identCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final rp = await _repo.listarPavimentos(widget.obra.id);
    final rc = await _repo.listarPecas(widget.obra.id);
    if (!mounted) return;
    setState(() {
      if (!rp.ok || !rc.ok) {
        _erroCarga = rp.erro ?? rc.erro;
        return;
      }
      _erroCarga = null;
      _pavimentos = rp.dados;
      _pecas = rc.dados;
      final pavs = _pavimentos ?? [];
      final aindaExiste = pavs.any((p) => p.id == _pavSelecionado);
      if (!aindaExiste) {
        _pavSelecionado = pavs.isEmpty ? null : pavs.first.id;
      }
    });
  }

  Future<void> _adicionarPavimento() async {
    setState(() {
      _salvandoPav = true;
      _erroPav = null;
    });
    final r = await _repo.criarPavimento(widget.obra.id, _pavCtrl.text);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _salvandoPav = false;
        _erroPav = r.erro;
      });
      return;
    }
    _pavCtrl.clear();
    setState(() => _salvandoPav = false);
    await _carregar();
  }

  Future<void> _adicionarPeca() async {
    final pav = _pavSelecionado;
    if (pav == null) return;
    setState(() {
      _salvandoPeca = true;
      _erroPeca = null;
      _avisoLista = null;
    });
    final r = await _repo.criarPeca(
      obraId: widget.obra.id,
      pavimentoId: pav,
      tipo: _tipoSelecionado,
      identificacao: _identCtrl.text,
    );
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _salvandoPeca = false;
        _erroPeca = r.erro;
      });
      return;
    }
    _identCtrl.clear();
    setState(() => _salvandoPeca = false);
    await _carregar();
  }

  Future<void> _excluir(Peca peca) async {
    setState(() => _avisoLista = null);

    // Peça sem concreto: confirma antes de apagar. Peça com concreto:
    // vai direto à API, que recusa e devolve o motivo (não há o que
    // confirmar, porque não será excluída).
    if (!peca.concretoLancado) {
      final confirmou = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Excluir peça?'),
          content: Text('A peça "${peca.identificacao}" será excluída. Isso não pode ser desfeito.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
          ],
        ),
      );
      if (confirmou != true || !mounted) return;
    }

    final r = await _repo.excluirPeca(widget.obra.id, peca.id);
    if (!mounted) return;
    if (!r.ok) {
      setState(() => _avisoLista = r.erro);
    }
    // Recarrega de qualquer jeito: se a recusa veio porque o estado da
    // tela estava desatualizado, a lista passa a mostrar o estado real.
    await _carregar();
  }

  List<Widget> _listaDePecas() {
    final pavs = _pavimentos ?? [];
    final pecas = _pecas ?? [];
    final widgets = <Widget>[];
    for (final pav in pavs) {
      final daqui = pecas.where((p) => p.pavimentoId == pav.id).toList();
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 8),
        child: Text(pav.nome, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      ));
      if (daqui.isEmpty) {
        widgets.add(const NoteText('Nenhuma peça neste pavimento.'));
      } else {
        widgets.addAll(daqui.map((p) => _PecaTile(peca: p, onExcluir: () => _excluir(p))));
      }
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final obra = widget.obra;
    final pavs = _pavimentos;
    final carregando = pavs == null && _erroCarga == null;

    return AppShell(
      title: obra.nome,
      accent: _accent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(obra.nome, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 6),
                Text(obra.endereco, style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
                const SizedBox(height: 2),
                Text('Responsável técnico: ${obra.responsavelTecnico}',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
              ],
            ),
          ),
          if (_erroCarga != null) ...[
            const SizedBox(height: 12),
            AppBanner(titulo: 'Não foi possível carregar', texto: _erroCarga!, tom: BannerTom.vermelho),
          ],
          if (carregando)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),

          // ---- Pavimentos
          const _Titulo('Pavimentos'),
          if (pavs != null && pavs.isEmpty) const NoteText('Nenhum pavimento cadastrado ainda.'),
          if (pavs != null && pavs.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: pavs.map((p) => Chip(label: Text(p.nome))).toList(),
            ),
          const SizedBox(height: 12),
          _Campo(rotulo: 'Novo pavimento', controller: _pavCtrl, dica: 'ex.: 4º pavimento'),
          if (_erroPav != null)
            AppBanner(titulo: 'Não foi possível cadastrar', texto: _erroPav!, tom: BannerTom.vermelho),
          PrimaryButton(
            texto: _salvandoPav ? 'Salvando...' : 'Adicionar pavimento',
            onPressed: _salvandoPav ? null : _adicionarPavimento,
          ),

          // ---- Peças
          const _Titulo('Peças'),
          if (_avisoLista != null)
            AppBanner(titulo: 'Exclusão não permitida', texto: _avisoLista!, tom: BannerTom.vermelho),
          ..._listaDePecas(),

          // ---- Nova peça
          const _Titulo('Nova peça'),
          if (pavs != null && pavs.isEmpty)
            const NoteText('Cadastre um pavimento antes de cadastrar peças.')
          else if (pavs != null) ...[
            _dropdown<int>(
              rotulo: 'Pavimento',
              valor: _pavSelecionado,
              itens: pavs.map((p) => DropdownMenuItem<int>(value: p.id, child: Text(p.nome))).toList(),
              onChanged: (v) => setState(() => _pavSelecionado = v),
            ),
            _dropdown<String>(
              rotulo: 'Tipo',
              valor: _tipoSelecionado,
              itens: tiposPeca.entries
                  .map((e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _tipoSelecionado = v ?? 'pilar'),
            ),
            _Campo(rotulo: 'Identificação', controller: _identCtrl, dica: 'ex.: P7'),
            if (_erroPeca != null)
              AppBanner(titulo: 'Não foi possível cadastrar', texto: _erroPeca!, tom: BannerTom.vermelho),
            PrimaryButton(
              texto: _salvandoPeca ? 'Salvando...' : 'Cadastrar peça',
              onPressed: _salvandoPeca ? null : _adicionarPeca,
            ),
          ],
        ],
      ),
    );
  }
}

/// Uma linha da lista de peças: tipo + identificação, se já recebeu
/// concreto (e quando), e o botão de excluir (cadeado se já recebeu).
class _PecaTile extends StatelessWidget {
  final Peca peca;
  final VoidCallback onExcluir;

  const _PecaTile({required this.peca, required this.onExcluir});

  @override
  Widget build(BuildContext context) {
    final lancado = peca.concretoLancado;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.only(left: 13, top: 6, bottom: 6, right: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${peca.tipoRotulo} ${peca.identificacao}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                const SizedBox(height: 3),
                if (lancado)
                  Row(
                    children: [
                      const Icon(Icons.check_circle, size: 14, color: AppColors.green),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Concreto lançado em ${peca.dataFormatada ?? '—'}',
                          style: const TextStyle(fontSize: 11.5, color: AppColors.green),
                        ),
                      ),
                    ],
                  )
                else
                  const Text('Sem concreto lançado',
                      style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
              ],
            ),
          ),
          IconButton(
            tooltip: lancado ? 'Não pode ser excluída (já recebeu concreto)' : 'Excluir peça',
            icon: Icon(lancado ? Icons.lock_outline : Icons.delete_outline, color: AppColors.inkSoft),
            onPressed: onExcluir,
          ),
        ],
      ),
    );
  }
}
