import 'package:flutter/material.dart';
import '../../services/classes_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

const _accent = AppColors.accentConstrutora;

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
  final TextInputType? teclado;

  const _Campo({required this.rotulo, required this.controller, this.dica, this.teclado});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(rotulo, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.inkSoft)),
          const SizedBox(height: 5),
          TextField(
            controller: controller,
            keyboardType: teclado,
            decoration: InputDecoration(hintText: dica),
          ),
        ],
      ),
    );
  }
}

class ClassesCadastroScreen extends StatefulWidget {
  const ClassesCadastroScreen({super.key});

  @override
  State<ClassesCadastroScreen> createState() => _ClassesCadastroScreenState();
}

class _ClassesCadastroScreenState extends State<ClassesCadastroScreen> {
  final _repo = ClassesRepository();

  List<ClasseCadastro>? _classes;
  String? _erroCarga;
  String? _aviso; // motivo, quando a API recusa uma exclusão

  final _nomeCtrl = TextEditingController();
  final _fckCtrl = TextEditingController();
  final _abatimentoCtrl = TextEditingController();
  final _toleranciaCtrl = TextEditingController();
  final _agregadoCtrl = TextEditingController();
  final _outrosAditivosCtrl = TextEditingController();
  bool _retardador = false;
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
    _fckCtrl.dispose();
    _abatimentoCtrl.dispose();
    _toleranciaCtrl.dispose();
    _agregadoCtrl.dispose();
    _outrosAditivosCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final r = await _repo.listar();
    if (!mounted) return;
    setState(() {
      if (r.ok) _classes = r.dados;
      _erroCarga = r.ok ? null : r.erro;
    });
  }

  Future<void> _cadastrar() async {
    setState(() {
      _erroForm = null;
      _salvando = true;
    });

    final nome = _nomeCtrl.text.trim();
    final fck = int.tryParse(_fckCtrl.text.trim());
    final abatimento = int.tryParse(_abatimentoCtrl.text.trim());
    final tolerancia = int.tryParse(_toleranciaCtrl.text.trim());
    final agregado = num.tryParse(_agregadoCtrl.text.trim().replaceAll(',', '.'));

    if (nome.isEmpty || fck == null || abatimento == null || tolerancia == null || agregado == null) {
      setState(() {
        _salvando = false;
        _erroForm =
            'Preencha nome, fck, abatimento, tolerância e dimensão do agregado. A tolerância é obrigatória.';
      });
      return;
    }

    // Valor negativo (tolerância, por exemplo) segue para a API de
    // propósito: é ela quem decide e devolve a mensagem.
    final outros = _outrosAditivosCtrl.text.trim();
    final r = await _repo.criar(
      nome: nome,
      fck: fck,
      abatimentoAlvo: abatimento,
      abatimentoTolerancia: tolerancia,
      agregadoMm: agregado,
      aditivoRetardador: _retardador,
      aditivosOutros: outros.isEmpty ? null : outros,
    );
    if (!mounted) return;
    setState(() => _salvando = false);
    if (!r.ok) {
      setState(() => _erroForm = r.erro);
      return;
    }

    _nomeCtrl.clear();
    _fckCtrl.clear();
    _abatimentoCtrl.clear();
    _toleranciaCtrl.clear();
    _agregadoCtrl.clear();
    _outrosAditivosCtrl.clear();
    setState(() => _retardador = false);
    await _carregar();
  }

  Future<void> _excluir(ClasseCadastro c) async {
    setState(() => _aviso = null);
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir classe?'),
        content: Text('A classe "${c.nome}" será excluída. Isso não pode ser desfeito.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    final r = await _repo.excluir(c.id);
    if (!mounted) return;
    // Se a classe tem pedido, a API recusa e a tela mostra o motivo.
    if (!r.ok) setState(() => _aviso = r.erro);
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final classes = _classes;
    final carregando = classes == null && _erroCarga == null;

    return AppShell(
      title: 'Classes de concreto',
      accent: _accent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const NoteText(
              'A classe reúne o que se especifica ao comprar: fck, abatimento com tolerância, dimensão do agregado e aditivos. É a tolerância que, na chegada do caminhão, decide se ele entra ou volta.'),
          const SizedBox(height: 10),
          if (_erroCarga != null)
            AppBanner(titulo: 'Não foi possível carregar', texto: _erroCarga!, tom: BannerTom.vermelho),
          if (_aviso != null)
            AppBanner(titulo: 'Não foi possível excluir', texto: _aviso!, tom: BannerTom.vermelho),
          if (carregando)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (classes != null && classes.isEmpty) const NoteText('Nenhuma classe cadastrada ainda.'),
          if (classes != null) ...classes.map((c) => _ClasseTile(classe: c, onExcluir: () => _excluir(c))),

          const _Titulo('Nova classe'),
          _Campo(rotulo: 'Nome da classe', controller: _nomeCtrl, dica: 'ex.: C25'),
          _Campo(rotulo: 'fck (MPa)', controller: _fckCtrl, dica: 'ex.: 25', teclado: TextInputType.number),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Campo(
                  rotulo: 'Abatimento (mm)',
                  controller: _abatimentoCtrl,
                  dica: 'ex.: 100',
                  teclado: TextInputType.number,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Campo(
                  rotulo: 'Tolerância ± (mm)',
                  controller: _toleranciaCtrl,
                  dica: 'ex.: 20',
                  teclado: const TextInputType.numberWithOptions(signed: true),
                ),
              ),
            ],
          ),
          _Campo(
            rotulo: 'Dimensão máxima do agregado (mm)',
            controller: _agregadoCtrl,
            dica: 'ex.: 19',
            teclado: const TextInputType.numberWithOptions(decimal: true),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Aditivo retardador', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: const Text('Fica registrado na classe', style: TextStyle(fontSize: 11.5)),
            value: _retardador,
            onChanged: (v) => setState(() => _retardador = v),
          ),
          _Campo(rotulo: 'Outros aditivos (opcional)', controller: _outrosAditivosCtrl, dica: 'ex.: plastificante'),
          if (_erroForm != null)
            AppBanner(titulo: 'Não foi possível cadastrar', texto: _erroForm!, tom: BannerTom.vermelho),
          PrimaryButton(
            texto: _salvando ? 'Salvando...' : 'Cadastrar classe',
            onPressed: _salvando ? null : _cadastrar,
          ),
        ],
      ),
    );
  }
}

