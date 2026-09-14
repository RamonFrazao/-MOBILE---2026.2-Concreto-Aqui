import 'package:flutter/material.dart';
import '../models/domain_models.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';
import '../screens/login_screen.dart';

/// Casca comum de tela: barra colorida por perfil, "Sair" só nas telas
/// iniciais de cada perfil, botão de voltar automático nas demais.
class AppShell extends StatelessWidget {
  final String title;
  final Color accent;
  final Widget body;
  final Widget? footer;
  final bool isHome;

  const AppShell({
    super.key,
    required this.title,
    required this.accent,
    required this.body,
    this.footer,
    this.isHome = false,
  });

  Future<void> _sair(BuildContext context) async {
    await Session.instance.encerrar();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: !isHome,
        title: Text(title),
        actions: isHome
            ? [
                TextButton(
                  onPressed: () => _sair(context),
                  child: const Text('Sair', style: TextStyle(color: Colors.white)),
                ),
              ]
            : null,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: body,
        ),
      ),
      bottomNavigationBar: footer == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: footer,
              ),
            ),
    );
  }
}

/// Linha discreta mostrando quem está logado — mesma ideia da "Sessão: ..."
/// do protótipo em HTML.
class SessionLine extends StatelessWidget {
  const SessionLine({super.key});

  @override
  Widget build(BuildContext context) {
    final u = Session.instance.usuarioAtual;
    if (u == null) return const SizedBox.shrink();
    final tenant = u.construtora != null ? ' · ${u.construtora}' : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        'Sessão: ${u.nome}$tenant — guardada no aparelho, sem pedir login de novo.',
        style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft, height: 1.4),
      ),
    );
  }
}

/// Botão de linha de menu (como um ListTile com borda e chevron).
class MenuRow extends StatelessWidget {
  final String titulo;
  final String? subtitulo;
  final Widget? trailing;
  final VoidCallback? onTap;

  const MenuRow({
    super.key,
    required this.titulo,
    this.subtitulo,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                      if (subtitulo != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitulo!, style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
                      ],
                    ],
                  ),
                ),
                trailing ?? const Icon(Icons.chevron_right, size: 18, color: AppColors.inkSoft),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Linha chave/valor (rótulo à esquerda, valor em mono à direita).
class KvRow extends StatelessWidget {
  final String label;
  final String value;

  const KvRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.inkSoft, fontSize: 13)),
          Text(value,
              style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'monospace', fontSize: 13)),
        ],
      ),
    );
  }
}

/// Cartão com borda fina, para agrupar KvRows.
class InfoCard extends StatelessWidget {
  final List<Widget> children;
  const InfoCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: children),
    );
  }
}

enum BannerTom { verde, ambar, vermelho }

/// Bloco de aviso colorido (equivalente ao `.banner` do protótipo).
class AppBanner extends StatelessWidget {
  final String titulo;
  final String texto;
  final BannerTom tom;

  const AppBanner({super.key, required this.titulo, required this.texto, this.tom = BannerTom.verde});

  @override
  Widget build(BuildContext context) {
    final (fundo, cor) = switch (tom) {
      BannerTom.verde => (AppColors.greenSoft, const Color(0xFF245A3E)),
      BannerTom.ambar => (AppColors.amberSoft, const Color(0xFF7A551A)),
      BannerTom.vermelho => (AppColors.redSoft, const Color(0xFF7C3020)),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(color: fundo, borderRadius: BorderRadius.circular(11)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: TextStyle(color: cor, fontWeight: FontWeight.w700, fontSize: 13.5)),
          const SizedBox(height: 2),
          Text(texto, style: TextStyle(color: cor, fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }
}

/// Nota discreta de rodapé de tela (equivalente ao `<p class="note">`).
class NoteText extends StatelessWidget {
  final String texto;
  const NoteText(this.texto, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(texto, style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft, height: 1.5)),
    );
  }
}

class StatusBadge extends StatelessWidget {
  final String texto;
  final Color cor;
  final Color fundo;

  const StatusBadge({super.key, required this.texto, required this.cor, required this.fundo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: fundo, borderRadius: BorderRadius.circular(999)),
      child: Text(texto, style: TextStyle(color: cor, fontWeight: FontWeight.w600, fontSize: 11)),
    );
  }
}

class StatusInfo {
  final String label;
  final Color cor;
  final Color fundo;
  const StatusInfo(this.label, this.cor, this.fundo);
}

StatusInfo statusInfoFor(StatusLote status) {
  switch (status) {
    case StatusLote.aguardandoCaminhao:
      return const StatusInfo('Aguardando caminhão', AppColors.inkSoft, Color(0xFFEDEEE8));
    case StatusLote.aguardandoResultados:
      return const StatusInfo('Aguardando resultados', AppColors.inkSoft, Color(0xFFEDEEE8));
    case StatusLote.aguardandoAceitacao:
      return const StatusInfo('Aguardando aceitação', AppColors.amber, AppColors.amberSoft);
    case StatusLote.aceito:
      return const StatusInfo('Aceito', AppColors.green, AppColors.greenSoft);
    case StatusLote.reprovado:
      return const StatusInfo('Reprovado', AppColors.red, AppColors.redSoft);
  }
}

class PrimaryButton extends StatelessWidget {
  final String texto;
  final VoidCallback? onPressed;
  final bool perigo;

  const PrimaryButton({super.key, required this.texto, required this.onPressed, this.perigo = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: perigo ? AppColors.red : AppColors.ink,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        ),
        onPressed: onPressed,
        child: Text(texto, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}
