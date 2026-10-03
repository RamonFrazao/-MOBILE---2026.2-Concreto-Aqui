const router = require('express').Router();
const pool = require('../db');
const { autenticar } = require('../middleware/auth');
const { exigirPerfil } = require('../middleware/perfil');

// Tudo aqui é da construtora: sem token válido -> 401; com token de
// obra ou laboratório -> 403. Além do perfil, cada rota confere que a
// obra pedida pertence à construtora de quem está logado.
router.use(autenticar, exigirPerfil('construtora'));

const TIPOS_PECA = ['pilar', 'viga', 'laje', 'fundacao'];
const MAX_TEXTO = 200;

// Postgres INTEGER vai até 2147483647; limitar a 9 dígitos evita que um
// número gigante na URL vire erro 500 em vez de um 400 claro.
const idValido = (v) => /^\d{1,9}$/.test(String(v));
const texto = (v) => (typeof v === 'string' ? v.trim() : '');

// Roda o handler e transforma qualquer exceção não tratada em 500,
// já que o Express 4 não captura erro de função async sozinho.
const rota = (fn) => async (req, res) => {
  try {
    await fn(req, res);
  } catch (err) {
    console.error(err);
    if (!res.headersSent) res.status(500).json({ erro: 'Erro interno.' });
  }
};

// Carrega a obra da URL e confere o dono. Se algo estiver errado, já
// responde ao cliente e devolve null (quem chama só precisa parar).
async function obraDaConstrutora(req, res) {
  const { obraId } = req.params;
  if (!idValido(obraId)) {
    res.status(400).json({ erro: 'Identificador de obra inválido.' });
    return null;
  }
  const { rows } = await pool.query('SELECT * FROM obras WHERE id = $1', [obraId]);
  const obra = rows[0];
  if (!obra) {
    res.status(404).json({ erro: 'Obra não encontrada.' });
    return null;
  }
  if (obra.construtora_id !== req.usuario.construtoraId) {
    res.status(403).json({ erro: 'Acesso negado: esta obra pertence a outra construtora.' });
    return null;
  }
  return obra;
}

// ---------------------------------------------------------------- Obras

router.get('/', rota(async (req, res) => {
  const { rows } = await pool.query(
    `SELECT o.id, o.nome, o.endereco, o.responsavel_tecnico,
            (SELECT COUNT(*) FROM pavimentos p WHERE p.obra_id = o.id)::int AS qtd_pavimentos,
            (SELECT COUNT(*) FROM pecas pc
               JOIN pavimentos p ON p.id = pc.pavimento_id
              WHERE p.obra_id = o.id)::int AS qtd_pecas
       FROM obras o
      WHERE o.construtora_id = $1
      ORDER BY o.nome`,
    [req.usuario.construtoraId]
  );
  res.json(rows);
}));

router.post('/', rota(async (req, res) => {
  const corpo = req.body || {};
  const nome = texto(corpo.nome);
  const endereco = texto(corpo.endereco);
  const responsavel = texto(corpo.responsavel_tecnico);

  const faltando = [];
  if (!nome) faltando.push('nome');
  if (!endereco) faltando.push('endereço');
  if (!responsavel) faltando.push('responsável técnico');
  if (faltando.length) {
    return res.status(400).json({ erro: `Preencha: ${faltando.join(', ')}.` });
  }
  if ([nome, endereco, responsavel].some((t) => t.length > MAX_TEXTO)) {
    return res.status(400).json({ erro: `Cada campo aceita no máximo ${MAX_TEXTO} caracteres.` });
  }

  const { rows } = await pool.query(
    `INSERT INTO obras (construtora_id, nome, endereco, responsavel_tecnico)
     VALUES ($1, $2, $3, $4)
     RETURNING id, nome, endereco, responsavel_tecnico`,
    [req.usuario.construtoraId, nome, endereco, responsavel]
  );
  res.status(201).json(rows[0]);
}));

// ----------------------------------------------------------- Pavimentos

router.get('/:obraId/pavimentos', rota(async (req, res) => {
  const obra = await obraDaConstrutora(req, res);
  if (!obra) return;
  const { rows } = await pool.query(
    'SELECT id, nome FROM pavimentos WHERE obra_id = $1 ORDER BY id',
    [obra.id]
  );
  res.json(rows);
}));

router.post('/:obraId/pavimentos', rota(async (req, res) => {
  const obra = await obraDaConstrutora(req, res);
  if (!obra) return;

  const nome = texto((req.body || {}).nome);
  if (!nome) return res.status(400).json({ erro: 'Informe o nome do pavimento.' });
  if (nome.length > MAX_TEXTO) {
    return res.status(400).json({ erro: `O nome aceita no máximo ${MAX_TEXTO} caracteres.` });
  }

  try {
    const { rows } = await pool.query(
      'INSERT INTO pavimentos (obra_id, nome) VALUES ($1, $2) RETURNING id, nome',
      [obra.id, nome]
    );
    res.status(201).json(rows[0]);
  } catch (err) {
    if (err.code === '23505') {
      return res.status(409).json({ erro: `Já existe um pavimento "${nome}" nesta obra.` });
    }
    throw err;
  }
}));

