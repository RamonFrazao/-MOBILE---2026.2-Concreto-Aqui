import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/amostras_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

/// Consulta pela identificação única do corpo de prova.
/// Disponível para obra, construtora e laboratório.
class ConsultaCorpoProvaScreen extends StatefulWidget {
  final String? identificacaoInicial;
  final Color accent;

  const ConsultaCorpoProvaScreen({
    super.key,
    this.identificacaoInicial,
    this.accent = AppColors.accentObra,
  });

  @override
  State<ConsultaCorpoProvaScreen> createState() => _ConsultaCorpoProvaScreenState();
}

class _ConsultaCorpoProvaScreenState extends State<ConsultaCorpoProvaScreen> {
  final _repo = AmostrasRepository();
  final _ctrl = TextEditingController();
  bool _buscando = false;
  String? _erro;
  Map<String, dynamic>? _cadeia;

  @override
  void initState() {
    super.initState();
    if (widget.identificacaoInicial != null && widget.identificacaoInicial!.trim().isNotEmpty) {
      _ctrl.text = widget.identificacaoInicial!.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) => _buscar());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final cod = _ctrl.text.trim();
    if (cod.isEmpty) {
      setState(() {
        _erro = 'Informe a identificação do corpo de prova.';
        _cadeia = null;
      });
      return;
    }
    setState(() {
      _buscando = true;
      _erro = null;
      _cadeia = null;
    });
    final r = await _repo.buscarPorIdentificacao(cod);
    if (!mounted) return;
    setState(() {
      _buscando = false;
      if (r.ok) {
        _cadeia = r.dados;
      } else {
        _erro = r.erro;
      }
    });
  }

  Future<void> _compartilhar() async {
    final etiqueta = _cadeia?['etiqueta'] as String?;
    if (etiqueta == null || etiqueta.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: etiqueta));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Identificação copiada — cole na etiqueta ou compartilhe.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Corpo de prova',
      accent: widget.accent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const NoteText(
            'Cada corpo de prova tem identificação única. Por ela se chega à amostra, '
            'ao caminhão/nota, ao lote e às peças da obra — o laudo deixa de ser um número solto.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Identificação (ex.: CP-2026-00042)',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _buscar(),
          ),
          const SizedBox(height: 10),
          PrimaryButton(
            texto: _buscando ? 'Buscando…' : 'Consultar',
            onPressed: _buscando ? null : _buscar,
          ),
          if (_erro != null) ...[
            const SizedBox(height: 12),
            AppBanner(titulo: 'Não encontrado', texto: _erro!, tom: BannerTom.vermelho),
          ],
          if (_cadeia != null) ...[
            const SizedBox(height: 16),
            _CadeiaCard(cadeia: _cadeia!, onCompartilhar: _compartilhar),
          ],
        ],
      ),
    );
  }
}

class _CadeiaCard extends StatelessWidget {
  final Map<String, dynamic> cadeia;
  final VoidCallback onCompartilhar;

  const _CadeiaCard({required this.cadeia, required this.onCompartilhar});

