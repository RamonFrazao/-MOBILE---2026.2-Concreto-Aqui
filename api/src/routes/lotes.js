const router = require('express').Router();
const pool = require('../db');
const { autenticar } = require('../middleware/auth');
const { situacaoPrazo, estaForaDoPrazo, sqlLimite, sqlRestanteSegundos, sqlExcedeuMinutos } = require('../prazos');
const { exemplaresDeCorpos } = require('../exemplares');
const { calcularFckEst } = require('../aceitacao');

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
            (SELECT COUNT(*) FROM caminhoes c
              WHERE c.lote_id = l.id AND c.prazo_minutos IS NOT NULL
                AND (c.fora_do_prazo OR (c.descarga_fim_em IS NULL AND now() > ${sqlLimite('c')})))::int AS qtd_fora_do_prazo,
            (SELECT COUNT(*) FROM amostras a
               JOIN caminhoes c ON c.id = a.caminhao_id
              WHERE c.lote_id = l.id)::int AS qtd_amostras,
            COALESCE((SELECT SUM(COALESCE(c.volume_efetivo, c.volume)) FROM caminhoes c WHERE c.lote_id = l.id), 0) AS volume_total
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
    `SELECT ca.id, ca.placa, ca.volume, ca.criado_em, ca.numero_nota,
            ce.nome AS central_nome, pe.numero AS pedido_numero,
            ca.prazo_minutos, ca.descarga_fim_em, ca.fora_do_prazo, cf.aviso_minutos,
            ${sqlRestanteSegundos('ca')} AS restante_segundos,
            ${sqlExcedeuMinutos('ca')} AS excedeu_minutos
       FROM caminhoes ca
       JOIN centrais ce ON ce.id = ca.central_id
       JOIN lotes lo ON lo.id = ca.lote_id
       LEFT JOIN configuracoes_prazo cf ON cf.construtora_id = lo.construtora_id
       LEFT JOIN pedidos pe ON pe.id = ca.pedido_id
      WHERE ca.lote_id = $1
      ORDER BY ca.criado_em, ca.id`,
    [id]
  );

  // Caminhão fora do prazo continua aqui: fica marcado, não some nem é bloqueado.
  const lista = caminhoes.rows.map((c) => {
    const situacao = situacaoPrazo(c);
    return {
      id: c.id,
      placa: c.placa,
      volume: c.volume === null ? null : Number(c.volume),
      criado_em: c.criado_em,
      central_nome: c.central_nome,
      pedido_numero: c.pedido_numero,
      numero_nota: c.numero_nota,
      situacao_prazo: situacao,
      fora_do_prazo: estaForaDoPrazo(situacao),
      restante_segundos: c.descarga_fim_em || c.prazo_minutos === null ? null : Number(c.restante_segundos),
      excedeu_minutos: Number(c.excedeu_minutos) || 0,
    };
  });
  const volumeTotal = lista.reduce((soma, c) => soma + (c.volume || 0), 0);

  const { rows: [contAmostras] } = await pool.query(
    `SELECT COUNT(*)::int AS n FROM amostras a
       JOIN caminhoes c ON c.id = a.caminhao_id
      WHERE c.lote_id = $1`,
    [lote.id]
  );

  return {
    ...lote,
    pecas: pecas.rows,
    caminhoes: lista,
    qtd_caminhoes: lista.length,
    qtd_fora_do_prazo: lista.filter((c) => c.fora_do_prazo).length,
    qtd_amostras: contAmostras?.n || 0,
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


// ---------------------------------------------------------------------
// Exemplares do lote (cálculo no servidor: maior valor, nunca a média)
// ---------------------------------------------------------------------
router.get('/:id/exemplares', rota(async (req, res) => {
  if (req.usuario.perfil === 'laboratorio') {
    return res.status(403).json({
      erro: 'Acesso negado: o perfil de laboratório não acessa exemplares nem aceitação.',
    });
  }
  if (!req.usuario.construtoraId) {
    return res.status(403).json({ erro: 'Acesso negado: o seu usuário não está ligado a uma construtora.' });
  }
  const { id } = req.params;
  if (!idValido(id)) return res.status(400).json({ erro: 'Identificador de lote inválido.' });

  const { rows: [lote] } = await pool.query(
    `SELECT id, numero, construtora_id, fck_projeto, status
       FROM lotes WHERE id = $1`,
    [Number(id)]
  );
  if (!lote) return res.status(404).json({ erro: 'Lote não encontrado.' });
  if (lote.construtora_id !== req.usuario.construtoraId) {
    return res.status(403).json({ erro: 'Acesso negado: este lote pertence a outra construtora.' });
  }

  const { rows } = await pool.query(
    `SELECT cp.id, cp.identificacao, cp.idade, cp.resultado, cp.situacao,
            a.id AS amostra_id, a.coletada_em,
            c.numero_nota, c.placa,
            l.id AS lote_id, l.numero AS lote_numero
       FROM corpos_prova cp
       JOIN amostras a ON a.id = cp.amostra_id
       JOIN caminhoes c ON c.id = a.caminhao_id
       JOIN lotes l ON l.id = c.lote_id
      WHERE l.id = $1
      ORDER BY cp.idade, a.id, cp.id`,
    [lote.id]
  );

  const exemplares = exemplaresDeCorpos(rows);

  // Agrupa por idade para a tela
  const porIdade = {};
  for (const e of exemplares) {
    const k = String(e.idade);
    if (!porIdade[k]) porIdade[k] = [];
    porIdade[k].push(e);
  }

  res.json({
    lote: {
      id: lote.id,
      numero: lote.numero,
      fck_projeto: lote.fck_projeto,
      status: lote.status,
    },
    // regra explícita na resposta, para a tela e para quem auditar
    regra: 'O resultado do exemplar é o maior valor entre os corpos da mesma amostra e idade — nunca a média.',
    exemplares,
    por_idade: porIdade,
  });
}));



// ---------------------------------------------------------------------
// Aceitação do lote — fck,est (NBR 12655) no servidor
// ---------------------------------------------------------------------

async function carregarTabelaPsi(executor) {
  const { rows } = await executor.query(
    'SELECT condicao_preparo, n_exemplares, psi6 FROM coeficientes_psi6 ORDER BY condicao_preparo, n_exemplares'
  );
  return rows;
}

async function exemplares28DoLote(executor, loteId) {
  const { rows } = await executor.query(
    `SELECT cp.id, cp.identificacao, cp.idade, cp.resultado, cp.situacao,
            a.id AS amostra_id, a.coletada_em,
            c.numero_nota, c.placa, l.id AS lote_id, l.numero AS lote_numero
       FROM corpos_prova cp
       JOIN amostras a ON a.id = cp.amostra_id
       JOIN caminhoes c ON c.id = a.caminhao_id
       JOIN lotes l ON l.id = c.lote_id
      WHERE l.id = $1 AND cp.idade = 28
      ORDER BY a.id, cp.id`,
    [loteId]
  );
  return exemplaresDeCorpos(rows).filter((e) => e.valor != null);
}

async function alertas7DoLote(executor, loteId) {
  const { rows } = await executor.query(
    `SELECT cp.id, cp.identificacao, cp.idade, cp.resultado, cp.situacao,
            a.id AS amostra_id, c.numero_nota, c.placa, l.id AS lote_id, l.numero AS lote_numero,
            a.coletada_em
       FROM corpos_prova cp
       JOIN amostras a ON a.id = cp.amostra_id
       JOIN caminhoes c ON c.id = a.caminhao_id
       JOIN lotes l ON l.id = c.lote_id
      WHERE l.id = $1 AND cp.idade = 7
      ORDER BY a.id, cp.id`,
    [loteId]
  );
  return exemplaresDeCorpos(rows);
}

// Prévia do fck,est e dos exemplares (não grava).
router.get('/:id/aceitacao', rota(async (req, res) => {
  if (req.usuario.perfil === 'laboratorio') {
    return res.status(403).json({ erro: 'Acesso negado: laboratório não acessa aceitação.' });
  }
  if (!req.usuario.construtoraId) {
    return res.status(403).json({ erro: 'Acesso negado.' });
  }
  const { id } = req.params;
  if (!idValido(id)) return res.status(400).json({ erro: 'Identificador de lote inválido.' });

  const { rows: [lote] } = await pool.query(
    `SELECT id, numero, construtora_id, fck_projeto, status, condicao_preparo,
            fck_est, situacao_aceitacao, aceitacao_em, aceitacao_por
       FROM lotes WHERE id = $1`,
    [Number(id)]
  );
  if (!lote) return res.status(404).json({ erro: 'Lote não encontrado.' });
  if (lote.construtora_id !== req.usuario.construtoraId) {
    return res.status(403).json({ erro: 'Acesso negado: este lote pertence a outra construtora.' });
  }

  const condicao = lote.condicao_preparo || 'A';
  const tabela = await carregarTabelaPsi(pool);
  const exemplares28 = await exemplares28DoLote(pool, lote.id);
  const valores = exemplares28.map((e) => e.valor);
  const calc = calcularFckEst(valores, condicao, tabela);
  const alertas7 = await alertas7DoLote(pool, lote.id);

  const { rows: decisoes } = await pool.query(
    `SELECT d.id, d.decisao, d.detalhe, d.registrada_em, u.nome AS autor
       FROM decisoes_lote d
       LEFT JOIN usuarios u ON u.id = d.registrada_por
      WHERE d.lote_id = $1
      ORDER BY d.registrada_em DESC`,
    [lote.id]
  );

  let veredito = null;
  if (calc.ok && lote.fck_projeto) {
    veredito = calc.fck_est >= lote.fck_projeto ? 'aceito' : 'reprovado';
  }

  res.json({
    lote: {
      id: lote.id,
      numero: lote.numero,
      fck_projeto: lote.fck_projeto,
      condicao_preparo: condicao,
      status: lote.status,
      situacao_aceitacao: lote.situacao_aceitacao,
      fck_est_gravado: lote.fck_est != null ? Number(lote.fck_est) : null,
      aceitacao_em: lote.aceitacao_em,
    },
    documentacao_norma:
      'NBR 12655:2015 amostragem parcial: exemplares de 28 dias ordenados; ' +
      '2≤n≤5 → Ψ6·f1; 6≤n<20 → 2·média(f1..f(m-1))−fm com m=⌊n/2⌋ e piso Ψ6·f1; ' +
      'n≥20 → fcm−1,65·sd com piso Ψ6·f1. Ψ6 e condição de preparo vêm do cadastro.',
    calculo: calc,
    veredito_sugerido: veredito,
    exemplares_28: exemplares28.map((e, i) => ({
      ...e,
      ordem: calc.ordenados ? calc.ordenados.indexOf(e.valor) + 1 : i + 1,
    })),
    alertas_7_dias: alertas7,
    decisoes,
  });
}));

// Define condição de preparo do lote (cadastro).
router.put('/:id/condicao-preparo', rota(async (req, res) => {
  if (req.usuario.perfil !== 'construtora') {
    return res.status(403).json({ erro: 'Só a construtora define a condição de preparo.' });
  }
  const { id } = req.params;
  if (!idValido(id)) return res.status(400).json({ erro: 'Identificador de lote inválido.' });
  const cond = String(req.body?.condicao_preparo || '').toUpperCase();
  if (!['A', 'B', 'C'].includes(cond)) {
    return res.status(400).json({ erro: 'Condição de preparo deve ser A, B ou C (NBR 12655).' });
  }
  const { rows: [lote] } = await pool.query(
    'SELECT id, construtora_id FROM lotes WHERE id = $1',
    [Number(id)]
  );
  if (!lote) return res.status(404).json({ erro: 'Lote não encontrado.' });
  if (lote.construtora_id !== req.usuario.construtoraId) {
    return res.status(403).json({ erro: 'Acesso negado.' });
  }
  const { rows: [salvo] } = await pool.query(
    `UPDATE lotes SET condicao_preparo = $2 WHERE id = $1
     RETURNING id, numero, condicao_preparo`,
    [lote.id, cond]
  );
  res.json(salvo);
}));

// Confirma aceitação ou reprovação com base no cálculo do servidor.
router.post('/:id/aceitacao', rota(async (req, res) => {
  if (req.usuario.perfil !== 'construtora') {
    return res.status(403).json({ erro: 'Só a construtora confirma a aceitação do lote.' });
  }
  if (!req.usuario.construtoraId) {
    return res.status(403).json({ erro: 'Acesso negado.' });
  }
  const { id } = req.params;
  if (!idValido(id)) return res.status(400).json({ erro: 'Identificador de lote inválido.' });

  const body = req.body || {};
  const decisao = body.decisao; // obrigatório se reprovado
  const detalhe = typeof body.detalhe === 'string' ? body.detalhe.trim() : null;

  const { rows: [lote] } = await pool.query(
    `SELECT id, numero, construtora_id, fck_projeto, status, condicao_preparo, situacao_aceitacao
       FROM lotes WHERE id = $1`,
    [Number(id)]
  );
  if (!lote) return res.status(404).json({ erro: 'Lote não encontrado.' });
  if (lote.construtora_id !== req.usuario.construtoraId) {
    return res.status(403).json({ erro: 'Acesso negado.' });
  }
  if (!lote.fck_projeto) {
    return res.status(409).json({ erro: 'Lote sem fck de projeto; defina o fck antes de aceitar.' });
  }
  if (lote.situacao_aceitacao === 'aceito' || lote.situacao_aceitacao === 'reprovado') {
    return res.status(409).json({
      erro: `Lote já está ${lote.situacao_aceitacao}.`,
    });
  }

  const condicao = lote.condicao_preparo || 'A';
  const tabela = await carregarTabelaPsi(pool);
  const exemplares28 = await exemplares28DoLote(pool, lote.id);
  const calc = calcularFckEst(exemplares28.map((e) => e.valor), condicao, tabela);
  if (!calc.ok) {
    return res.status(409).json({ erro: calc.erro, calculo: calc });
  }

  const veredito = calc.fck_est >= lote.fck_projeto ? 'aceito' : 'reprovado';
  if (veredito === 'reprovado') {
    const permitidas = ['revisao_projeto', 'extracao_testemunhos', 'prova_de_carga', 'outra'];
    if (!permitidas.includes(decisao)) {
      return res.status(400).json({
        erro: 'Lote reprovado exige a decisão tomada: revisao_projeto, extracao_testemunhos, prova_de_carga ou outra.',
        fck_est: calc.fck_est,
        fck_projeto: lote.fck_projeto,
      });
    }
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      `UPDATE lotes
          SET fck_est = $2,
              situacao_aceitacao = $3,
              aceitacao_em = now(),
              aceitacao_por = $4,
              status = CASE WHEN $3 = 'aceito' THEN 'encerrado' ELSE status END
        WHERE id = $1`,
      [lote.id, calc.fck_est, veredito, req.usuario.id]
    );
    if (veredito === 'reprovado') {
      await client.query(
        `INSERT INTO decisoes_lote (lote_id, decisao, detalhe, registrada_por)
         VALUES ($1, $2, $3, $4)`,
        [lote.id, decisao, detalhe, req.usuario.id]
      );
    }
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }

  res.status(201).json({
    lote_id: lote.id,
    numero: lote.numero,
    situacao_aceitacao: veredito,
    fck_est: calc.fck_est,
    fck_projeto: lote.fck_projeto,
    calculo: calc,
    exemplares_28: exemplares28,
    decisao: veredito === 'reprovado' ? { decisao, detalhe } : null,
  });
}));