// ---------------------------------------------------------------- Peças

// Lista todas as peças da obra. Para cada uma diz se já recebeu concreto
// e, se sim, a data (a do lançamento mais recente).
router.get('/:obraId/pecas', rota(async (req, res) => {
  const obra = await obraDaConstrutora(req, res);
  if (!obra) return;

  const { rows } = await pool.query(
    `SELECT pc.id, pc.pavimento_id, p.nome AS pavimento, pc.tipo, pc.identificacao,
            (COUNT(l.id) > 0) AS concreto_lancado,
            to_char(MAX(l.data_lancamento), 'YYYY-MM-DD') AS data_lancamento
       FROM pecas pc
       JOIN pavimentos p ON p.id = pc.pavimento_id
       LEFT JOIN lancamentos l ON l.peca_id = pc.id
      WHERE p.obra_id = $1
      GROUP BY pc.id, p.id
      ORDER BY p.id, pc.identificacao`,
    [obra.id]
  );
  res.json(rows);
}));

router.post('/:obraId/pavimentos/:pavimentoId/pecas', rota(async (req, res) => {
  const obra = await obraDaConstrutora(req, res);
  if (!obra) return;

  const { pavimentoId } = req.params;
  if (!idValido(pavimentoId)) {
    return res.status(400).json({ erro: 'Identificador de pavimento inválido.' });
  }
  // O pavimento precisa ser desta obra (que já sabemos ser da construtora).
  const pav = await pool.query(
    'SELECT id FROM pavimentos WHERE id = $1 AND obra_id = $2',
    [pavimentoId, obra.id]
  );
  if (!pav.rows[0]) {
    return res.status(404).json({ erro: 'Pavimento não encontrado nesta obra.' });
  }

  const corpo = req.body || {};
  const tipo = texto(corpo.tipo).toLowerCase();
  const identificacao = texto(corpo.identificacao);

  if (!TIPOS_PECA.includes(tipo)) {
    return res.status(400).json({ erro: 'Tipo inválido. Use: pilar, viga, laje ou fundacao.' });
  }
  if (!identificacao) {
    return res.status(400).json({ erro: 'Informe a identificação da peça (ex.: P7).' });
  }
  if (identificacao.length > MAX_TEXTO) {
    return res.status(400).json({ erro: `A identificação aceita no máximo ${MAX_TEXTO} caracteres.` });
  }

  try {
    const { rows } = await pool.query(
      `INSERT INTO pecas (pavimento_id, tipo, identificacao)
       VALUES ($1, $2, $3)
       RETURNING id, pavimento_id, tipo, identificacao`,
      [pavimentoId, tipo, identificacao]
    );
    res.status(201).json({ ...rows[0], concreto_lancado: false, data_lancamento: null });
  } catch (err) {
    if (err.code === '23505') {
      return res.status(409).json({
        erro: `Já existe uma peça "${identificacao}" neste pavimento. A identificação não pode se repetir dentro do mesmo pavimento.`,
      });
    }
    throw err;
  }
}));

// Exclui uma peça — só se ela nunca recebeu concreto. Depois que um lote
// foi lançado nela, a rastreabilidade ("onde foi parar esse concreto?")
// depende dela, então a API recusa e diz o motivo.
router.delete('/:obraId/pecas/:pecaId', rota(async (req, res) => {
  const obra = await obraDaConstrutora(req, res);
  if (!obra) return;

  const { pecaId } = req.params;
  if (!idValido(pecaId)) {
    return res.status(400).json({ erro: 'Identificador de peça inválido.' });
  }

  const { rows } = await pool.query(
    `SELECT pc.id, pc.identificacao,
            COUNT(l.id)::int AS qtd,
            to_char(MAX(l.data_lancamento), 'DD/MM/YYYY') AS ultima_data
       FROM pecas pc
       JOIN pavimentos p ON p.id = pc.pavimento_id
       LEFT JOIN lancamentos l ON l.peca_id = pc.id
      WHERE pc.id = $1 AND p.obra_id = $2
      GROUP BY pc.id`,
    [pecaId, obra.id]
  );
  const peca = rows[0];
  if (!peca) return res.status(404).json({ erro: 'Peça não encontrada nesta obra.' });

  const motivo = (data) =>
    `A peça "${peca.identificacao}" não pode ser excluída: já recebeu concreto` +
    (data ? ` (lançado em ${data})` : '') +
    ' e a rastreabilidade do lote depende dela.';

  if (peca.qtd > 0) {
    return res.status(409).json({ erro: motivo(peca.ultima_data) });
  }

  try {
    await pool.query('DELETE FROM pecas WHERE id = $1', [peca.id]);
  } catch (err) {
    // 23503 = violação de chave estrangeira: um lançamento foi registrado
    // entre a checagem acima e o DELETE. O banco barra, e a resposta
    // continua sendo a mesma.
    if (err.code === '23503') return res.status(409).json({ erro: motivo(null) });
    throw err;
  }
  res.status(204).end();
}));

module.exports = router;