class _ClasseTile extends StatelessWidget {
  final ClasseCadastro classe;
  final VoidCallback onExcluir;

  const _ClasseTile({required this.classe, required this.onExcluir});

  @override
  Widget build(BuildContext context) {
    final temPedido = classe.qtdPedidos > 0;
    final outros = classe.aditivosOutros;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Formato usual: [C25]  abatimento 100 ± 20 mm
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF1EF),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  classe.nome,
                  style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'abatimento ${classe.abatimentoAlvo} ± ${classe.abatimentoTolerancia} mm',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'fck ${classe.fck} MPa · agregado ${classe.agregadoMm} mm',
            style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
          ),
          if (classe.aditivoRetardador || (outros != null && outros.isNotEmpty)) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (classe.aditivoRetardador)
                  const StatusBadge(texto: 'retardador', cor: AppColors.amber, fundo: AppColors.amberSoft),
                if (outros != null && outros.isNotEmpty)
                  StatusBadge(texto: outros, cor: AppColors.inkSoft, fundo: const Color(0xFFEDEEE8)),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  temPedido ? '${classe.qtdPedidos} pedido(s) já feito(s)' : 'nenhum pedido ainda',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                ),
              ),
              OutlinedButton(
                onPressed: onExcluir,
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
                child: Text(temPedido ? 'Excluir (com pedido)' : 'Excluir'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