// ---------------------------------------------------------------------
// Relatório de controle do concreto por lote (fiscalização / cliente)
// Inclui recusados e fora do prazo — não omite o que costuma ser escondido.
// ---------------------------------------------------------------------
router.get('/:id/relatorio', rota(async (req, res) => {
  if (req.usuario.perfil === 'laboratorio') {
    return res.status(403).json({ erro: 'Acesso negado: laboratório não acessa relatório de lote.' });
  }
  if (!req.usuario.construtoraId) {
    return res.status(403).json({ erro: 'Acesso negado.' });
  }
  const { id } = req.params;
  if (!idValido(id)) return res.status(400).json({ erro: 'Identificador de lote inválido.' });

  const { rows: [lote] } = await pool.query(
    `SELECT l.id, l.numero, l.peca, l.volume, l.status, l.fck_projeto, l.condicao_preparo,
            l.fck_est, l.situacao_aceitacao, l.aceitacao_em, l.obra_id,
            o.nome AS obra_nome, cc.nome AS classe_nome, cc.fck AS classe_fck
       FROM lotes l
       LEFT JOIN obras o ON o.id = l.obra_id
       LEFT JOIN classes_concreto cc ON cc.id = l.classe_id
      WHERE l.id = $1`,
    [Number(id)]
  );
  if (!lote) return res.status(404).json({ erro: 'Lote não encontrado.' });
  // construtora_id check
  const { rows: [own] } = await pool.query(
    'SELECT construtora_id FROM lotes WHERE id = $1',
    [lote.id]
  );
  if (own.construtora_id !== req.usuario.construtoraId) {
    return res.status(403).json({ erro: 'Acesso negado: este lote pertence a outra construtora.' });
  }

  const { rows: pecas } = await pool.query(
    `SELECT p.id, p.identificacao, pav.nome AS pavimento, o.nome AS obra
       FROM lote_pecas lp
       JOIN pecas p ON p.id = lp.peca_id
       JOIN pavimentos pav ON pav.id = p.pavimento_id
       JOIN obras o ON o.id = pav.obra_id
      WHERE lp.lote_id = $1
      ORDER BY o.nome, pav.nome, p.identificacao`,
    [lote.id]
  );

  const { rows: caminhoes } = await pool.query(
    `SELECT c.id, c.numero_nota, c.placa, c.volume, c.volume_efetivo,
            c.descarga_inicio_em, c.descarga_fim_em, c.fora_do_prazo, c.recusado,
            c.abatimento_mm, c.abatimento_ok, c.primeiro_contato_em, c.chegada_obra_em,
            c.classe_nota, c.fck_nota, ce.nome AS central_nome,
            ${sqlLimite('c')} AS limite_em,
            ${sqlExcedeuMinutos('c')} AS excedeu_minutos
       FROM caminhoes c
       JOIN centrais ce ON ce.id = c.central_id
      WHERE c.lote_id = $1
      ORDER BY c.criado_em`,
    [lote.id]
  );

  const { rows: corpos } = await pool.query(
    `SELECT cp.id, cp.identificacao, cp.idade, cp.resultado, cp.situacao,
            a.id AS amostra_id, c.numero_nota, c.placa
       FROM corpos_prova cp
       JOIN amostras a ON a.id = cp.amostra_id
       JOIN caminhoes c ON c.id = a.caminhao_id
      WHERE c.lote_id = $1
      ORDER BY cp.idade, a.id, cp.id`,
    [lote.id]
  );
  const exemplares = exemplaresDeCorpos(corpos.map((r) => ({
    ...r,
    lote_id: lote.id,
    lote_numero: lote.numero,
    coletada_em: null,
  })));

  // fck,est prévia
  let calculo = null;
  try {
    const tabela = await pool.query('SELECT condicao_preparo, n_exemplares, psi6 FROM coeficientes_psi6');
    const vals = exemplares.filter((e) => e.idade === 28 && e.valor != null).map((e) => e.valor);
    if (vals.length >= 2) {
      calculo = calcularFckEst(vals, lote.condicao_preparo || 'A', tabela.rows);
    }
  } catch (_) { /* módulo pode não estar em todos os deploys */ }

  const caminhoesFmt = caminhoes.map((c) => {
    const situacao = c.descarga_fim_em
      ? (c.fora_do_prazo ? 'fora_do_prazo' : 'no_prazo')
      : (c.recusado ? 'recusado' : 'em_andamento');
    return {
      id: c.id,
      numero_nota: c.numero_nota,
      placa: c.placa,
      central_nome: c.central_nome,
      volume: c.volume != null ? Number(c.volume) : null,
      volume_efetivo: c.volume_efetivo != null ? Number(c.volume_efetivo) : null,
      recusado: !!c.recusado,
      fora_do_prazo: !!c.fora_do_prazo,
      situacao_prazo: situacao,
      excedeu_minutos: c.excedeu_minutos != null ? Number(c.excedeu_minutos) : null,
      descarga_inicio_em: c.descarga_inicio_em,
      descarga_fim_em: c.descarga_fim_em,
      limite_em: c.limite_em,
      destaque: !!(c.recusado || c.fora_do_prazo),
      ensaio_abatimento: {
        medido_mm: c.abatimento_mm,
        ok: c.abatimento_ok,
        aceite: c.recusado ? 'recusado' : (c.abatimento_ok === false ? 'recusado' : (c.abatimento_mm != null ? 'aceito' : 'nao_informado')),
      },
    };
  });

  res.json({
    gerado_em: new Date().toISOString(),
    lote: {
      id: lote.id,
      numero: lote.numero,
      peca_legado: lote.peca,
      volume: lote.volume != null ? Number(lote.volume) : null,
      status: lote.status,
      fck_projeto: lote.fck_projeto,
      classe: lote.classe_nome,
      obra: lote.obra_nome,
      condicao_preparo: lote.condicao_preparo || 'A',
      fck_est: lote.fck_est != null ? Number(lote.fck_est) : (calculo && calculo.ok ? calculo.fck_est : null),
      situacao_aceitacao: lote.situacao_aceitacao,
      aceitacao_em: lote.aceitacao_em,
    },
    pecas,
    caminhoes: caminhoesFmt,
    resumo_caminhoes: {
      total: caminhoesFmt.length,
      recusados: caminhoesFmt.filter((c) => c.recusado).length,
      fora_do_prazo: caminhoesFmt.filter((c) => c.fora_do_prazo).length,
      no_prazo: caminhoesFmt.filter((c) => !c.recusado && c.situacao_prazo === 'no_prazo').length,
    },
    exemplares,
    calculo_fck_est: calculo,
    observacao:
      'Caminhões recusados e fora do prazo aparecem destacados neste relatório — não são omitidos.',
  });
}));

