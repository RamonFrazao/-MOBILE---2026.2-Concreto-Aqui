const router = require('express').Router();
const pool = require('../db');
const { autenticar } = require('../middleware/auth');
const { lerConfig } = require('../prazos');

// Configuração do prazo de descarga. A construtora define; o técnico da
// obra só lê. O laboratório não acessa.
router.use(autenticar);

router.use((req, res, next) => {
  if (req.usuario.perfil === 'laboratorio') {
    return res.status(403).json({ erro: 'Acesso negado: o perfil de laboratório não acessa esta configuração.' });
  }
  if (!req.usuario.construtoraId) {
    return res.status(403).json({ erro: 'Acesso negado: o seu usuário não está ligado a uma construtora.' });
  }
  next();
});

const MSG_PERFIL = 'Acesso negado: o seu perfil não tem acesso a este recurso.';
const permitir = (...perfis) => (req, res, next) =>
  perfis.includes(req.usuario.perfil) ? next() : res.status(403).json({ erro: MSG_PERFIL });

const rota = (fn) => async (req, res) => {
  try {
    await fn(req, res);
  } catch (err) {
    console.error(err);
    if (!res.headersSent) res.status(500).json({ erro: 'Erro interno.' });
  }
};

function inteiro(v) {
  if (typeof v === 'number') return Number.isInteger(v) ? v : null;
  if (typeof v === 'string' && /^\d{1,6}$/.test(v.trim())) return Number(v.trim());
  return null;
}

router.get('/prazos', permitir('construtora', 'obra'), rota(async (req, res) => {
  res.json(await lerConfig(pool, req.usuario.construtoraId));
}));

// Muda o prazo para os caminhões que chegarem DEPOIS: cada caminhão guarda
// o prazo que valia quando chegou.
router.put('/prazos', permitir('construtora'), rota(async (req, res) => {
  const corpo = req.body || {};
  const prazo = inteiro(corpo.prazo_descarga_minutos);
  const aviso = inteiro(corpo.aviso_minutos);
  const semRetardador = corpo.prazo_retardador_minutos === undefined || corpo.prazo_retardador_minutos === null
    || (typeof corpo.prazo_retardador_minutos === 'string' && corpo.prazo_retardador_minutos.trim() === '');
  const retardador = semRetardador ? null : inteiro(corpo.prazo_retardador_minutos);

  if (prazo === null || prazo <= 0 || prazo > 1440) {
    return res.status(400).json({ erro: 'O prazo de descarga precisa ser um número inteiro de minutos, maior que zero (até 1440).' });
  }
  if (aviso === null || aviso < 0 || aviso > prazo) {
    return res.status(400).json({ erro: 'O aviso precisa ser um número inteiro de minutos, de zero até o prazo de descarga.' });
  }
  if (!semRetardador && (retardador === null || retardador <= 0 || retardador > 1440)) {
    return res.status(400).json({ erro: 'O prazo com retardador precisa ser um número inteiro de minutos, maior que zero (até 1440), ou ficar em branco.' });
  }
  if (retardador !== null && retardador < prazo) {
    return res.status(400).json({ erro: 'O prazo com aditivo retardador não pode ser menor que o prazo normal: o retardador existe para alongar o prazo.' });
  }

  await lerConfig(pool, req.usuario.construtoraId); // garante a linha
  const { rows } = await pool.query(
    `UPDATE configuracoes_prazo
        SET prazo_descarga_minutos = $2, prazo_retardador_minutos = $3, aviso_minutos = $4, atualizado_em = now()
      WHERE construtora_id = $1
  RETURNING prazo_descarga_minutos, prazo_retardador_minutos, aviso_minutos`,
    [req.usuario.construtoraId, prazo, retardador, aviso]
  );
  res.json(rows[0]);
}));

module.exports = router;
