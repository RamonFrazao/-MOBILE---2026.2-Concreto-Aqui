const router = require('express').Router();
const pool = require('../db');
const { autenticar } = require('../middleware/auth');
const { exigirPerfil } = require('../middleware/perfil');

// Cadastro de central é só da construtora. De propósito, não existe
// nenhuma rota aqui para criar usuário de central — ela nunca recebe
// acesso ao sistema, em nenhuma tela.
router.use(autenticar, exigirPerfil('construtora'));

const MAX_TEXTO = 200;
const texto = (v) => (typeof v === 'string' ? v.trim() : '');
const idValido = (v) => /^\d{1,9}$/.test(String(v));

const rota = (fn) => async (req, res) => {
  try {
    await fn(req, res);
  } catch (err) {
    console.error(err);
    if (!res.headersSent) res.status(500).json({ erro: 'Erro interno.' });
  }
};

// Lista as centrais da construtora logada, cada uma já com quantos
// caminhões vieram dela.
router.get('/', rota(async (req, res) => {
  const { rows } = await pool.query(
    `SELECT c.id, c.nome, c.cnpj, c.contato, c.ativo,
            (SELECT COUNT(*) FROM caminhoes ca WHERE ca.central_id = c.id)::int AS qtd_caminhoes
       FROM centrais c
      WHERE c.construtora_id = $1
      ORDER BY c.nome`,
    [req.usuario.construtoraId]
  );
  res.json(rows);
}));

router.post('/', rota(async (req, res) => {
  const corpo = req.body || {};
  const nome = texto(corpo.nome);
  const cnpj = texto(corpo.cnpj);
  const contato = texto(corpo.contato);

  const faltando = [];
  if (!nome) faltando.push('nome');
  if (!cnpj) faltando.push('CNPJ');
  if (!contato) faltando.push('contato');
  if (faltando.length) {
    return res.status(400).json({ erro: `Preencha: ${faltando.join(', ')}.` });
  }
  if ([nome, cnpj, contato].some((t) => t.length > MAX_TEXTO)) {
    return res.status(400).json({ erro: `Cada campo aceita no máximo ${MAX_TEXTO} caracteres.` });
  }

  try {
    const { rows } = await pool.query(
      `INSERT INTO centrais (construtora_id, nome, cnpj, contato)
       VALUES ($1, $2, $3, $4)
       RETURNING id, nome, cnpj, contato, ativo`,
      [req.usuario.construtoraId, nome, cnpj, contato]
    );
    res.status(201).json({ ...rows[0], qtd_caminhoes: 0 });
  } catch (err) {
    if (err.code === '23505') {
      return res.status(409).json({ erro: `Já existe uma central com o CNPJ "${cnpj}".` });
    }
    throw err;
  }
}));

// Carrega a central da URL e confere o dono. Se algo estiver errado, já
// responde ao cliente e devolve null (quem chama só precisa parar).
async function centralDaConstrutora(req, res) {
  const { id } = req.params;
  if (!idValido(id)) {
    res.status(400).json({ erro: 'Identificador de central inválido.' });
    return null;
  }
  const { rows } = await pool.query('SELECT * FROM centrais WHERE id = $1', [id]);
  const central = rows[0];
  if (!central) {
    res.status(404).json({ erro: 'Central não encontrada.' });
    return null;
  }
  if (central.construtora_id !== req.usuario.construtoraId) {
    res.status(403).json({ erro: 'Acesso negado: esta central pertence a outra construtora.' });
    return null;
  }
  return central;
}

// Ativar/desativar é a alternativa à exclusão para quem já tem movimento.
router.patch('/:id/ativo', rota(async (req, res) => {
  const central = await centralDaConstrutora(req, res);
  if (!central) return;

  const ativo = (req.body || {}).ativo;
  if (typeof ativo !== 'boolean') {
    return res.status(400).json({ erro: 'Informe "ativo" como true ou false.' });
  }

  const { rows } = await pool.query(
    'UPDATE centrais SET ativo = $1 WHERE id = $2 RETURNING id, nome, cnpj, contato, ativo',
    [ativo, central.id]
  );
  res.json(rows[0]);
}));

// Exclui a central — só se ela nunca teve um caminhão. Quem já tem
// movimento é desativado (rota acima), nunca excluído: apagar perderia
// a origem das notas e lotes já registrados.
router.delete('/:id', rota(async (req, res) => {
  const central = await centralDaConstrutora(req, res);
  if (!central) return;

  const { rows } = await pool.query(
    'SELECT COUNT(*)::int AS qtd FROM caminhoes WHERE central_id = $1',
    [central.id]
  );
  if (rows[0].qtd > 0) {
    return res.status(409).json({
      erro: `Esta central já tem movimento (${rows[0].qtd} caminhão(ões) registrados) e não pode ser excluída — desative em vez de excluir.`,
    });
  }

  try {
    await pool.query('DELETE FROM centrais WHERE id = $1', [central.id]);
  } catch (err) {
    // 23503 = violação de chave estrangeira: algo passou a referenciar
    // esta central entre a checagem acima e o DELETE. O banco barra, e
    // a resposta continua sendo a mesma.
    if (err.code === '23503') {
      return res.status(409).json({
        erro: 'Esta central já tem movimento e não pode ser excluída — desative em vez de excluir.',
      });
    }
    throw err;
  }
  res.status(204).end();
}));

module.exports = router;
