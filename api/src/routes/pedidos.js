const router = require('express').Router();
const pool = require('../db');
const { autenticar } = require('../middleware/auth');
const { exigirPerfil } = require('../middleware/perfil');

// Pedido é da construtora: é ela quem compra. O pedido é a referência da
// conferência na chegada do caminhão (nota com fck diferente do pedido é
// divergência), por isso ele guarda central, classe, volume, data/hora
// previstas e a peça de destino.
router.use(autenticar, exigirPerfil('construtora'));

const VOLUME_MAXIMO = 100000; // m³ — só para barrar digitação absurda
const idValido = (v) => /^\d{1,9}$/.test(String(v));

const rota = (fn) => async (req, res) => {
  try {
    await fn(req, res);
  } catch (err) {
    console.error(err);
    if (!res.headersSent) res.status(500).json({ erro: 'Erro interno.' });
  }
};

// Converte o valor recebido em número, ou devolve null se não for um
// número de verdade (vazio, texto, booleano, lista...).
function numero(v) {
  if (typeof v === 'number') return Number.isFinite(v) ? v : null;
  if (typeof v === 'string' && v.trim() !== '') {
    const n = Number(v);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

// Um pedido por linha, já com tudo que a tela precisa: obra, peça,
// central, classe e o volume entregue (soma dos caminhões que já
// chegaram para ele).
const SELECT_PEDIDOS = `
  SELECT p.id, p.numero, p.status, p.volume, p.prevista_para, p.criado_em, p.cancelado_em,
         ce.id AS central_id, ce.nome AS central_nome,
         cl.id AS classe_id, cl.nome AS classe_nome, cl.fck,
         cl.abatimento_alvo, cl.abatimento_tolerancia,
         pc.id AS peca_id, pc.tipo AS peca_tipo, pc.identificacao AS peca_identificacao,
         pv.id AS pavimento_id, pv.nome AS pavimento_nome,
         o.id AS obra_id, o.nome AS obra_nome,
         COALESCE(SUM(ca.volume), 0) AS volume_entregue,
         COUNT(ca.id)::int AS qtd_caminhoes
    FROM pedidos p
    JOIN centrais ce ON ce.id = p.central_id
    JOIN classes_concreto cl ON cl.id = p.classe_id
    JOIN pecas pc ON pc.id = p.peca_id
    JOIN pavimentos pv ON pv.id = pc.pavimento_id
    JOIN obras o ON o.id = pv.obra_id
    LEFT JOIN caminhoes ca ON ca.pedido_id = p.id
`;
const GRUPO_PEDIDOS = 'GROUP BY p.id, ce.id, cl.id, pc.id, pv.id, o.id';

// O Postgres devolve NUMERIC como texto; aqui vira número de novo.
function formatar(linha) {
  return {
    ...linha,
    volume: Number(linha.volume),
    volume_entregue: Number(linha.volume_entregue),
  };
}

async function buscarPedidos(executor, construtoraId, { obraId = null, id = null } = {}) {
  const params = [construtoraId];
  let filtro = 'WHERE p.construtora_id = $1';
  if (obraId !== null) {
    params.push(obraId);
    filtro += ` AND o.id = $${params.length}`;
  }
  if (id !== null) {
    params.push(id);
    filtro += ` AND p.id = $${params.length}`;
  }
  const { rows } = await executor.query(
    `${SELECT_PEDIDOS} ${filtro} ${GRUPO_PEDIDOS}
      ORDER BY o.nome, p.prevista_para DESC, p.numero DESC`,
    params
  );
  return rows.map(formatar);
}

// Lista os pedidos da construtora logada. A tela agrupa por obra; o
// filtro ?obra_id= devolve só os de uma obra.
router.get('/', rota(async (req, res) => {
  let obraId = null;
  if (req.query.obra_id !== undefined) {
    if (!idValido(req.query.obra_id)) {
      return res.status(400).json({ erro: 'Identificador de obra inválido.' });
    }
    obraId = Number(req.query.obra_id);
  }
  res.json(await buscarPedidos(pool, req.usuario.construtoraId, { obraId }));
}));

// O que o formulário de novo pedido precisa para montar as escolhas:
// centrais ativas, classes e peças (com a obra e o pavimento delas).
router.get('/opcoes', rota(async (req, res) => {
  const c = req.usuario.construtoraId;

  const centrais = await pool.query(
    'SELECT id, nome FROM centrais WHERE construtora_id = $1 AND ativo ORDER BY nome',
    [c]
  );
  const classes = await pool.query(
    `SELECT id, nome, fck, abatimento_alvo, abatimento_tolerancia
       FROM classes_concreto WHERE construtora_id = $1 ORDER BY fck, nome`,
    [c]
  );
  const pecas = await pool.query(
    `SELECT pc.id, pc.tipo, pc.identificacao,
            pv.nome AS pavimento_nome, o.id AS obra_id, o.nome AS obra_nome
       FROM pecas pc
       JOIN pavimentos pv ON pv.id = pc.pavimento_id
       JOIN obras o ON o.id = pv.obra_id
      WHERE o.construtora_id = $1
      ORDER BY o.nome, pv.nome, pc.identificacao`,
    [c]
  );

  res.json({ centrais: centrais.rows, classes: classes.rows, pecas: pecas.rows });
}));

// Confere que o id pedido existe e é desta construtora. Devolve a linha,
// ou responde ao cliente e devolve null.
async function doDono(res, nome, id, construtoraId, sql) {
  const { rows } = await pool.query(sql, [id]);
  const linha = rows[0];
  if (!linha) {
    res.status(400).json({ erro: `${nome[0].toUpperCase()}${nome.slice(1)} não encontrada.` });
    return null;
  }
  if (linha.construtora_id !== construtoraId) {
    res.status(403).json({ erro: `Acesso negado: esta ${nome} pertence a outra construtora.` });
    return null;
  }
  return linha;
}

router.post('/', rota(async (req, res) => {
  const corpo = req.body || {};
  const construtoraId = req.usuario.construtoraId;

  const centralId = numero(corpo.central_id);
  const classeId = numero(corpo.classe_id);
  const pecaId = numero(corpo.peca_id);
  const volumeBruto = numero(corpo.volume);

  const faltando = [];
  if (centralId === null || !Number.isInteger(centralId)) faltando.push('central');
  if (classeId === null || !Number.isInteger(classeId)) faltando.push('classe');
  if (pecaId === null || !Number.isInteger(pecaId)) faltando.push('peça de destino');
  if (volumeBruto === null) faltando.push('volume');
  if (typeof corpo.prevista_para !== 'string' || corpo.prevista_para.trim() === '') {
    faltando.push('data e hora previstas');
  }
  if (faltando.length) {
    return res.status(400).json({ erro: `Preencha: ${faltando.join(', ')}.` });
  }

  // Volume: maior que zero (já considerando as 2 casas decimais que o
  // banco guarda — 0,001 vira 0,00 e não vale).
  const volume = Math.round(volumeBruto * 100) / 100;
  if (volume <= 0) {
    return res.status(400).json({ erro: 'O volume pedido precisa ser maior que zero (em m³).' });
  }
  if (volume > VOLUME_MAXIMO) {
    return res.status(400).json({ erro: `O volume pedido não pode passar de ${VOLUME_MAXIMO} m³.` });
  }

  const prevista = new Date(corpo.prevista_para);
  if (Number.isNaN(prevista.getTime()) || prevista.getFullYear() < 2000 || prevista.getFullYear() > 2100) {
    return res.status(400).json({ erro: 'Data e hora previstas inválidas.' });
  }

  // Central, classe e peça precisam existir e ser desta construtora.
  const central = await doDono(res, 'central', centralId, construtoraId,
    'SELECT id, construtora_id, ativo FROM centrais WHERE id = $1');
  if (!central) return;
  if (!central.ativo) {
    return res.status(409).json({ erro: 'Esta central está desativada e não recebe novos pedidos.' });
  }

  const classe = await doDono(res, 'classe', classeId, construtoraId,
    'SELECT id, construtora_id FROM classes_concreto WHERE id = $1');
  if (!classe) return;

  const peca = await doDono(res, 'peça', pecaId, construtoraId,
    `SELECT pc.id, o.construtora_id
       FROM pecas pc
       JOIN pavimentos pv ON pv.id = pc.pavimento_id
       JOIN obras o ON o.id = pv.obra_id
      WHERE pc.id = $1`);
  if (!peca) return;

  // O número próprio é atribuído dentro de uma transação, com um
  // bloqueio por construtora: dois pedidos feitos ao mesmo tempo esperam
  // um pelo outro em vez de pegar o mesmo número.
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock(1005, $1)', [construtoraId]);
    const { rows: [{ proximo }] } = await client.query(
      'SELECT COALESCE(MAX(numero), 0) + 1 AS proximo FROM pedidos WHERE construtora_id = $1',
      [construtoraId]
    );
    const { rows: [novo] } = await client.query(
      `INSERT INTO pedidos (construtora_id, numero, central_id, classe_id, peca_id, volume, prevista_para)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING id`,
      [construtoraId, proximo, centralId, classeId, pecaId, volume, prevista.toISOString()]
    );
    await client.query('COMMIT');

    const [pedido] = await buscarPedidos(pool, construtoraId, { id: novo.id });
    res.status(201).json(pedido);
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}));

// Cancela o pedido — só enquanto nenhum caminhão tiver chegado para ele.
// Depois que chegou concreto, o pedido já virou movimento e não se
// cancela mais. O pedido fica registrado como "cancelado" (não é apagado).
router.post('/:id/cancelar', rota(async (req, res) => {
  const { id } = req.params;
  if (!idValido(id)) {
    return res.status(400).json({ erro: 'Identificador de pedido inválido.' });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    // FOR UPDATE: enquanto cancela, ninguém liga um caminhão a este pedido.
    const { rows } = await client.query('SELECT * FROM pedidos WHERE id = $1 FOR UPDATE', [id]);
    const pedido = rows[0];

    if (!pedido) {
      await client.query('ROLLBACK');
      return res.status(404).json({ erro: 'Pedido não encontrado.' });
    }
    if (pedido.construtora_id !== req.usuario.construtoraId) {
      await client.query('ROLLBACK');
      return res.status(403).json({ erro: 'Acesso negado: este pedido pertence a outra construtora.' });
    }
    if (pedido.status === 'cancelado') {
      await client.query('ROLLBACK');
      return res.status(409).json({ erro: `O pedido ${pedido.numero} já está cancelado.` });
    }

    const { rows: [{ qtd }] } = await client.query(
      'SELECT COUNT(*)::int AS qtd FROM caminhoes WHERE pedido_id = $1',
      [pedido.id]
    );
    if (qtd > 0) {
      await client.query('ROLLBACK');
      return res.status(409).json({
        erro: `Não é possível cancelar o pedido ${pedido.numero}: já chegou caminhão para ele (${qtd}).`,
      });
    }

    await client.query(
      `UPDATE pedidos SET status = 'cancelado', cancelado_em = now() WHERE id = $1`,
      [pedido.id]
    );
    await client.query('COMMIT');

    const [atualizado] = await buscarPedidos(pool, req.usuario.construtoraId, { id: pedido.id });
    res.json(atualizado);
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}));

module.exports = router;
