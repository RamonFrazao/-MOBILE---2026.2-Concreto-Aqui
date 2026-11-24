import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/domain_models.dart' show Perfil;
import '../../services/caminhoes_repository.dart';
import '../../services/amostras_repository.dart';
import '../../services/session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

const _accent = AppColors.accentObra;

String _dois(int n) => n.toString().padLeft(2, '0');
String _fmtData(DateTime d) => '${_dois(d.day)}/${_dois(d.month)}/${d.year}';
String _fmtHora(TimeOfDay t) => '${_dois(t.hour)}:${_dois(t.minute)}';
String _fmtDataHora(DateTime d) => '${_fmtData(d)} ${_dois(d.hour)}:${_dois(d.minute)}';
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

class _Campo extends StatelessWidget {
  final String rotulo;
  final TextEditingController controller;
  final String? dica;
  final TextInputType? teclado;
  final TextCapitalization capitalizacao;

  const _Campo({
    required this.rotulo,
    required this.controller,
    this.dica,
    this.teclado,
    this.capitalizacao = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Rotulo(rotulo),
          TextField(
            controller: controller,
            keyboardType: teclado,
            textCapitalization: capitalizacao,
            decoration: InputDecoration(hintText: dica),
          ),
        ],
      ),
    );
  }
}

/// Data e hora escolhidas em dois botões, lado a lado.
class _SeletorDataHora extends StatelessWidget {
  final DateTime? data;
  final TimeOfDay? hora;
  final VoidCallback onData;
  final VoidCallback onHora;

  const _SeletorDataHora({
    required this.data,
    required this.hora,
    required this.onData,
    required this.onHora,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onData,
            child: Text(data == null ? 'Escolher data' : _fmtData(data!)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton(
            onPressed: onHora,
            child: Text(hora == null ? 'Escolher hora' : _fmtHora(hora!)),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Lista de caminhões registrados
// ---------------------------------------------------------------------

class CaminhoesListaScreen extends StatefulWidget {
  const CaminhoesListaScreen({super.key});

  @override
  State<CaminhoesListaScreen> createState() => _CaminhoesListaScreenState();
}

class _CaminhoesListaScreenState extends State<CaminhoesListaScreen> {
  final _repo = CaminhoesRepository();

  List<CaminhaoRegistrado>? _caminhoes;
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
      if (r.ok) _caminhoes = r.dados;
      _erroCarga = r.ok ? null : r.erro;
    });
  }

  Future<void> _registrar() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const NovoCaminhaoScreen()));
    if (mounted) await _carregar();
  }

  Future<void> _ver(CaminhaoRegistrado c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CaminhaoDetalheScreen(caminhaoId: c.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lista = _caminhoes;
    final carregando = lista == null && _erroCarga == null;

    return AppShell(
      title: 'Caminhões',
      accent: _accent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          
          const SizedBox(height: 10),
          PrimaryButton(texto: 'Registrar caminhão', onPressed: _registrar),
          const SizedBox(height: 12),
          if (_erroCarga != null)
            AppBanner(titulo: 'Não foi possível carregar', texto: _erroCarga!, tom: BannerTom.vermelho),
          if (carregando)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (lista != null && lista.isEmpty) const NoteText('Nenhum caminhão registrado ainda.'),
          if (lista != null) ...lista.map((c) => _CaminhaoTile(caminhao: c, onTap: () => _ver(c))),
        ],
      ),
    );
  }
}

class _CaminhaoTile extends StatelessWidget {
  final CaminhaoRegistrado caminhao;
  final VoidCallback onTap;

