const router = require('express').Router();
const pool = require('../db');
const { autenticar } = require('../middleware/auth');

// O lote é a unidade de julgamento: reúne as peças concretadas na mesma
// condição e guarda o fck de projeto, contra o qual a aceitação vai
// comparar o resultado. A aceitação é do lote, nunca de um caminhão
// isolado.
//
// Regras gerais, na ordem em que são conferidas:
//   1. Sem token válido -> 401.
//   2. Perfil "laboratorio" -> 403 em TODAS as rotas deste arquivo. O
//      laboratório só lança resultado de rompimento; pedido, lote e
//      aceitação não são dele, nem pela API.
//   3. Abrir, listar, ver, encerrar e excluir lote é só da construtora.
//      A única rota aberta também ao perfil "obra" é a busca por código
//      (GET /lotes?codigo=...), como desde a T01.
//   4. Lote de outra construtora -> 403 com mensagem clara, sem devolver
//      nenhum dado do lote.
router.use(autenticar);

router.use((req, res, next) => {
  if (req.usuario.perfil === 'laboratorio') {
    return res.status(403).json({
      erro: 'Acesso negado: o perfil de laboratório não acessa pedidos, lotes nem aceitação.',
    });
  }
  next();
});

const MSG_SO_CONSTRUTORA = 'Acesso negado: o seu perfil não tem acesso a este recurso.';

// Responde 403 e devolve false se quem chama não é a construtora.
function exigirConstrutora(req, res) {
  if (req.usuario.perfil !== 'construtora') {
    res.status(403).json({ erro: MSG_SO_CONSTRUTORA });
    return false;
  }
  return true;
}

const idValido = (v) => /^\d{1,9}$/.test(String(v));
const FCK_MAXIMO = 200;
const MAX_PECAS = 200;

const rota = (fn) => async (req, res) => {
  try {
    await fn(req, res);
  } catch (err) {
    console.error(err);
    if (!res.headersSent) res.status(500).json({ erro: 'Erro interno.' });
  }
};

const ROTULOS_TIPO = { pilar: 'Pilar', viga: 'Viga', laje: 'Laje', fundacao: 'Fundação' };
const rotuloPeca = (tipo, identificacao) => `${ROTULOS_TIPO[tipo] || tipo} ${identificacao}`;

