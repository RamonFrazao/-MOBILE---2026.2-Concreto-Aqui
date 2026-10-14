import 'package:flutter/material.dart';
import '../../services/pedidos_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

const _accent = AppColors.accentConstrutora;

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

// ---------------------------------------------------------------------
// Lista de pedidos, agrupada por obra
// ---------------------------------------------------------------------

class PedidosScreen extends StatefulWidget {
  const PedidosScreen({super.key});

  @override
  State<PedidosScreen> createState() => _PedidosScreenState();
}

class _PedidosScreenState extends State<PedidosScreen> {
  final _repo = PedidosRepository();

  List<Pedido>? _pedidos;
  String? _erroCarga;
  String? _aviso; // motivo, quando a API recusa um cancelamento

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final r = await _repo.listar();
    if (!mounted) return;
    setState(() {
      if (r.ok) _pedidos = r.dados;
      _erroCarga = r.ok ? null : r.erro;
    });
  }

  Future<void> _novo() async {
    final criou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const NovoPedidoScreen()),
    );
    if (criou == true) {
      setState(() => _aviso = null);
      await _carregar();
    }
  }

  Future<void> _cancelar(Pedido p) async {
    setState(() => _aviso = null);
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar pedido?'),
        content: Text('O pedido ${p.numero} (${_fmtVolume(p.volume)} m³ de ${p.classeNome}) será cancelado.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancelar pedido')),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    final r = await _repo.cancelar(p.id);
    if (!mounted) return;
    // Se já chegou caminhão, a API recusa e a tela mostra o motivo.
    if (!r.ok) setState(() => _aviso = r.erro);
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final pedidos = _pedidos;
    final carregando = pedidos == null && _erroCarga == null;

    // Agrupa por obra, mantendo a ordem em que a API devolveu.
    final grupos = <int, List<Pedido>>{};
    if (pedidos != null) {
      for (final p in pedidos) {
        grupos.putIfAbsent(p.obraId, () => []).add(p);
      }
    }

    return AppShell(
      title: 'Pedidos',
      accent: _accent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const NoteText(
              'O pedido registra o que foi comprado. É a referência da conferência na chegada: nota com fck diferente do pedido é divergência.'),
          const SizedBox(height: 10),
          PrimaryButton(texto: 'Novo pedido', onPressed: _novo),
          const SizedBox(height: 12),
          if (_erroCarga != null)
            AppBanner(titulo: 'Não foi possível carregar', texto: _erroCarga!, tom: BannerTom.vermelho),
          if (_aviso != null)
            AppBanner(titulo: 'Não foi possível cancelar', texto: _aviso!, tom: BannerTom.vermelho),
          if (carregando)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (pedidos != null && pedidos.isEmpty) const NoteText('Nenhum pedido registrado ainda.'),
          for (final grupo in grupos.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 8),
              child: Text(
                grupo.value.first.obraNome,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            ...grupo.value.map((p) => _PedidoTile(pedido: p, onCancelar: () => _cancelar(p))),
          ],
        ],
      ),
    );
  }
}

class _PedidoTile extends StatelessWidget {
  final Pedido pedido;
  final VoidCallback onCancelar;

  const _PedidoTile({required this.pedido, required this.onCancelar});

