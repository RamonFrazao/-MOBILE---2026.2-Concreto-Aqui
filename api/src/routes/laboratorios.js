const router = require('express').Router();
const bcrypt = require('bcrypt');
const pool = require('../db');
const { autenticar } = require('../middleware/auth');
const { exigirPerfil } = require('../middleware/perfil');

// Cadastro de laboratório é só da construtora. Criar o usuário de
// acesso do laboratório também passa por aqui, embora quem loga depois
// com esse usuário caia no perfil "laboratorio" (bem mais restrito).
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

router.get('/', rota(async (req, res) => {
  const { rows } = await pool.query(
    `SELECT l.id, l.nome, l.cnpj, l.contato, l.ativo,
            (SELECT COUNT(*) FROM usuarios u WHERE u.laboratorio_id = l.id)::int AS qtd_usuarios
       FROM laboratorios l
      WHERE l.construtora_id = $1
      ORDER BY l.nome`,
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
      `INSERT INTO laboratorios (construtora_id, nome, cnpj, contato)
       VALUES ($1, $2, $3, $4)
       RETURNING id, nome, cnpj, contato, ativo`,
      [req.usuario.construtoraId, nome, cnpj, contato]
    );
    res.status(201).json({ ...rows[0], qtd_usuarios: 0 });
  } catch (err) {
    if (err.code === '23505') {
      return res.status(409).json({ erro: `Já existe um laboratório com o CNPJ "${cnpj}".` });
    }
    throw err;
  }
}));

async function laboratorioDaConstrutora(req, res) {
  const { id } = req.params;
  if (!idValido(id)) {
    res.status(400).json({ erro: 'Identificador de laboratório inválido.' });
    return null;
  }
  const { rows } = await pool.query('SELECT * FROM laboratorios WHERE id = $1', [id]);
  const lab = rows[0];
  if (!lab) {
    res.status(404).json({ erro: 'Laboratório não encontrado.' });
    return null;
  }
  if (lab.construtora_id !== req.usuario.construtoraId) {
    res.status(403).json({ erro: 'Acesso negado: este laboratório pertence a outra construtora.' });
    return null;
  }
  return lab;
}

router.patch('/:id/ativo', rota(async (req, res) => {
  const lab = await laboratorioDaConstrutora(req, res);
  if (!lab) return;

  const ativo = (req.body || {}).ativo;
  if (typeof ativo !== 'boolean') {
    return res.status(400).json({ erro: 'Informe "ativo" como true ou false.' });
  }

  const { rows } = await pool.query(
    'UPDATE laboratorios SET ativo = $1 WHERE id = $2 RETURNING id, nome, cnpj, contato, ativo',
    [ativo, lab.id]
  );
  res.json(rows[0]);
}));

// Exclui o laboratório — só se nenhum usuário de acesso foi criado para
// ele ainda. Depois que existe um usuário vinculado, só desativar:
// excluir derrubaria o login de quem já usa esse laboratório.
router.delete('/:id', rota(async (req, res) => {
  const lab = await laboratorioDaConstrutora(req, res);
  if (!lab) return;

  const { rows } = await pool.query(
    'SELECT COUNT(*)::int AS qtd FROM usuarios WHERE laboratorio_id = $1',
    [lab.id]
  );
  if (rows[0].qtd > 0) {
    return res.status(409).json({
      erro: 'Este laboratório já tem usuário de acesso vinculado e não pode ser excluído — desative em vez de excluir.',
    });
  }

  try {
    await pool.query('DELETE FROM laboratorios WHERE id = $1', [lab.id]);
  } catch (err) {
    if (err.code === '23503') {
      return res.status(409).json({
        erro: 'Este laboratório já tem movimento e não pode ser excluído — desative em vez de excluir.',
      });
    }
    throw err;
  }
  res.status(204).end();
}));

// ---------------------------------------------- Usuário de acesso do lab

router.get('/:id/usuarios', rota(async (req, res) => {
  const lab = await laboratorioDaConstrutora(req, res);
  if (!lab) return;
  const { rows } = await pool.query(
    'SELECT id, username, nome FROM usuarios WHERE laboratorio_id = $1 ORDER BY id',
    [lab.id]
  );
  res.json(rows);
}));

// Cria o usuário de acesso do laboratório, já com perfil "laboratorio"
// (o mais restrito) e a senha cifrada do mesmo jeito que no seed — a
// senha em texto puro nunca é gravada, só o hash.
router.post('/:id/usuarios', rota(async (req, res) => {
  const lab = await laboratorioDaConstrutora(req, res);
  if (!lab) return;

  const corpo = req.body || {};
  const username = texto(corpo.username);
  const senha = texto(corpo.senha);
  const nome = texto(corpo.nome);

  const faltando = [];
  if (!username) faltando.push('usuário');
  if (!senha) faltando.push('senha');
  if (!nome) faltando.push('nome');
  if (faltando.length) {
    return res.status(400).json({ erro: `Preencha: ${faltando.join(', ')}.` });
  }
  if (senha.length < 4) {
    return res.status(400).json({ erro: 'A senha precisa ter pelo menos 4 caracteres.' });
  }

  const senhaHash = await bcrypt.hash(senha, 10);

  try {
    const { rows } = await pool.query(
      `INSERT INTO usuarios (username, senha_hash, perfil, nome, laboratorio_id)
       VALUES ($1, $2, 'laboratorio', $3, $4)
       RETURNING id, username, nome`,
      [username, senhaHash, nome, lab.id]
    );
    res.status(201).json(rows[0]);
  } catch (err) {
    if (err.code === '23505') {
      return res.status(409).json({ erro: `Já existe um usuário com o nome "${username}".` });
    }
    throw err;
  }
}));

module.exports = router;
