// Modelos de domínio do Concreto Aqui.
// Mantidos simples e sem dependência de pacotes externos de propósito —
// a ideia é que estes objetos possam, mais tarde, virar apenas o resultado
// de um parse de JSON vindo da API, sem mudar quem os consome.

enum Perfil { construtora, obra, laboratorio }

class Usuario {
  final String username;
  final String senha; // só existe aqui porque o mock roda 100% local;
  // numa API real a senha nunca chega a este objeto.
  final Perfil perfil;
  final String nome;
  final String? construtora;

  const Usuario({
    required this.username,
    required this.senha,
    required this.perfil,
    required this.nome,
    this.construtora,
  });
}

class ClasseConcreto {
  final String id;
  final String nome;
  final int fck; // MPa
  final String abatimento; // ex.: "100 ± 20 mm"
  final String agregado;

  const ClasseConcreto({
    required this.id,
    required this.nome,
    required this.fck,
    required this.abatimento,
    required this.agregado,
  });

  /// Extrai (alvo, tolerância) de uma string como "100 ± 20 mm".
  (int alvo, int tolerancia) get toleranciaAbatimento {
    final match = RegExp(r'(\d+)\s*±\s*(\d+)').firstMatch(abatimento);
    if (match == null) return (0, 0);
    return (int.parse(match.group(1)!), int.parse(match.group(2)!));
  }
}

class CorpoProva {
  final int idade; // 7 ou 28 dias
  double? resultado; // MPa, nulo até o laboratório lançar

  CorpoProva({required this.idade, this.resultado});
}

class Amostra {
  final String peca;
  final String identificacao;
  final List<CorpoProva> corposDeProva;

  Amostra({
    required this.peca,
    required this.identificacao,
    required this.corposDeProva,
  });

  /// O exemplar vale o maior valor entre os dois corpos da mesma idade —
  /// nunca a média. Retorna null enquanto faltar algum dos dois resultados.
  double? valorExemplar(int idade) {
    final valores = corposDeProva
        .where((c) => c.idade == idade && c.resultado != null)
        .map((c) => c.resultado!)
        .toList();
    if (valores.length < 2) return null;
    return valores.reduce((a, b) => a > b ? a : b);
  }
}

class Caminhao {
  final String placa;
  final String nota;
  final String horaContato;
  String status; // 'chegando' | 'aceito' | 'recusado'

  Caminhao({
    required this.placa,
    required this.nota,
    required this.horaContato,
    this.status = 'chegando',
  });
}

enum StatusLote {
  aguardandoCaminhao,
  aguardandoResultados,
  aguardandoAceitacao,
  aceito,
  reprovado,
}

class Lote {
  final String id;
  final String numero;
  final String peca;
  final String classeId;
  final double volume;
  final int caminhoesPlanejados;
  StatusLote status;
  final List<Caminhao> caminhoes;
  final List<Amostra> amostras;

  Lote({
    required this.id,
    required this.numero,
    required this.peca,
    required this.classeId,
    required this.volume,
    required this.caminhoesPlanejados,
    required this.status,
    List<Caminhao>? caminhoes,
    List<Amostra>? amostras,
  })  : caminhoes = caminhoes ?? [],
        amostras = amostras ?? [];

  /// fck,est do lote — versão simplificada, para fins didáticos, da regra
  /// de amostragem parcial da NBR 12655 (ordena os exemplares de 28 dias,
  /// toma a média dos m menores e compara com o menor valor; nunca uma
  /// média simples de tudo). Documentar a regra completa na apresentação.
  double? calcularFckEst() {
    final exemplares28 = <double>[];
    for (final amostra in amostras) {
      final v = amostra.valorExemplar(28);
      if (v != null) exemplares28.add(v);
    }
    if (exemplares28.isEmpty) return null;
    exemplares28.sort();
    if (exemplares28.length == 1) return exemplares28.first;
    final m = (exemplares28.length / 2).floor().clamp(1, exemplares28.length);
    final media = exemplares28.take(m).reduce((a, b) => a + b) / m;
    final fckEst = 2 * media - exemplares28.first;
    return double.parse(fckEst.toStringAsFixed(1));
  }
}
