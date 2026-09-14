import '../models/domain_models.dart';

/// Resultado de uma busca de lote por código.
/// Como o mock só guarda os lotes da construtora logada, qualquer código
/// fora dessa lista representa, de propósito, "lote de outra construtora" —
/// é assim que este protótipo demonstra a recusa que a API real fará.
class BuscaLoteResultado {
  final Lote? lote;
  final String? erro;
  const BuscaLoteResultado.encontrado(Lote this.lote) : erro = null;
  const BuscaLoteResultado.negado()
      : lote = null,
        erro =
            'Acesso negado: este lote pertence a outra construtora, ou não existe.';

  bool get ok => lote != null;
}

/// Fonte de dados única do protótipo, hoje 100% em memória.
/// Quando a API entrar (E2), estes métodos estáticos viram chamadas HTTP,
/// sem precisar reescrever as telas que os usam.
class MockDb {
  MockDb._();

  static final List<Usuario> usuarios = [
    const Usuario(
      username: 'construtora',
      senha: '1234',
      perfil: Perfil.construtora,
      nome: 'Escritório técnico',
      construtora: 'Construtora Bom Conselho',
    ),
    const Usuario(
      username: 'tecnico',
      senha: '1234',
      perfil: Perfil.obra,
      nome: 'Técnico no canteiro',
    ),
    const Usuario(
      username: 'lab',
      senha: '1234',
      perfil: Perfil.laboratorio,
      nome: 'Laboratorista',
    ),
  ];

  static final List<ClasseConcreto> classes = [
    const ClasseConcreto(
        id: 'c25', nome: 'C25', fck: 25, abatimento: '100 ± 20 mm', agregado: '19 mm'),
    const ClasseConcreto(
        id: 'c30', nome: 'C30', fck: 30, abatimento: '90 ± 20 mm', agregado: '19 mm'),
  ];

  static const nomeObra = 'Residencial Bom Conselho';
  static const pavimento = '3º pavimento';
  static final List<String> pecas = [
    'Pilares P1 a P12',
    'Laje do 2º pavimento L-201',
  ];

  static const centrais = ['Central Concrelama — BR-232, km 12'];
  static const laboratorios = ['Laboratório UAST'];

  static final List<Lote> lotes = [
    Lote(
      id: 'l1',
      numero: '12/03',
      peca: 'Pilares do 3º pavimento',
      classeId: 'c25',
      volume: 8,
      caminhoesPlanejados: 4,
      status: StatusLote.aceito,
      caminhoes: [
        Caminhao(placa: 'QRZ-4C18', nota: '45.812', horaContato: '08:05', status: 'aceito'),
      ],
      amostras: [
        Amostra(
          peca: 'Pilar P7',
          identificacao: 'CP-2026-0418',
          corposDeProva: [
            CorpoProva(idade: 7, resultado: 19.8),
            CorpoProva(idade: 7, resultado: 20.1),
            CorpoProva(idade: 28, resultado: 27.4),
            CorpoProva(idade: 28, resultado: 26.1),
          ],
        ),
      ],
    ),
    Lote(
      id: 'l2',
      numero: '14/03',
      peca: 'Laje do 2º pavimento L-201',
      classeId: 'c25',
      volume: 6,
      caminhoesPlanejados: 1,
      status: StatusLote.aguardandoCaminhao,
    ),
  ];

  static ClasseConcreto classePorId(String id) =>
      classes.firstWhere((c) => c.id == id);

  static Lote lotePorId(String id) => lotes.firstWhere((l) => l.id == id);

  static BuscaLoteResultado buscarPorCodigo(String codigo) {
    final achados = lotes.where((l) => l.numero == codigo);
    if (achados.isEmpty) return const BuscaLoteResultado.negado();
    return BuscaLoteResultado.encontrado(achados.first);
  }

  static int proximoNumeroCp() =>
      1000 + lotes.fold<int>(0, (n, l) => n + l.amostras.length);
}
