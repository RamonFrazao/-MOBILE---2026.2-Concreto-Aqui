const router = require('express').Router();
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const pool = require('../db');
const { JWT_SECRET } = require('../config');

const ERRO_GENERICO = 'Usuário ou senha inválidos.';

// Hash válido, mas de uma senha que ninguém tem — usado quando o usuário
// não existe, para que o bcrypt.compare rode do mesmo jeito e o tempo de
// resposta não denuncie se o usuário existe ou não.
const HASH_FANTASMA = '$2b$10$C6UzMDM.H6dfI/f/IKcEeO0k8FnJl6vKh3zK0k0k0k0k0k0k0k0k0';

router.post('/login', async (req, res) => {
  const { username, senha } = req.body || {};

  if (!username || !senha) {
    return res.status(401).json({ erro: ERRO_GENERICO });
  }

  try {
    const { rows } = await pool.query(
      `SELECT u.*, c.nome AS construtora_nome
       FROM usuarios u
       LEFT JOIN construtoras c ON c.id = u.construtora_id
       WHERE username = $1`,
      [username]
    );
    const usuario = rows[0];
    const hashParaComparar = usuario ? usuario.senha_hash : HASH_FANTASMA;
    const senhaOk = await bcrypt.compare(senha, hashParaComparar);

    if (!usuario || !senhaOk) {
      return res.status(401).json({ erro: ERRO_GENERICO });
    }

    const token = jwt.sign(
      { sub: usuario.id, perfil: usuario.perfil, construtoraId: usuario.construtora_id },
      JWT_SECRET,
      { expiresIn: '30d' }
    );

    res.json({
      token,
      usuario: {
        username: usuario.username,
        perfil: usuario.perfil,
        nome: usuario.nome,
        construtora: usuario.construtora_nome,
      },
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ erro: 'Erro interno.' });
  }
});

module.exports = router;
