import 'package:flutter/material.dart';
import '../../services/cadastros_repository.dart';
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
  final bool senha;

  const _Campo({required this.rotulo, required this.controller, this.dica, this.senha = false});

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
            obscureText: senha,
            decoration: InputDecoration(hintText: dica),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Lista de centrais e laboratórios
// ---------------------------------------------------------------------

class CadastrosScreen extends StatefulWidget {
  const CadastrosScreen({super.key});

  @override
  State<CadastrosScreen> createState() => _CadastrosScreenState();
}

class _CadastrosScreenState extends State<CadastrosScreen> {
  final _repo = CadastrosRepository();

  List<Central>? _centrais;
  List<Laboratorio>? _laboratorios;
  String? _erroCarga;

  final _centralNomeCtrl = TextEditingController();
  final _centralCnpjCtrl = TextEditingController();
  final _centralContatoCtrl = TextEditingController();
  String? _erroCentral;
  bool _salvandoCentral = false;
  String? _avisoCentral;

  final _labNomeCtrl = TextEditingController();
  final _labCnpjCtrl = TextEditingController();
  final _labContatoCtrl = TextEditingController();
  String? _erroLab;
  bool _salvandoLab = false;
  String? _avisoLab;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final rc = await _repo.listarCentrais();
    final rl = await _repo.listarLaboratorios();
    if (!mounted) return;
    setState(() {
      if (rc.ok) _centrais = rc.dados;
      if (rl.ok) _laboratorios = rl.dados;
      _erroCarga = !rc.ok ? rc.erro : (!rl.ok ? rl.erro : null);
    });
  }

  Future<void> _cadastrarCentral() async {
    setState(() {
      _erroCentral = null;
      _salvandoCentral = true;
    });
    final r = await _repo.criarCentral(
      nome: _centralNomeCtrl.text.trim(),
      cnpj: _centralCnpjCtrl.text.trim(),
      contato: _centralContatoCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _salvandoCentral = false);
    if (!r.ok) {
      setState(() => _erroCentral = r.erro);
      return;
    }
    _centralNomeCtrl.clear();
    _centralCnpjCtrl.clear();
    _centralContatoCtrl.clear();
    await _carregar();
  }

  Future<void> _alternarAtivoCentral(Central c) async {
    final r = await _repo.definirAtivoCentral(c.id, !c.ativo);
    if (!mounted) return;
    if (!r.ok) setState(() => _avisoCentral = r.erro);
    await _carregar();
  }

  Future<void> _excluirCentral(Central c) async {
    setState(() => _avisoCentral = null);
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir central?'),
        content: Text('A central "${c.nome}" será excluída. Isso não pode ser desfeito.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    final r = await _repo.excluirCentral(c.id);
    if (!mounted) return;
    if (!r.ok) setState(() => _avisoCentral = r.erro);
    await _carregar();
  }

  Future<void> _cadastrarLaboratorio() async {
    setState(() {
      _erroLab = null;
      _salvandoLab = true;
    });
    final r = await _repo.criarLaboratorio(
      nome: _labNomeCtrl.text.trim(),
      cnpj: _labCnpjCtrl.text.trim(),
      contato: _labContatoCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _salvandoLab = false);
    if (!r.ok) {
      setState(() => _erroLab = r.erro);
      return;
    }
    _labNomeCtrl.clear();
    _labCnpjCtrl.clear();
    _labContatoCtrl.clear();
    await _carregar();
  }

  Future<void> _alternarAtivoLaboratorio(Laboratorio l) async {
    final r = await _repo.definirAtivoLaboratorio(l.id, !l.ativo);
    if (!mounted) return;
    if (!r.ok) setState(() => _avisoLab = r.erro);
    await _carregar();
  }

  Future<void> _excluirLaboratorio(Laboratorio l) async {
    setState(() => _avisoLab = null);
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir laboratório?'),
        content: Text('O laboratório "${l.nome}" será excluído. Isso não pode ser desfeito.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    final r = await _repo.excluirLaboratorio(l.id);
    if (!mounted) return;
    if (!r.ok) setState(() => _avisoLab = r.erro);
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final centrais = _centrais;
    final laboratorios = _laboratorios;
    final carregando = centrais == null && laboratorios == null && _erroCarga == null;

    return AppShell(
      title: 'Centrais e laboratórios',
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

          // ---------------- Centrais ----------------
          const _Titulo('Centrais'),
          const NoteText('A central vende o concreto. É só cadastro — nunca tem tela nem login no sistema.'),
          if (_avisoCentral != null)
            AppBanner(titulo: 'Não foi possível concluir', texto: _avisoCentral!, tom: BannerTom.vermelho),
          if (centrais != null && centrais.isEmpty) const NoteText('Nenhuma central cadastrada ainda.'),
          if (centrais != null)
            ...centrais.map((c) => _CadastroTile(
                  nome: c.nome,
                  linha2: 'CNPJ ${c.cnpj} · ${c.contato}',
                  linha3: '${c.qtdCaminhoes} caminhão(ões) registrados',
                  ativo: c.ativo,
                  bloqueado: c.qtdCaminhoes > 0,
                  onAlternarAtivo: () => _alternarAtivoCentral(c),
                  onExcluir: () => _excluirCentral(c),
                )),
          const SizedBox(height: 8),
          _Campo(rotulo: 'Nome da central', controller: _centralNomeCtrl, dica: 'ex.: Central Concrelama'),
          _Campo(rotulo: 'CNPJ', controller: _centralCnpjCtrl, dica: 'ex.: 11.222.333/0001-44'),
          _Campo(rotulo: 'Contato', controller: _centralContatoCtrl, dica: 'ex.: (87) 99900-1122'),
          if (_erroCentral != null)
            AppBanner(titulo: 'Não foi possível cadastrar', texto: _erroCentral!, tom: BannerTom.vermelho),
          PrimaryButton(
            texto: _salvandoCentral ? 'Salvando...' : 'Cadastrar central',
            onPressed: _salvandoCentral ? null : _cadastrarCentral,
          ),

          // ---------------- Laboratórios ----------------
          const _Titulo('Laboratórios'),
          const NoteText(
              'O laboratório ensaia o concreto. Depois de cadastrado, pode receber um usuário de acesso com perfil de laboratório.'),
          if (_avisoLab != null)
            AppBanner(titulo: 'Não foi possível concluir', texto: _avisoLab!, tom: BannerTom.vermelho),
          if (laboratorios != null && laboratorios.isEmpty) const NoteText('Nenhum laboratório cadastrado ainda.'),
          if (laboratorios != null)
            ...laboratorios.map((l) => _CadastroTile(
                  nome: l.nome,
                  linha2: 'CNPJ ${l.cnpj} · ${l.contato}',
                  linha3: l.qtdUsuarios > 0
                      ? '${l.qtdUsuarios} usuário(s) de acesso'
                      : 'nenhum usuário de acesso ainda',
                  ativo: l.ativo,
                  bloqueado: l.qtdUsuarios > 0,
                  onAlternarAtivo: () => _alternarAtivoLaboratorio(l),
                  onExcluir: () => _excluirLaboratorio(l),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => LaboratorioUsuariosScreen(laboratorio: l)),
                  ),
                )),
          const SizedBox(height: 8),
          _Campo(rotulo: 'Nome do laboratório', controller: _labNomeCtrl, dica: 'ex.: Laboratório UAST'),
          _Campo(rotulo: 'CNPJ', controller: _labCnpjCtrl, dica: 'ex.: 22.333.444/0001-55'),
          _Campo(rotulo: 'Contato', controller: _labContatoCtrl, dica: 'ex.: (87) 99700-5566'),
          if (_erroLab != null)
            AppBanner(titulo: 'Não foi possível cadastrar', texto: _erroLab!, tom: BannerTom.vermelho),
          PrimaryButton(
            texto: _salvandoLab ? 'Salvando...' : 'Cadastrar laboratório',
            onPressed: _salvandoLab ? null : _cadastrarLaboratorio,
          ),
        ],
      ),
    );
  }
}

