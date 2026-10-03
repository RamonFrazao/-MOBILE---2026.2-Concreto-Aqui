// Restringe uma rota a um ou mais perfis. Usar depois de `autenticar`,
// que é quem preenche req.usuario a partir do token.
//
//   router.use(autenticar, exigirPerfil('construtora'));
function exigirPerfil(...perfisPermitidos) {
  return (req, res, next) => {
    if (!perfisPermitidos.includes(req.usuario.perfil)) {
      return res.status(403).json({
        erro: 'Acesso negado: o seu perfil não tem acesso a este recurso.',
      });
    }
    next();
  };
}

module.exports = { exigirPerfil };
