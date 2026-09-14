const jwt = require('jsonwebtoken');
const { JWT_SECRET } = require('../config');

// Confere o token da sessão em cada rota protegida. Sem token válido,
// nem chega a saber se o recurso pedido existe.
function autenticar(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;

  if (!token) {
    return res.status(401).json({ erro: 'Não autenticado.' });
  }

  try {
    req.usuario = jwt.verify(token, JWT_SECRET);
    next();
  } catch {
    return res.status(401).json({ erro: 'Sessão inválida ou expirada.' });
  }
}

module.exports = { autenticar };