class _CadastroTile extends StatelessWidget {
  final String nome;
  final String linha2;
  final String linha3;
  final bool ativo;
  final bool bloqueado;
  final VoidCallback onAlternarAtivo;
  final VoidCallback onExcluir;
  final VoidCallback? onTap;

  const _CadastroTile({
    required this.nome,
    required this.linha2,
    required this.linha3,
    required this.ativo,
    required this.bloqueado,
    required this.onAlternarAtivo,
    required this.onExcluir,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(11),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(nome, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                ),
                StatusBadge(
                  texto: ativo ? 'Ativo' : 'Desativado',
                  cor: ativo ? AppColors.green : AppColors.inkSoft,
                  fundo: ativo ? AppColors.greenSoft : const Color(0xFFEDEEE8),
                ),
                if (onTap != null) const Icon(Icons.chevron_right, size: 18, color: AppColors.inkSoft),
              ],
            ),
            const SizedBox(height: 4),
            Text(linha2, style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
            const SizedBox(height: 2),
            Text(linha3, style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onAlternarAtivo,
                    child: Text(ativo ? 'Desativar' : 'Ativar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onExcluir,
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
                    child: Text(bloqueado ? 'Excluir (com movimento)' : 'Excluir'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Usuário de acesso do laboratório
// ---------------------------------------------------------------------

class LaboratorioUsuariosScreen extends StatefulWidget {
  final Laboratorio laboratorio;
  const LaboratorioUsuariosScreen({super.key, required this.laboratorio});

  @override
  State<LaboratorioUsuariosScreen> createState() => _LaboratorioUsuariosScreenState();
}

class _LaboratorioUsuariosScreenState extends State<LaboratorioUsuariosScreen> {
  final _repo = CadastrosRepository();
  List<UsuarioLab>? _usuarios;
  String? _erroCarga;

  final _usernameCtrl = TextEditingController();
  final _senhaCtrl = TextEditingController();
  final _nomeCtrl = TextEditingController();
  String? _erroForm;
  String? _sucesso;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final r = await _repo.listarUsuariosLaboratorio(widget.laboratorio.id);
    if (!mounted) return;
    setState(() {
      if (r.ok) _usuarios = r.dados;
      _erroCarga = r.ok ? null : r.erro;
    });
  }

  Future<void> _criar() async {
    setState(() {
      _erroForm = null;
      _sucesso = null;
      _salvando = true;
    });
    final r = await _repo.criarUsuarioLaboratorio(
      laboratorioId: widget.laboratorio.id,
      username: _usernameCtrl.text.trim(),
      senha: _senhaCtrl.text.trim(),
      nome: _nomeCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _salvando = false);
    if (!r.ok) {
      setState(() => _erroForm = r.erro);
      return;
    }
    final username = r.dados!.username;
    _usernameCtrl.clear();
    _senhaCtrl.clear();
    _nomeCtrl.clear();
    setState(() => _sucesso = 'Usuário "$username" criado. Já pode entrar com o perfil de laboratório.');
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final usuarios = _usuarios;
    return AppShell(
      title: widget.laboratorio.nome,
      accent: _accent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoCard(children: [
            KvRow(label: 'CNPJ', value: widget.laboratorio.cnpj),
            KvRow(label: 'Contato', value: widget.laboratorio.contato),
          ]),
          const _Titulo('Usuários de acesso'),
          if (_erroCarga != null)
            AppBanner(titulo: 'Não foi possível carregar', texto: _erroCarga!, tom: BannerTom.vermelho),
          if (usuarios != null && usuarios.isEmpty)
            const NoteText('Nenhum usuário de acesso ainda — crie um abaixo para liberar o login deste laboratório.'),
          if (usuarios != null)
            ...usuarios.map((u) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.line),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(u.nome, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            Text('usuário: ${u.username}',
                                style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft, fontFamily: 'monospace')),
                          ],
                        ),
                      ),
                      const StatusBadge(texto: 'laboratório', cor: AppColors.green, fundo: AppColors.greenSoft),
                    ],
                  ),
                )),

          const _Titulo('Criar novo usuário de acesso'),
          _Campo(rotulo: 'Nome', controller: _nomeCtrl, dica: 'ex.: Laboratorista responsável'),
          _Campo(rotulo: 'Usuário', controller: _usernameCtrl, dica: 'ex.: lab-uast'),
          _Campo(rotulo: 'Senha', controller: _senhaCtrl, dica: 'mínimo 4 caracteres', senha: true),
          if (_erroForm != null)
            AppBanner(titulo: 'Não foi possível criar', texto: _erroForm!, tom: BannerTom.vermelho),
          if (_sucesso != null) AppBanner(titulo: 'Usuário criado', texto: _sucesso!, tom: BannerTom.verde),
          PrimaryButton(
            texto: _salvando ? 'Salvando...' : 'Criar usuário de acesso',
            onPressed: _salvando ? null : _criar,
          ),
        ],
      ),
    );
  }
}
