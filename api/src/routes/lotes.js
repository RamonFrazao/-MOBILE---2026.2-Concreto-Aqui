const router = require('express').Router();
const pool = require('../db');
const { autenticar } = require('../middleware/auth');

// Busca um lote pelo código. Usa query string (?codigo=...) em vez de
// parâmetro na URL porque os códigos de lote têm barra (ex.: "12/03"),
// e uma barra dentro de um segmento de rota (/lotes/12/03) quebraria o
// roteamento — a query string não tem esse problema.
//
// Se o lote existir mas for de outra construtora, a resposta é 403 com
// mensagem clara — nunca os dados do lote, e nunca uma mensagem que
// deixe adivinhar se ele existe ou não para quem não tem acesso.
router.get('/', autenticar, async (req, res) => {
  const codigo = req.query.codigo;

  if (!codigo) {
    return res.status(400).json({ erro: 'Informe o código do lote (?codigo=...).' });
  }

  try {
    const { rows } = await pool.query('SELECT * FROM lotes WHERE numero = $1', [codigo]);
    const lote = rows[0];

    if (!lote) {
      return res.status(404).json({ erro: 'Lote não encontrado.' });
    }

    if (lote.construtora_id !== req.usuario.construtoraId) {
      return res.status(403).json({
        erro: 'Acesso negado: este lote pertence a outra construtora.',
      });
    }

    res.json(lote);
  } catch (err) {
    console.error(err);
    res.status(500).json({ erro: 'Erro interno.' });
  }
});

module.exports = router;
