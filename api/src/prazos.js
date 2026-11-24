// Prazo de descarga: configuração e cálculo.
//
// O prazo NÃO é um número escrito neste código: vem da tabela
// configuracoes_prazo (o valor padrão fica na própria tabela, no schema).
// Todo cálculo de tempo é feito pelo servidor — com o relógio do banco
// (now()), nunca com o relógio do aparelho de quem usa o app.

// Garante que a construtora tem a linha de configuração (com os valores
// padrão do schema) e devolve a configuração.
async function lerConfig(executor, construtoraId) {
  await executor.query(
    'INSERT INTO configuracoes_prazo (construtora_id) VALUES ($1) ON CONFLICT (construtora_id) DO NOTHING',
    [construtoraId]
  );
  const { rows } = await executor.query(
    `SELECT prazo_descarga_minutos, prazo_retardador_minutos, aviso_minutos
       FROM configuracoes_prazo WHERE construtora_id = $1`,
    [construtoraId]
  );
  return rows[0];
}

// O prazo de um caminhão: o do concreto com retardador (se a equipe já o
// configurou) ou o normal. Guardado no caminhão na hora em que ele chega.
function prazoDoCaminhao(config, comRetardador) {
  if (comRetardador && config.prazo_retardador_minutos !== null) {
    return config.prazo_retardador_minutos;
  }
  return config.prazo_descarga_minutos;
}

// Pedaços de SQL para calcular o tempo com o relógio do banco. `c` é o
// apelido da tabela caminhoes.
const sqlLimite = (c) => `(${c}.primeiro_contato_em + ${c}.prazo_minutos * interval '1 minute')`;
const sqlRestanteSegundos = (c) => `EXTRACT(EPOCH FROM (${sqlLimite(c)} - now()))::int`;
const sqlExcedeuMinutos = (c) =>
  `GREATEST(0, EXTRACT(EPOCH FROM (COALESCE(${c}.descarga_fim_em, now()) - ${sqlLimite(c)})) / 60)::int`;

// Situação do prazo de um caminhão, a partir do que o banco calculou:
//   descarga aberta : no_prazo | atencao (falta pouco) | estourado
//   descarga fechada: encerrada_no_prazo | encerrada_fora_do_prazo
// Caminhão do desenho antigo, sem prazo, devolve null.
function situacaoPrazo(r) {
  if (r.prazo_minutos === null || r.prazo_minutos === undefined) return null;
  if (r.descarga_fim_em) return r.fora_do_prazo ? 'encerrada_fora_do_prazo' : 'encerrada_no_prazo';
  const restante = Number(r.restante_segundos);
  if (restante <= 0) return 'estourado';
  if (restante <= (Number(r.aviso_minutos) || 0) * 60) return 'atencao';
  return 'no_prazo';
}

const estaForaDoPrazo = (situacao) =>
  situacao === 'estourado' || situacao === 'encerrada_fora_do_prazo';

module.exports = {
  lerConfig, prazoDoCaminhao, situacaoPrazo, estaForaDoPrazo,
  sqlLimite, sqlRestanteSegundos, sqlExcedeuMinutos,
};