// Rastreabilidade por peça: todos os ensaios que a cobrem.
router.get('/rastreabilidade/peca/:pecaId', rota(async (req, res) => {
  if (req.usuario.perfil === 'laboratorio') {
    return res.status(403).json({ erro: 'Acesso negado.' });
  }
  if (!req.usuario.construtoraId) {
    return res.status(403).json({ erro: 'Acesso negado.' });
  }
  const { pecaId } = req.params;
  if (!idValido(pecaId)) return res.status(400).json({ erro: 'Identificador de peça inválido.' });

  const { rows: [peca] } = await pool.query(
    `SELECT p.id, p.identificacao, pav.nome AS pavimento, o.nome AS obra, o.construtora_id
       FROM pecas p
       JOIN pavimentos pav ON pav.id = p.pavimento_id
       JOIN obras o ON o.id = pav.obra_id
      WHERE p.id = $1`,
    [Number(pecaId)]
  );
  if (!peca) return res.status(404).json({ erro: 'Peça não encontrada.' });
  if (peca.construtora_id !== req.usuario.construtoraId) {
    return res.status(403).json({ erro: 'Acesso negado.' });
  }

  const { rows: lotes } = await pool.query(
    `SELECT l.id, l.numero, l.fck_projeto, l.fck_est, l.situacao_aceitacao
       FROM lote_pecas lp
       JOIN lotes l ON l.id = lp.lote_id
      WHERE lp.peca_id = $1
      ORDER BY l.id`,
    [peca.id]
  );

  const ensaios = [];
  for (const l of lotes) {
    const { rows: cps } = await pool.query(
      `SELECT cp.identificacao, cp.idade, cp.resultado, cp.situacao,
              c.numero_nota, c.placa, c.recusado, c.fora_do_prazo
         FROM corpos_prova cp
         JOIN amostras a ON a.id = cp.amostra_id
         JOIN caminhoes c ON c.id = a.caminhao_id
        WHERE c.lote_id = $1
        ORDER BY cp.idade, cp.id`,
      [l.id]
    );
    ensaios.push({
      lote: l,
      corpos_prova: cps.map((c) => ({
        identificacao: c.identificacao,
        idade: c.idade,
        resultado: c.resultado != null ? Number(c.resultado) : null,
        situacao: c.situacao,
        numero_nota: c.numero_nota,
        placa: c.placa,
        caminhao_recusado: !!c.recusado,
        fora_do_prazo: !!c.fora_do_prazo,
      })),
    });
  }

  res.json({
    peca: {
      id: peca.id,
      identificacao: peca.identificacao,
      pavimento: peca.pavimento,
      obra: peca.obra,
    },
    lotes_e_ensaios: ensaios,
  });
}));


module.exports = router;