  const _CaminhaoTile({required this.caminhao, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = caminhao;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: (c.confere && !c.foraDoPrazo) ? AppColors.line : AppColors.red),
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
                        'Nota ${c.numeroNota}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                      ),
                    ),
                    if (c.confere)
                      const StatusBadge(texto: 'Confere', cor: AppColors.green, fundo: AppColors.greenSoft)
                    else
                      StatusBadge(
                        texto: c.qtdDivergencias == 1 ? '1 divergência' : '${c.qtdDivergencias} divergências',
                        cor: AppColors.red,
                        fundo: AppColors.redSoft,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${c.centralNome} · ${c.placa} · ${_fmtVolume(c.volume)} m³',
                  style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
                ),
                const SizedBox(height: 2),
                Text(
                  'Lote ${c.loteNumero} · Pedido nº ${c.pedidoNumero} · chegou ${_fmtDataHora(c.chegadaObraEm)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
                ),
                const SizedBox(height: 6),
                _TagPrazo(caminhao: c),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A situação do prazo de descarga numa linha só (para a lista).
class _TagPrazo extends StatelessWidget {
  final CaminhaoRegistrado caminhao;
  const _TagPrazo({required this.caminhao});

  @override
  Widget build(BuildContext context) {
    final c = caminhao;
    final min = (c.restanteSegundos ?? 0) ~/ 60;
    final String texto;
    final Color cor;
    switch (c.situacaoPrazo) {
      case 'atencao':
        texto = 'Falta pouco: restam $min min para o fim do prazo';
        cor = AppColors.amber;
      case 'estourado':
        texto = 'Prazo de descarga estourado há ${c.excedeuMinutos} min';
        cor = AppColors.red;
      case 'encerrada_no_prazo':
        texto = 'Descarga encerrada dentro do prazo';
        cor = AppColors.green;
      case 'encerrada_fora_do_prazo':
        texto = 'Descarga encerrada fora do prazo (passou ${c.excedeuMinutos} min)';
        cor = AppColors.red;
      default:
        texto = 'Descarga em andamento: restam $min min';
        cor = AppColors.green;
    }
    return Text(texto, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cor));
  }
}

// ---------------------------------------------------------------------
// Registro do caminhão
// ---------------------------------------------------------------------

class NovoCaminhaoScreen extends StatefulWidget {
  const NovoCaminhaoScreen({super.key});

  @override
  State<NovoCaminhaoScreen> createState() => _NovoCaminhaoScreenState();
}

class _NovoCaminhaoScreenState extends State<NovoCaminhaoScreen> {
  final _repo = CaminhoesRepository();

  OpcoesCaminhao? _opcoes;
  String? _erroCarga;

  int? _loteId;
  int? _pedidoId;
  int? _centralId;

  final _notaCtrl = TextEditingController();
  final _placaCtrl = TextEditingController();
  final _volumeCtrl = TextEditingController();
  final _tracoCtrl = TextEditingController();
  final _consumoCtrl = TextEditingController();
  final _classeCtrl = TextEditingController();
  final _fckCtrl = TextEditingController();
  final _aditivosCtrl = TextEditingController();
  bool _retardador = false;

  // Primeiro contato do cimento com a água: sem valor inicial, o técnico
  // tem de ler na nota. Chegada à obra: começa em "agora".
  DateTime? _contatoData;
  TimeOfDay? _contatoHora;
  DateTime? _chegadaData;
  TimeOfDay? _chegadaHora;