function numero(v) {
  if (typeof v === 'number') return Number.isFinite(v) ? v : null;
  if (typeof v === 'string' && v.trim() !== '') {
    const n = Number(v);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

// Data da concretagem no formato AAAA-MM-DD, existente no calendário.
function dataValida(s) {
  if (typeof s !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(s)) return false;
  const [a, m, d] = s.split('-').map(Number);
  if (a < 2000 || a > 2100) return false;
  const dt = new Date(Date.UTC(a, m - 1, d));
  return dt.getUTCFullYear() === a && dt.getUTCMonth() === m - 1 && dt.getUTCDate() === d;
}

const dataBr = (s) => `${s.slice(8, 10)}/${s.slice(5, 7)}/${s.slice(0, 4)}`;

// ---------------------------------------------------------------------
// Busca por código (T01) e listagem
// ---------------------------------------------------------------------

// Com ?codigo=... : busca um lote pelo código (comportamento da T01).
//   - lote desta construtora -> 200
//   - lote que só existe em outra construtora -> 403, sem dados
//   - não existe -> 404
// O código ("12/03") agora pode se repetir entre construtoras, por isso a
// busca olha primeiro a construtora de quem pede.
// Sem ?codigo : lista os lotes da construtora (só construtora), os mais
// recentes primeiro; ?obra_id= filtra por obra.
router.get('/', rota(async (req, res) => {
  if (req.query.codigo !== undefined) {
    const codigo = req.query.codigo;
    if (typeof codigo !== 'string' || codigo.trim() === '') {
      return res.status(400).json({ erro: 'Informe o código do lote (?codigo=...).' });
    }

    const { rows } = await pool.query(
      `SELECT id, construtora_id, numero, peca, classe_id, volume, status, central_id,
              obra_id, fck_projeto, encerrado_em,
              to_char(data_concretagem, 'YYYY-MM-DD') AS data_concretagem
         FROM lotes
        WHERE numero = $1 AND construtora_id = $2`,
      [codigo, req.usuario.construtoraId]
    );
    if (rows[0]) return res.json(rows[0]);

    const outra = await pool.query('SELECT 1 FROM lotes WHERE numero = $1 LIMIT 1', [codigo]);
    if (outra.rows[0]) {
      return res.status(403).json({
        erro: 'Acesso negado: este lote pertence a outra construtora.',
      });
    }
    return res.status(404).json({ erro: 'Lote não encontrado.' });
  }

  if (!exigirConstrutora(req, res)) return;

  const params = [req.usuario.construtoraId];
  let filtro = 'WHERE l.construtora_id = $1 AND l.obra_id IS NOT NULL';
  if (req.query.obra_id !== undefined) {
    if (!idValido(req.query.obra_id)) {
      return res.status(400).json({ erro: 'Identificador de obra inválido.' });
    }
    params.push(Number(req.query.obra_id));
    filtro += ` AND l.obra_id = $${params.length}`;
  }

  const { rows } = await pool.query(
    `SELECT l.id, l.numero, l.status, l.fck_projeto, l.obra_id, o.nome AS obra_nome,
            to_char(l.data_concretagem, 'YYYY-MM-DD') AS data_concretagem,
            (SELECT COUNT(*) FROM lote_pecas lp WHERE lp.lote_id = l.id)::int AS qtd_pecas,
            (SELECT COUNT(*) FROM caminhoes c WHERE c.lote_id = l.id)::int AS qtd_caminhoes,
            COALESCE((SELECT SUM(c.volume) FROM caminhoes c WHERE c.lote_id = l.id), 0) AS volume_total
       FROM lotes l
       JOIN obras o ON o.id = l.obra_id
       ${filtro}
      ORDER BY l.data_concretagem DESC, l.id DESC`,
    params
  );
  res.json(rows.map((r) => ({ ...r, volume_total: Number(r.volume_total) })));
}));

// O que o formulário de abertura de lote precisa: as obras e as peças
// delas (a tela mostra só as peças da obra escolhida).
router.get('/opcoes', rota(async (req, res) => {
  if (!exigirConstrutora(req, res)) return;
  const c = req.usuario.construtoraId;

  const obras = await pool.query(
    'SELECT id, nome FROM obras WHERE construtora_id = $1 ORDER BY nome',
    [c]
  );
  const pecas = await pool.query(
    `SELECT pc.id, pc.tipo, pc.identificacao, pv.nome AS pavimento_nome, o.id AS obra_id
       FROM pecas pc
       JOIN pavimentos pv ON pv.id = pc.pavimento_id
       JOIN obras o ON o.id = pv.obra_id
      WHERE o.construtora_id = $1
      ORDER BY o.nome, pv.nome, pc.identificacao`,
    [c]
  );
  res.json({ obras: obras.rows, pecas: pecas.rows });
}));

// ---------------------------------------------------------------------
// Abertura
// ---------------------------------------------------------------------

router.post('/', rota(async (req, res) => {
  if (!exigirConstrutora(req, res)) return;
  const construtoraId = req.usuario.construtoraId;
  const corpo = req.body || {};

  const obraId = numero(corpo.obra_id);
  const fck = numero(corpo.fck_projeto);

  const faltando = [];
  if (obraId === null || !Number.isInteger(obraId)) faltando.push('obra');
  if (!dataValida(corpo.data_concretagem)) faltando.push('data da concretagem (AAAA-MM-DD)');
  if (fck === null) faltando.push('fck de projeto');
  if (faltando.length) {
    return res.status(400).json({ erro: `Preencha: ${faltando.join(', ')}.` });
  }

  if (!Number.isInteger(fck) || fck <= 0 || fck > FCK_MAXIMO) {
    return res.status(400).json({
      erro: `O fck de projeto precisa ser um número inteiro maior que zero, em MPa (até ${FCK_MAXIMO}).`,
    });
  }

  // Peças abrangidas: uma ou mais, sem repetir.
  const brutas = corpo.peca_ids;
  if (!Array.isArray(brutas) || brutas.length === 0) {
    return res.status(400).json({ erro: 'Escolha ao menos uma peça: um lote abrange uma ou mais peças.' });
  }
  if (brutas.length > MAX_PECAS) {
    return res.status(400).json({ erro: `Um lote abrange no máximo ${MAX_PECAS} peças.` });
  }
  const pecaIds = brutas.map(numero);
  if (pecaIds.some((n) => n === null || !Number.isInteger(n) || n <= 0)) {
    return res.status(400).json({ erro: 'A lista de peças tem um identificador inválido.' });
  }
  if (new Set(pecaIds).size !== pecaIds.length) {
    return res.status(400).json({ erro: 'A mesma peça aparece mais de uma vez na lista.' });
  }

  // A obra precisa existir e ser desta construtora.
  const { rows: obras } = await pool.query(
    'SELECT id, construtora_id FROM obras WHERE id = $1',
    [obraId]
  );
  if (!obras[0]) return res.status(400).json({ erro: 'Obra não encontrada.' });
  if (obras[0].construtora_id !== construtoraId) {
    return res.status(403).json({ erro: 'Acesso negado: esta obra pertence a outra construtora.' });
  }

  // Cada peça precisa existir, ser desta construtora e ser da obra escolhida.
  const { rows: pecas } = await pool.query(
    `SELECT pc.id, pc.tipo, pc.identificacao, o.id AS obra_id, o.construtora_id
       FROM pecas pc
       JOIN pavimentos pv ON pv.id = pc.pavimento_id
       JOIN obras o ON o.id = pv.obra_id
      WHERE pc.id = ANY($1::int[])`,
    [pecaIds]
  );
  if (pecas.length !== pecaIds.length) {
    const achadas = new Set(pecas.map((p) => p.id));
    const falta = pecaIds.find((id) => !achadas.has(id));
    return res.status(400).json({ erro: `Peça não encontrada (identificador ${falta}).` });
  }
  const deOutra = pecas.find((p) => p.construtora_id !== construtoraId);
  if (deOutra) {
    return res.status(403).json({ erro: 'Acesso negado: uma das peças pertence a outra construtora.' });
  }
  const deOutraObra = pecas.find((p) => p.obra_id !== obraId);
  if (deOutraObra) {
    return res.status(400).json({
      erro: `A peça ${rotuloPeca(deOutraObra.tipo, deOutraObra.identificacao)} não pertence à obra escolhida.`,
    });
  }

  // Uma peça pertence a um lote por concretagem: não pode entrar em dois
  // lotes da mesma data.
  const { rows: conflitos } = await pool.query(
    `SELECT pc.tipo, pc.identificacao, l.numero
       FROM lote_pecas lp
       JOIN lotes l ON l.id = lp.lote_id
       JOIN pecas pc ON pc.id = lp.peca_id
      WHERE lp.peca_id = ANY($1::int[]) AND lp.data_concretagem = $2`,
    [pecaIds, corpo.data_concretagem]
  );
  if (conflitos.length > 0) {
    const lista = conflitos
      .map((c) => `${rotuloPeca(c.tipo, c.identificacao)} (lote ${c.numero})`)
      .join(', ');
    return res.status(409).json({
      erro: `Uma peça só pertence a um lote por concretagem. Já estão em outro lote em ${dataBr(corpo.data_concretagem)}: ${lista}.`,
    });
  }

  const resumo = pecas
    .map((p) => rotuloPeca(p.tipo, p.identificacao))
    .join(', ')
    .slice(0, 200);
  const base = `${corpo.data_concretagem.slice(8, 10)}/${corpo.data_concretagem.slice(5, 7)}`;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    // Bloqueio por construtora: dois lotes abertos ao mesmo tempo esperam
    // um pelo outro em vez de pegar o mesmo código.
    await client.query('SELECT pg_advisory_xact_lock(1006, $1)', [construtoraId]);

    // Código do lote: o dia/mês da concretagem ("12/03"); se já existe,
    // "12/03-2", "12/03-3"...
    const { rows: usados } = await client.query(
      `SELECT numero FROM lotes WHERE construtora_id = $1 AND (numero = $2 OR numero LIKE $2 || '-%')`,
      [construtoraId, base]
    );
    const existentes = new Set(usados.map((u) => u.numero));
    let codigo = base;
    for (let k = 2; existentes.has(codigo); k++) codigo = `${base}-${k}`;

    // O lote nasce "em andamento".
    const { rows: [novo] } = await client.query(
      `INSERT INTO lotes (construtora_id, numero, peca, status, obra_id, data_concretagem, fck_projeto)
       VALUES ($1, $2, $3, 'em_andamento', $4, $5, $6)
       RETURNING id`,
      [construtoraId, codigo, resumo, obraId, corpo.data_concretagem, fck]
    );
    await client.query(
      `INSERT INTO lote_pecas (lote_id, peca_id, data_concretagem)
       SELECT $1, UNNEST($2::int[]), $3::date`,
      [novo.id, pecaIds, corpo.data_concretagem]
    );
    await client.query('COMMIT');

    res.status(201).json(await carregarLote(pool, novo.id));
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    // 23505 = violação de unicidade: o banco barrou uma corrida que a
    // checagem acima não pegou (peça já em outro lote da mesma data).
    if (err.code === '23505') {
      return res.status(409).json({
        erro: 'Uma peça só pertence a um lote por concretagem: alguma das peças já entrou em outro lote desta data.',
      });
    }
    throw err;
  } finally {
    client.release();
  }
}));

// ---------------------------------------------------------------------
// Lote aberto: peças, caminhões recebidos e volume total
// ---------------------------------------------------------------------

async function carregarLote(executor, id) {
  const { rows } = await executor.query(
    `SELECT l.id, l.construtora_id, l.numero, l.status, l.fck_projeto, l.obra_id,
            o.nome AS obra_nome, l.encerrado_em,
            to_char(l.data_concretagem, 'YYYY-MM-DD') AS data_concretagem
       FROM lotes l
       LEFT JOIN obras o ON o.id = l.obra_id
      WHERE l.id = $1`,
    [id]
  );
  const lote = rows[0];
  if (!lote) return null;

  const pecas = await executor.query(
    `SELECT pc.id, pc.tipo, pc.identificacao, pv.nome AS pavimento_nome
       FROM lote_pecas lp
       JOIN pecas pc ON pc.id = lp.peca_id
       JOIN pavimentos pv ON pv.id = pc.pavimento_id
      WHERE lp.lote_id = $1
      ORDER BY pv.nome, pc.identificacao`,
    [id]
  );
  const caminhoes = await executor.query(
    `SELECT ca.id, ca.placa, ca.volume, ca.criado_em,
            ce.nome AS central_nome, pe.numero AS pedido_numero
       FROM caminhoes ca
       JOIN centrais ce ON ce.id = ca.central_id
       LEFT JOIN pedidos pe ON pe.id = ca.pedido_id
      WHERE ca.lote_id = $1
      ORDER BY ca.criado_em, ca.id`,
    [id]
  );

  const lista = caminhoes.rows.map((c) => ({ ...c, volume: c.volume === null ? null : Number(c.volume) }));
  const volumeTotal = lista.reduce((soma, c) => soma + (c.volume || 0), 0);

  return {
    ...lote,
    pecas: pecas.rows,
    caminhoes: lista,
    qtd_caminhoes: lista.length,
    volume_total: Math.round(volumeTotal * 100) / 100,
  };
}

// Carrega o lote da URL e confere o dono. Se algo estiver errado, já
// responde ao cliente e devolve null (quem chama só precisa parar).
async function loteDaConstrutora(req, res) {
  const { id } = req.params;
  if (!idValido(id)) {
    res.status(400).json({ erro: 'Identificador de lote inválido.' });
    return null;
  }
  const lote = await carregarLote(pool, Number(id));
  if (!lote) {
    res.status(404).json({ erro: 'Lote não encontrado.' });
    return null;
  }
  if (lote.construtora_id !== req.usuario.construtoraId) {
    res.status(403).json({ erro: 'Acesso negado: este lote pertence a outra construtora.' });
    return null;
  }
  return lote;
}

router.get('/:id', rota(async (req, res) => {
  if (!exigirConstrutora(req, res)) return;
  const lote = await loteDaConstrutora(req, res);
  if (!lote) return;
  res.json(lote);
}));

// ---------------------------------------------------------------------
// Encerrar e excluir
// ---------------------------------------------------------------------

// Encerra o lote: depois disso, ele não recebe caminhão novo (a API
// confere aqui; o banco também recusa, por um gatilho em caminhoes).
router.post('/:id/encerrar', rota(async (req, res) => {
  if (!exigirConstrutora(req, res)) return;
  const existente = await loteDaConstrutora(req, res);
  if (!existente) return;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    // FOR UPDATE: enquanto encerra, nenhum caminhão novo é ligado ao lote.
    const { rows } = await client.query('SELECT status FROM lotes WHERE id = $1 FOR UPDATE', [existente.id]);
    const situacao = rows[0] && rows[0].status;

    if (situacao === 'encerrado') {
      await client.query('ROLLBACK');
      return res.status(409).json({ erro: `O lote ${existente.numero} já está encerrado.` });
    }
    if (situacao !== 'em_andamento') {
      await client.query('ROLLBACK');
      return res.status(409).json({ erro: `O lote ${existente.numero} não está em andamento e não pode ser encerrado.` });
    }

    await client.query(
      `UPDATE lotes SET status = 'encerrado', encerrado_em = now() WHERE id = $1`,
      [existente.id]
    );
    await client.query('COMMIT');
    res.json(await carregarLote(pool, existente.id));
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}));

// Exclui o lote — só se nenhum caminhão chegou para ele. Com caminhão
// recebido, o lote já é movimento e a aceitação depende dele.
router.delete('/:id', rota(async (req, res) => {
  if (!exigirConstrutora(req, res)) return;
  const lote = await loteDaConstrutora(req, res);
  if (!lote) return;

  if (lote.qtd_caminhoes > 0) {
    return res.status(409).json({
      erro: `Não é possível excluir o lote ${lote.numero}: já recebeu caminhão (${lote.qtd_caminhoes}).`,
    });
  }

  try {
    await pool.query('DELETE FROM lotes WHERE id = $1', [lote.id]);
  } catch (err) {
    // 23503 = violação de chave estrangeira: um caminhão (ou lançamento)
    // passou a apontar para este lote entre a checagem acima e o DELETE.
    if (err.code === '23503') {
      return res.status(409).json({
        erro: `Não é possível excluir o lote ${lote.numero}: ele já tem movimento (caminhão ou lançamento de concreto).`,
      });
    }
    throw err;
  }
  res.status(204).end();
}));

module.exports = router;
