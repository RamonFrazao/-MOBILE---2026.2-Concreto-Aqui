import 'package:flutter/material.dart';
import '../../services/fila_offline.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

const _accent = AppColors.accentObra;

class FilaOfflineScreen extends StatefulWidget {
  const FilaOfflineScreen({super.key});

  @override
  State<FilaOfflineScreen> createState() => _FilaOfflineScreenState();
}

class _FilaOfflineScreenState extends State<FilaOfflineScreen> {
  final _fila = FilaOffline.instance;

  @override
  void initState() {
    super.initState();
    _fila.carregar();
    _fila.addListener(_onChange);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _fila.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final itens = _fila.itens.reversed.toList();
    return AppShell(
      title: 'Fila offline',
      accent: _accent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${_fila.pendentes} pendente(s)'
            '${_fila.comErro > 0 ? ' · ${_fila.comErro} com erro' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          PrimaryButton(
            texto: _fila.enviando ? 'Enviando…' : 'Enviar fila agora',
            onPressed: _fila.enviando ? null : () => _fila.enviarPendentes(forcar: true),
          ),
          const SizedBox(height: 12),
          if (itens.isEmpty)
            const Text('Fila vazia.', style: TextStyle(color: AppColors.inkSoft))
          else
            Expanded(
              child: ListView.builder(
                itemCount: itens.length,
                itemBuilder: (_, i) {
                  final it = itens[i];
                  final cor = switch (it.status) {
                    FilaStatus.enviado => AppColors.green,
                    FilaStatus.erro => AppColors.red,
                    FilaStatus.pendente => AppColors.amber,
                  };
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(it.rotulo, style: const TextStyle(fontSize: 13.5)),
                      subtitle: Text(
                        '${it.status.name} · ${it.clientId.substring(0, 8)}…'
                        '${it.erro != null ? '\n${it.erro}' : ''}',
                        style: TextStyle(fontSize: 12, color: cor),
                      ),
                      isThreeLine: it.erro != null,
                      trailing: it.status == FilaStatus.erro
                          ? IconButton(
                              icon: const Icon(Icons.refresh),
                              onPressed: () => _fila.tentarDeNovo(it.clientId),
                            )
                          : null,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