  String? _erroForm;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _chegadaData = DateTime.now();
    _chegadaHora = TimeOfDay.now();
    _carregar();
  }

  @override
  void dispose() {
    _notaCtrl.dispose();
    _placaCtrl.dispose();
    _volumeCtrl.dispose();
    _tracoCtrl.dispose();
    _consumoCtrl.dispose();
    _classeCtrl.dispose();
    _fckCtrl.dispose();
    _aditivosCtrl.dispose();
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

  Future<DateTime?> _escolherData(DateTime? atual) {
    final hoje = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: atual ?? hoje,
      firstDate: DateTime(hoje.year - 1),
      lastDate: DateTime(hoje.year + 1),
    );
  }

  Future<void> _escolherContatoData() async {
    final d = await _escolherData(_contatoData);
    if (d != null && mounted) setState(() => _contatoData = d);
  }

  Future<void> _escolherContatoHora() async {
    final h = await showTimePicker(context: context, initialTime: _contatoHora ?? TimeOfDay.now());
    if (h != null && mounted) setState(() => _contatoHora = h);
  }

  Future<void> _escolherChegadaData() async {
    final d = await _escolherData(_chegadaData);
    if (d != null && mounted) setState(() => _chegadaData = d);
  }

  Future<void> _escolherChegadaHora() async {
    final h = await showTimePicker(context: context, initialTime: _chegadaHora ?? TimeOfDay.now());
    if (h != null && mounted) setState(() => _chegadaHora = h);
  }

  Future<void> _salvar() async {
    final loteId = _loteId;
    final pedidoId = _pedidoId;
    final centralId = _centralId;
    final nota = _notaCtrl.text.trim();
    final placa = _placaCtrl.text.trim();
    final traco = _tracoCtrl.text.trim();
    final classeNota = _classeCtrl.text.trim();
    final volume = num.tryParse(_volumeCtrl.text.trim().replaceAll(',', '.'));
    final fck = int.tryParse(_fckCtrl.text.trim());
    final consumoTexto = _consumoCtrl.text.trim();
    final consumo = consumoTexto.isEmpty ? null : num.tryParse(consumoTexto.replaceAll(',', '.'));
    final contatoData = _contatoData;
    final contatoHora = _contatoHora;
    final chegadaData = _chegadaData;
    final chegadaHora = _chegadaHora;

    if (loteId == null ||
        pedidoId == null ||
        centralId == null ||
        nota.isEmpty ||
        placa.isEmpty ||
        traco.isEmpty ||
        classeNota.isEmpty ||
        volume == null ||
        fck == null ||
        contatoData == null ||
        contatoHora == null ||
        chegadaData == null ||
        chegadaHora == null) {
      setState(() => _erroForm =
          'Escolha o lote, o pedido e a central, e preencha nota, placa, volume, traço, classe e fck da nota, o primeiro contato do cimento com a água e a chegada à obra.');
      return;
    }
    if (consumoTexto.isNotEmpty && consumo == null) {
      setState(() => _erroForm = 'O consumo de cimento precisa ser um número (kg/m³).');
      return;
    }

    setState(() {
      _erroForm = null;
      _salvando = true;
    });

    final aditivos = _aditivosCtrl.text.trim();
    // Volume zero, nota repetida, horários incoerentes etc. seguem para a
    // API de propósito: é ela quem decide e devolve a mensagem.
    final r = await _repo.registrar(
      loteId: loteId,
      pedidoId: pedidoId,
      centralId: centralId,
      numeroNota: nota,
      placa: placa,
      volume: volume,
      traco: traco,
      consumoCimento: consumo,
      aditivos: aditivos.isEmpty ? null : aditivos,
      aditivoRetardador: _retardador,
      classeNota: classeNota,
      fckNota: fck,
      primeiroContatoEm: DateTime(
          contatoData.year, contatoData.month, contatoData.day, contatoHora.hour, contatoHora.minute),
      chegadaObraEm: DateTime(
          chegadaData.year, chegadaData.month, chegadaData.day, chegadaHora.hour, chegadaHora.minute),
    );
    if (!mounted) return;
    setState(() => _salvando = false);

    if (!r.ok) {
      setState(() => _erroForm = r.erro);
      return;
    }

    // Depois de registrar, a tela mostra a nota comparada com o pedido.
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => CaminhaoDetalheScreen(caminhaoId: r.dados!.id, recemRegistrado: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = _opcoes;
    final carregando = o == null && _erroCarga == null;

    int? obraDoLote;
    if (o != null && _loteId != null) {
      for (final l in o.lotes) {
        if (l.id == _loteId) obraDoLote = l.obraId;
      }
    }
    final pedidosDaObra = (o == null || obraDoLote == null)
        ? <OpcaoPedidoCaminhao>[]
        : o.pedidos.where((p) => p.obraId == obraDoLote).toList();

    return AppShell(
      title: 'Registrar caminhão',
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
            const _Titulo('Para onde vai o concreto'),
            const _Rotulo('Lote'),
            if (o.lotes.isEmpty)
              const NoteText('Nenhum lote em andamento. A construtora precisa abrir um lote antes.')
            else
              DropdownButtonFormField<int>(
                value: _loteId,
                isExpanded: true,
                hint: const Text('Escolha o lote'),
                items: o.lotes
                    .map((l) => DropdownMenuItem<int>(
                          value: l.id,
                          child: Text(l.rotulo, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setState(() {
                  _loteId = v;
                  // O pedido tem de ser da mesma obra do lote (o novo, v).
                  int? obraNova;
                  for (final l in o.lotes) {
                    if (l.id == v) obraNova = l.obraId;
                  }
                  final aindaValido = o.pedidos.any((p) => p.id == _pedidoId && p.obraId == obraNova);
                  if (!aindaValido) _pedidoId = null;
                }),
              ),
            const SizedBox(height: 14),
            const _Rotulo('Pedido'),
            if (_loteId == null)
              const NoteText('Escolha o lote para ver os pedidos da mesma obra.')
            else if (pedidosDaObra.isEmpty)
              const NoteText('Nenhum pedido aberto para a obra deste lote.')
            else
              DropdownButtonFormField<int>(
                value: pedidosDaObra.any((p) => p.id == _pedidoId) ? _pedidoId : null,
                isExpanded: true,
                hint: const Text('Escolha o pedido'),
                items: pedidosDaObra
                    .map((p) => DropdownMenuItem<int>(
                          value: p.id,
                          child: Text(p.rotulo, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setState(() {
                  _pedidoId = v;
                  // A central da nota começa como a do pedido; o técnico
                  // troca se a nota disser outra.
                  for (final p in pedidosDaObra) {
                    if (p.id == v) _centralId = p.centralId;
                  }
                }),
              ),

            const _Titulo('Dados da nota de entrega'),
            const _Rotulo('Central (a que está na nota)'),
            if (o.centrais.isEmpty)
              const NoteText('Nenhuma central ativa cadastrada.')
            else
              DropdownButtonFormField<int>(
                value: o.centrais.any((c) => c.id == _centralId) ? _centralId : null,
                isExpanded: true,
                hint: const Text('Escolha a central'),
                items: o.centrais
                    .map((c) => DropdownMenuItem<int>(
                          value: c.id,
                          child: Text(c.nome, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _centralId = v),
              ),
            const SizedBox(height: 12),
            _Campo(rotulo: 'Número da nota', controller: _notaCtrl, dica: 'ex.: 45.812'),
            _Campo(
              rotulo: 'Placa',
              controller: _placaCtrl,
              dica: 'ex.: QRZ-4C18',
              capitalizacao: TextCapitalization.characters,
            ),
            _Campo(
              rotulo: 'Volume (m³)',
              controller: _volumeCtrl,
              dica: 'ex.: 8',
              teclado: const TextInputType.numberWithOptions(decimal: true),
            ),
            _Campo(rotulo: 'Traço', controller: _tracoCtrl, dica: 'ex.: 1 : 2,1 : 2,8 : 0,45'),
            _Campo(
              rotulo: 'Consumo de cimento (kg/m³) — opcional',
              controller: _consumoCtrl,
              dica: 'ex.: 320',
              teclado: const TextInputType.numberWithOptions(decimal: true),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _Campo(
                    rotulo: 'Classe na nota',
                    controller: _classeCtrl,
                    dica: 'ex.: C25',
                    capitalizacao: TextCapitalization.characters,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Campo(
                    rotulo: 'fck na nota (MPa)',
                    controller: _fckCtrl,
                    dica: 'ex.: 25',
                    teclado: TextInputType.number,
                  ),
                ),
              ],
            ),
            _Campo(rotulo: 'Aditivos (opcional)', controller: _aditivosCtrl, dica: 'ex.: plastificante'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tem aditivo retardador', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              value: _retardador,
              onChanged: (v) => setState(() => _retardador = v),
            ),

            const _Titulo('Horários'),
            const _Rotulo('Primeiro contato do cimento com a água'),
            _SeletorDataHora(
              data: _contatoData,
              hora: _contatoHora,
              onData: _escolherContatoData,
              onHora: _escolherContatoHora,
            ),
            
            const SizedBox(height: 12),
            const _Rotulo('Chegada à obra'),
            _SeletorDataHora(
              data: _chegadaData,
              hora: _chegadaHora,
              onData: _escolherChegadaData,
              onHora: _escolherChegadaHora,
            ),
            const SizedBox(height: 16),
            if (_erroForm != null)
              AppBanner(titulo: 'Não foi possível registrar', texto: _erroForm!, tom: BannerTom.vermelho),
            PrimaryButton(
              texto: _salvando ? 'Registrando...' : 'Registrar e conferir com o pedido',
              onPressed: _salvando ? null : _salvar,
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Nota comparada com o pedido
// ---------------------------------------------------------------------

class CaminhaoDetalheScreen extends StatefulWidget {
  final int caminhaoId;

  /// Verdadeiro logo depois do registro: o título do aviso fala em
  /// "registrado" em vez de só mostrar a situação.
  final bool recemRegistrado;

  const CaminhaoDetalheScreen({super.key, required this.caminhaoId, this.recemRegistrado = false});

  @override
  State<CaminhaoDetalheScreen> createState() => _CaminhaoDetalheScreenState();
}

class _CaminhaoDetalheScreenState extends State<CaminhaoDetalheScreen> with WidgetsBindingObserver {
  final _repo = CaminhoesRepository();

  CaminhaoRegistrado? _caminhao;
  String? _erroCarga;
  String? _avisoEncerrar; // motivo, quando a API recusa encerrar a descarga
  bool _encerrando = false;

  // Contagem regressiva. O tempo restante vem do SERVIDOR; o app só o faz
  // "correr" com um cronômetro (Stopwatch), que mede tempo decorrido sem
  // depender da data e hora do aparelho (que podem estar erradas). A cada
  // 30 segundos, e ao voltar para o app, pergunta de novo ao servidor.
  final Stopwatch _cronometro = Stopwatch();
  int _baseSegundos = 0;
  Timer? _timer;
  String? _fase;
  int _tiques = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _carregar();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _passouUmSegundo());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    // Com a tela apagada o cronômetro pode ter parado: ao voltar, o
    // servidor diz quanto tempo falta de verdade.
    if (estado == AppLifecycleState.resumed) _carregar(silencioso: true);
  }

  /// Segundos que faltam (negativo = estourou). Nulo se a descarga já terminou.
  int? get _restante {
    final c = _caminhao;
    if (c == null || c.descargaFimEm != null) return null;
    return _baseSegundos - _cronometro.elapsed.inSeconds;
  }

  String _faseDe(int restante, CaminhaoRegistrado c) {
    if (restante <= 0) return 'estourado';
    if (restante <= c.avisoMinutos * 60) return 'atencao';
    return 'no_prazo';
  }

  void _passouUmSegundo() {
    final c = _caminhao;
    final r = _restante;
    if (!mounted || c == null || r == null) return;
    _tiques++;
    final fase = _faseDe(r, c);
    if (_fase != null && fase != _fase) {
      // Mudou de faixa: o app avisa.
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(fase == 'estourado'
            ? 'Prazo de descarga estourado.'
            : 'Falta pouco para o fim do prazo de descarga.'),
      ));
    }
    _fase = fase;
    if (_tiques % 30 == 0) _carregar(silencioso: true);
    setState(() {});
  }

  Future<void> _carregar({bool silencioso = false}) async {
    final r = await _repo.detalhe(widget.caminhaoId);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        final c = r.dados!;
        _caminhao = c;
        _baseSegundos = c.restanteSegundos ?? 0;
        _cronometro
          ..reset()
          ..start();
        if (c.restanteSegundos != null) _fase ??= _faseDe(c.restanteSegundos!, c);
        _erroCarga = null;
      } else if (!silencioso) {
        _erroCarga = r.erro;
      }
    });
  }

  Future<void> _encerrar(CaminhaoRegistrado c) async {
    setState(() => _avisoEncerrar = null);

    // Formulário: hora de início, hora de fim e volume efetivo.
    DateTime? inicioData = DateTime.now();
    TimeOfDay? inicioHora = TimeOfDay.now();
    DateTime? fimData = DateTime.now();
    TimeOfDay? fimHora = TimeOfDay.now();
    final volumeCtrl = TextEditingController(text: _fmtVolume(c.volume).replaceAll('.', ','));
    String? erroLocal;

    final dados = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Encerrar a descarga'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Registre a hora de início e a hora de fim da descarga '
                      '(horas de verdade). A hora de fim fecha a conta do prazo. '
                      'Isso não pode ser desfeito.',
                    ),
                    const SizedBox(height: 16),
                    const Text('Início da descarga', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: ctx,
                                initialDate: inicioData ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (d != null) setLocal(() => inicioData = d);
                            },
                            child: Text(inicioData == null
                                ? 'Data'
                                : '${_dois(inicioData!.day)}/${_dois(inicioData!.month)}/${inicioData!.year}'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final h = await showTimePicker(
                                context: ctx,
                                initialTime: inicioHora ?? TimeOfDay.now(),
                              );
                              if (h != null) setLocal(() => inicioHora = h);
                            },
                            child: Text(inicioHora == null ? 'Hora' : _fmtHora(inicioHora!)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('Fim da descarga', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: ctx,
                                initialDate: fimData ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (d != null) setLocal(() => fimData = d);
                            },
                            child: Text(fimData == null
                                ? 'Data'
                                : '${_dois(fimData!.day)}/${_dois(fimData!.month)}/${fimData!.year}'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final h = await showTimePicker(
                                context: ctx,
                                initialTime: fimHora ?? TimeOfDay.now(),
                              );
                              if (h != null) setLocal(() => fimHora = h);
                            },
                            child: Text(fimHora == null ? 'Hora' : _fmtHora(fimHora!)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: volumeCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Volume efetivamente descarregado (m³)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (erroLocal != null) ...[
                      const SizedBox(height: 8),
                      Text(erroLocal!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Voltar')),
                TextButton(
                  onPressed: () {
                    if (inicioData == null || inicioHora == null || fimData == null || fimHora == null) {
                      setLocal(() => erroLocal = 'Informe data e hora de início e de fim.');
                      return;
                    }
                    final vol = num.tryParse(volumeCtrl.text.trim().replaceAll(',', '.'));
                    if (vol == null || vol <= 0) {
                      setLocal(() => erroLocal = 'Informe o volume efetivamente descarregado.');
                      return;
                    }
                    final inicio = DateTime(
                      inicioData!.year, inicioData!.month, inicioData!.day,
                      inicioHora!.hour, inicioHora!.minute,
                    );
                    final fim = DateTime(
                      fimData!.year, fimData!.month, fimData!.day,
                      fimHora!.hour, fimHora!.minute,
                    );
                    if (fim.isBefore(inicio)) {
                      setLocal(() => erroLocal = 'Hora de fim anterior à de início é recusada.');
                      return;
                    }
                    Navigator.pop(ctx, {
                      'inicio': inicio,
                      'fim': fim,
                      'volume': vol,
                    });
                  },
                  child: const Text('Encerrar'),
                ),
              ],
            );
          },
        );
      },
    );
    volumeCtrl.dispose();
    if (dados == null || !mounted) return;

    setState(() => _encerrando = true);
    final r = await _repo.encerrarDescargaComFila(
      caminhaoId: c.id,
      descargaInicioEm: dados['inicio'] as DateTime,
      descargaFimEm: dados['fim'] as DateTime,
      volumeEfetivo: dados['volume'] as num,
    );
    if (!mounted) return;
    setState(() {
      _encerrando = false;
      if (r.ok) {
        if (r.dados != null) {
          _caminhao = r.dados;
          _cronometro.stop();
        } else {
          _avisoEncerrar = 'Sem rede: descarga guardada na fila offline e será enviada ao conectar.';
          _cronometro.stop();
        }
      } else {
        _avisoEncerrar = r.erro;
      }
    });
  }

  static String _fmtContagem(int segundos) {
    final s = segundos.abs();
    return '${segundos < 0 ? '-' : ''}${_dois(s ~/ 3600)}:${_dois((s % 3600) ~/ 60)}:${_dois(s % 60)}';
  }

  /// O bloco do prazo de descarga: contagem regressiva (ou o resultado, se
  /// a descarga já terminou), aviso e botão de encerrar.
  List<Widget> _blocoPrazo(CaminhaoRegistrado c) {
    final podeEncerrar = Session.instance.usuarioAtual?.perfil == Perfil.obra;
    final r = _restante;

    if (r == null) {
      final fora = c.foraDoPrazo;
      final inicioStr = c.descargaInicioEm != null ? _fmtDataHora(c.descargaInicioEm!) : '—';
      final fimStr = c.descargaFimEm != null ? _fmtDataHora(c.descargaFimEm!) : '—';
      final volStr = c.volumeEfetivo != null ? '${_fmtVolume(c.volumeEfetivo!)} m³' : '—';
      return [
        AppBanner(
          titulo: fora ? 'Descarga encerrada fora do prazo' : 'Descarga encerrada dentro do prazo',
          texto: fora
              ? 'Início $inicioStr · Fim $fimStr · Volume $volStr. Passou ${c.excedeuMinutos} min do prazo de ${c.prazoMinutos} min. O caminhão continua no sistema, marcado como fora do prazo, e aparece no lote e no relatório.'
              : 'Início $inicioStr · Fim $fimStr · Volume $volStr. Terminou dentro do prazo de ${c.prazoMinutos} min, contados do primeiro contato do cimento com a água.',
          tom: fora ? BannerTom.vermelho : BannerTom.verde,
        ),
        if (!c.recusado && Session.instance.usuarioAtual?.perfil == Perfil.obra) ...[
          const SizedBox(height: 10),
          PrimaryButton(
            texto: 'Moldar corpos de prova (amostra)',
            onPressed: _moldando ? null : () => _moldarAmostra(c),
          ),
        ],
      ];
    }

    final fase = _faseDe(r, c);
    final cor = fase == 'estourado' ? AppColors.red : (fase == 'atencao' ? AppColors.amber : AppColors.green);
    final fundo =
        fase == 'estourado' ? AppColors.redSoft : (fase == 'atencao' ? AppColors.amberSoft : AppColors.greenSoft);
    final total = c.prazoMinutos * 60;
    final progresso = total <= 0 ? 0.0 : (r / total).clamp(0.0, 1.0).toDouble();

    return [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: fundo, borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Text(
              fase == 'estourado' ? 'Prazo estourado há' : 'Tempo restante para descarregar',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: cor),
            ),
            const SizedBox(height: 4),
            Text(
              _fmtContagem(r),
              style: TextStyle(fontFamily: 'monospace', fontSize: 44, fontWeight: FontWeight.w700, color: cor),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(value: progresso, minHeight: 8, backgroundColor: Colors.white, color: cor),
            ),
            const SizedBox(height: 8),
            Text(
              'Prazo de ${c.prazoMinutos} min a partir do primeiro contato, às ${_dois(c.primeiroContatoEm.hour)}:${_dois(c.primeiroContatoEm.minute)}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      if (fase == 'atencao')
        AppBanner(
          titulo: 'Falta pouco',
          texto: 'Faltam ${(r / 60).ceil()} min para o fim do prazo. Termine a descarga.',
          tom: BannerTom.ambar,
        ),
      if (fase == 'estourado')
        const AppBanner(
          titulo: 'Prazo estourado',
          texto:
              'Este concreto passou do prazo. O caminhão não é bloqueado nem apagado: ao encerrar a descarga, ele fica registrado como fora do prazo.',
          tom: BannerTom.vermelho,
        ),
      if (_avisoEncerrar != null)
        AppBanner(titulo: 'Não foi possível encerrar', texto: _avisoEncerrar!, tom: BannerTom.vermelho),
      if (podeEncerrar)
        PrimaryButton(
          texto: _encerrando ? 'Encerrando...' : 'Encerrar descarga',
          perigo: fase == 'estourado',
          onPressed: _encerrando ? null : () => _encerrar(c),
        ),
      const SizedBox(height: 6),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = _caminhao;
    final carregando = c == null && _erroCarga == null;

    return AppShell(
      title: c == null ? 'Caminhão' : 'Nota ${c.numeroNota}',
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
          if (c != null) ...[
            ..._blocoPrazo(c),
            if (c.confere)
              AppBanner(
                titulo: widget.recemRegistrado ? 'Caminhão registrado' : 'A nota confere com o pedido',
                texto: widget.recemRegistrado
                    ? 'A nota confere com o pedido: nenhuma divergência.'
                    : 'Classe, fck, volume, central e destino batem com o pedido.',
                tom: BannerTom.verde,
              )
            else
              AppBanner(
                titulo: widget.recemRegistrado
                    ? 'Caminhão registrado, com divergências'
                    : 'A nota diverge do pedido',
                texto:
                    '${c.qtdDivergencias == 1 ? '1 divergência' : '${c.qtdDivergencias} divergências'} entre a nota e o pedido. Confira antes de descarregar.',
                tom: BannerTom.vermelho,
              ),

            const _Titulo('Nota × pedido'),
            ...c.conferencia.map((i) => _LinhaConferencia(item: i)),

            const _Titulo('Dados da nota'),
            InfoCard(children: [
              KvRow(label: 'Nota', value: c.numeroNota),
              KvRow(label: 'Central', value: c.centralNome),
              KvRow(label: 'Placa', value: c.placa),
              KvRow(label: 'Volume', value: '${_fmtVolume(c.volume)} m³'),
              KvRow(label: 'Traço', value: c.traco),
              if (c.consumoCimento != null)
                KvRow(label: 'Consumo de cimento', value: '${_fmtVolume(c.consumoCimento!)} kg/m³'),
              KvRow(label: 'Classe / fck na nota', value: '${c.classeNota} · ${c.fckNota} MPa'),
              KvRow(label: 'Aditivos', value: _aditivosTexto(c)),
              KvRow(label: 'Lote', value: c.loteNumero),
              KvRow(label: 'Pedido', value: 'nº ${c.pedidoNumero}'),
            ]),

            const _Titulo('Horários'),
            InfoCard(children: [
              KvRow(label: 'Primeiro contato (cimento + água)', value: _fmtDataHora(c.primeiroContatoEm)),
              KvRow(label: 'Chegada à obra', value: _fmtDataHora(c.chegadaObraEm)),
              KvRow(label: 'Entre um e outro', value: _duracao(c.chegadaObraEm.difference(c.primeiroContatoEm))),
            ]),
            
          ],
        ],
      ),
    );
  }

  static String _aditivosTexto(CaminhaoRegistrado c) {
    final itens = <String>[
      if (c.aditivos != null && c.aditivos!.isNotEmpty) c.aditivos!,
      if (c.aditivoRetardador) 'retardador',
    ];
    return itens.isEmpty ? 'nenhum' : itens.join(', ');
  }

  static String _duracao(Duration d) => '${d.inHours}h ${_dois(d.inMinutes % 60)}min';
}

/// Uma linha da comparação. Divergência fica em vermelho, com o motivo.
class _LinhaConferencia extends StatelessWidget {
  final ItemConferencia item;
  const _LinhaConferencia({required this.item});

  @override
  Widget build(BuildContext context) {
    final diverge = item.diverge;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: diverge ? AppColors.redSoft : Colors.white,
        border: Border.all(color: diverge ? AppColors.red : AppColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                diverge ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                size: 18,
                color: diverge ? AppColors.red : AppColors.green,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(item.rotulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              if (diverge) const StatusBadge(texto: 'divergência', cor: AppColors.red, fundo: Colors.white),
            ],
          ),
          const SizedBox(height: 6),
          Text('Pedido: ${item.pedido}', style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace')),
          const SizedBox(height: 2),
          Text('Nota: ${item.nota}', style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace')),
          if (diverge && item.detalhe != null) ...[
            const SizedBox(height: 6),
            Text(
              item.detalhe!,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF7C3020), height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}