  static String _rotuloSituacao(String? s) {
    switch (s) {
      case 'moldado':
        return 'moldado';
      case 'em_cura':
        return 'em cura';
      case 'em_remessa':
        return 'em remessa';
      case 'no_laboratorio':
        return 'no laboratório';
      case 'rompido':
        return 'rompido';
      case 'descartado':
        return 'descartado';
      default:
        return s ?? '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cp = cadeia['corpo_prova'] as Map<String, dynamic>? ?? {};
    final amostra = cadeia['amostra'] as Map<String, dynamic>? ?? {};
    final caminhao = cadeia['caminhao'] as Map<String, dynamic>? ?? {};
    final lote = cadeia['lote'] as Map<String, dynamic>? ?? {};
    final obra = cadeia['obra'] as Map<String, dynamic>? ?? {};
    final pecas = (cadeia['pecas'] as List? ?? []).cast<Map<String, dynamic>>();
    final irmaos = (amostra['corpos_prova'] as List? ?? []).cast<Map<String, dynamic>>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.greenSoft,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.green.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cp['identificacao'] as String? ?? '—',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 0.5),
              ),
              const SizedBox(height: 4),
              Text(
                'Idade: ${cp['idade'] ?? '—'} dias'
                '${cp['resultado'] != null ? ' · ${cp['resultado']} MPa' : ''}'
                ' · situação: ${_rotuloSituacao(cp['situacao'] as String?)}',
                style: const TextStyle(fontSize: 13, color: AppColors.inkSoft),
              ),
              if (cp['cura_inicio_em'] != null)
                Text('Cura iniciada: ${cp['cura_inicio_em']}',
                    style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
              if (cp['situacao'] == 'descartado' && cp['motivo_descarte'] != null)
                Text('Descarte: ${cp['motivo_descarte']}',
                    style: const TextStyle(fontSize: 12, color: AppColors.red)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        PrimaryButton(texto: 'Copiar etiqueta', onPressed: onCompartilhar),
        const SizedBox(height: 16),
        _Secao(
          titulo: 'Obra e peça',
          linhas: [
            'Obra: ${obra['nome'] ?? '—'}',
            if (obra['endereco'] != null) 'Endereço: ${obra['endereco']}',
            'Lote: ${lote['numero'] ?? '—'}'
                '${lote['data_concretagem'] != null ? ' · ${lote['data_concretagem']}' : ''}',
            if (lote['fck_projeto'] != null) 'fck projeto: ${lote['fck_projeto']} MPa',
            if (pecas.isEmpty)
              'Peças do lote: (nenhuma vinculada)'
            else
              'Peças: ${pecas.map((p) => p['rotulo'] ?? p['identificacao']).join(', ')}',
          ],
        ),
        _Secao(
          titulo: 'Caminhão e nota de origem',
          linhas: [
            'Nota: ${caminhao['numero_nota'] ?? '—'}',
            'Placa: ${caminhao['placa'] ?? '—'}',
            if (caminhao['central_nome'] != null) 'Central: ${caminhao['central_nome']}',
            if (caminhao['classe_nota'] != null)
              'Classe/fck nota: ${caminhao['classe_nota']} / ${caminhao['fck_nota']} MPa',
            if (caminhao['volume_efetivo'] != null)
              'Volume efetivo: ${caminhao['volume_efetivo']} m³'
            else if (caminhao['volume'] != null)
              'Volume: ${caminhao['volume']} m³',
            if (caminhao['fora_do_prazo'] == true) 'Situação: fora do prazo de descarga',
            if (caminhao['recusado'] == true) 'Situação: recusado',
          ],
        ),
        _Secao(
          titulo: 'Amostra (irmãos desta moldagem)',
          linhas: irmaos
              .map((i) =>
                  '${i['identificacao']} · ${i['idade']} dias'
                  '${i['resultado'] != null ? ' · ${i['resultado']} MPa' : ''}')
              .toList(),
        ),
      ],
    );
  }
}

class _Secao extends StatelessWidget {
  final String titulo;
  final List<String> linhas;

  const _Secao({required this.titulo, required this.linhas});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.inkSoft)),
            const SizedBox(height: 6),
            for (final l in linhas)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(l, style: const TextStyle(fontSize: 13.5)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Lista corpos de prova que cobrem uma peça específica.
class CorposDaPecaScreen extends StatefulWidget {
  final int pecaId;
  final Color accent;

  const CorposDaPecaScreen({
    super.key,
    required this.pecaId,
    this.accent = AppColors.accentConstrutora,
  });

  @override
  State<CorposDaPecaScreen> createState() => _CorposDaPecaScreenState();
}

class _CorposDaPecaScreenState extends State<CorposDaPecaScreen> {
  final _repo = AmostrasRepository();
  bool _carregando = true;
  String? _erro;
  Map<String, dynamic>? _dados;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    final r = await _repo.porPeca(widget.pecaId);
    if (!mounted) return;
    setState(() {
      _carregando = false;
      if (r.ok) {
        _dados = r.dados;
      } else {
        _erro = r.erro;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final peca = _dados?['peca'] as Map<String, dynamic>?;
    final lista = (_dados?['corpos_prova'] as List? ?? []).cast<Map<String, dynamic>>();

    return AppShell(
      title: peca != null ? (peca['rotulo'] as String? ?? 'Peça') : 'Corpos de prova da peça',
      accent: widget.accent,
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? AppBanner(titulo: 'Erro', texto: _erro!, tom: BannerTom.vermelho)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (peca != null)
                      NoteText(
                        '${peca['obra'] ?? ''} · ${peca['pavimento'] ?? ''} · '
                        '${lista.length} corpo(s) de prova cobrindo esta peça.',
                      ),
                    const SizedBox(height: 10),
                    if (lista.isEmpty)
                      const Text('Nenhum corpo de prova vinculado a esta peça ainda.',
                          style: TextStyle(color: AppColors.inkSoft))
                    else
                      for (final cp in lista)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: MenuRow(
                            titulo: cp['identificacao'] as String? ?? '—',
                            subtitulo:
                                '${cp['idade']} dias · lote ${(cp['lote'] as Map?)?['numero'] ?? '—'} · '
                                'nota ${(cp['caminhao'] as Map?)?['numero_nota'] ?? '—'}'
                                '${cp['resultado'] != null ? ' · ${cp['resultado']} MPa' : ''}',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ConsultaCorpoProvaScreen(
                                  identificacaoInicial: cp['identificacao'] as String?,
                                  accent: widget.accent,
                                ),
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
    );
  }
}