  @override
  Widget build(BuildContext context) {
    final p = pedido;

    final String rotulo;
    final Color cor;
    final Color fundo;
    if (p.cancelado) {
      rotulo = 'Cancelado';
      cor = AppColors.red;
      fundo = AppColors.redSoft;
    } else if (p.volumeEntregue >= p.volume) {
      rotulo = 'Entregue';
      cor = AppColors.green;
      fundo = AppColors.greenSoft;
    } else if (p.volumeEntregue > 0) {
      rotulo = 'Em entrega';
      cor = AppColors.amber;
      fundo = AppColors.amberSoft;
    } else {
      rotulo = 'Aguardando';
      cor = AppColors.inkSoft;
      fundo = const Color(0xFFEDEEE8);
    }

    final progresso = (p.volumeEntregue / p.volume).clamp(0.0, 1.0).toDouble();
    final caminhoes = p.qtdCaminhoes == 1 ? '1 caminhão' : '${p.qtdCaminhoes} caminhões';

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
          Row(
            children: [
              Expanded(
                child: Text(
                  'Pedido nº ${p.numero}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
              ),
              StatusBadge(texto: rotulo, cor: cor, fundo: fundo),
            ],
          ),
          const SizedBox(height: 6),
          Text(p.classeResumo, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(
            '${p.centralNome} · ${p.pecaRotulo} (${p.pavimentoNome})',
            style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
          ),
          const SizedBox(height: 2),
          Text(
            'Previsto: ${_fmtDataHora(p.previstaPara)}',
            style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
          ),
          const SizedBox(height: 10),
          Text(
            'Entregue: ${_fmtVolume(p.volumeEntregue)} de ${_fmtVolume(p.volume)} m³ · $caminhoes',
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progresso,
              minHeight: 6,
              backgroundColor: const Color(0xFFEBEBE4),
              color: p.cancelado ? AppColors.red : AppColors.green,
            ),
          ),
          if (!p.cancelado) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: onCancelar,
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
                child: Text(p.qtdCaminhoes > 0 ? 'Cancelar (com caminhão)' : 'Cancelar pedido'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Novo pedido
// ---------------------------------------------------------------------

class NovoPedidoScreen extends StatefulWidget {
  const NovoPedidoScreen({super.key});

  @override
  State<NovoPedidoScreen> createState() => _NovoPedidoScreenState();
}

class _NovoPedidoScreenState extends State<NovoPedidoScreen> {
  final _repo = PedidosRepository();

  OpcoesPedido? _opcoes;
  String? _erroCarga;

  int? _centralId;
  int? _classeId;
  int? _pecaId;
  final _volumeCtrl = TextEditingController();
  DateTime? _data;
  TimeOfDay? _hora;

  String? _erroForm;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _volumeCtrl.dispose();
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
      firstDate: DateTime(hoje.year, hoje.month, hoje.day),
      lastDate: DateTime(hoje.year + 2),
    );
    if (d != null && mounted) setState(() => _data = d);
  }

  Future<void> _escolherHora() async {
    final h = await showTimePicker(context: context, initialTime: _hora ?? TimeOfDay.now());
    if (h != null && mounted) setState(() => _hora = h);
  }

  Future<void> _salvar() async {
    final centralId = _centralId;
    final classeId = _classeId;
    final pecaId = _pecaId;
    final data = _data;
    final hora = _hora;
    final volume = num.tryParse(_volumeCtrl.text.trim().replaceAll(',', '.'));

    if (centralId == null ||
        classeId == null ||
        pecaId == null ||
        data == null ||
        hora == null ||
        volume == null) {
      setState(() => _erroForm =
          'Escolha a central, a classe, a peça de destino, a data e a hora previstas, e informe o volume em m³.');
      return;
    }

    setState(() {
      _erroForm = null;
      _salvando = true;
    });

    // Volume zero ou negativo segue para a API de propósito: é ela quem
    // decide e devolve a mensagem.
    final r = await _repo.criar(
      centralId: centralId,
      classeId: classeId,
      pecaId: pecaId,
      volume: volume,
      previstaPara: DateTime(data.year, data.month, data.day, hora.hour, hora.minute),
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

    return AppShell(
      title: 'Novo pedido',
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
            const _Rotulo('Central'),
            if (o.centrais.isEmpty)
              const NoteText('Nenhuma central ativa. Cadastre uma em "Centrais e laboratórios".')
            else
              DropdownButtonFormField<int>(
                value: _centralId,
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
            const SizedBox(height: 14),
            const _Rotulo('Classe'),
            if (o.classes.isEmpty)
              const NoteText('Nenhuma classe cadastrada. Cadastre uma em "Classes de concreto".')
            else
              DropdownButtonFormField<int>(
                value: _classeId,
                isExpanded: true,
                hint: const Text('Escolha a classe'),
                items: o.classes
                    .map((c) => DropdownMenuItem<int>(
                          value: c.id,
                          child: Text(c.resumo, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _classeId = v),
              ),
            const SizedBox(height: 14),
            const _Rotulo('Peça de destino'),
            if (o.pecas.isEmpty)
              const NoteText('Nenhuma peça cadastrada. Cadastre em "Obras e peças".')
            else
              DropdownButtonFormField<int>(
                value: _pecaId,
                isExpanded: true,
                hint: const Text('Escolha a peça'),
                items: o.pecas
                    .map((p) => DropdownMenuItem<int>(
                          value: p.id,
                          child: Text(p.rotulo, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _pecaId = v),
              ),
            const SizedBox(height: 14),
            const _Rotulo('Volume (m³)'),
            TextField(
              controller: _volumeCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(hintText: 'ex.: 8'),
            ),
            const SizedBox(height: 14),
            const _Rotulo('Data e hora previstas'),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _escolherData,
                    child: Text(_data == null ? 'Escolher data' : _fmtData(_data!)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _escolherHora,
                    child: Text(_hora == null ? 'Escolher hora' : _fmtHora(_hora!)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_erroForm != null)
              AppBanner(titulo: 'Não foi possível registrar', texto: _erroForm!, tom: BannerTom.vermelho),
            PrimaryButton(
              texto: _salvando ? 'Salvando...' : 'Registrar pedido',
              onPressed: _salvando ? null : _salvar,
            ),
          ],
        ],
      ),
    );
  }
}
