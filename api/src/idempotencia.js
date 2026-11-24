// Idempotência: o mesmo client_id (gerado no aparelho) não cria recurso duas vezes.

const CLIENT_ID_RE = /^[A-Za-z0-9_-]{8,80}$/;

function normalizarClientId(body, headers) {
  const h = headers['x-client-id'] || headers['x-client-operation-id'];
  const raw = (body && body.client_id) || h;
  if (raw == null || raw === '') return null;
  const id = String(raw).trim();
  if (!CLIENT_ID_RE.test(id)) return null;
  return id;
}

async function buscarOperacao(executor, clientId, construtoraId) {
  const { rows: [op] } = await executor.query(
    `SELECT client_id, status_http, resposta, resource_tipo, resource_id
       FROM operacoes_cliente
      WHERE client_id = $1 AND construtora_id = $2`,
    [clientId, construtoraId]
  );
  return op || null;
}

async function gravarOperacao(executor, {
  clientId,
  construtoraId,
  usuarioId,
  tipo,
  resourceTipo,
  resourceId,
  statusHttp,
  resposta,
}) {
  await executor.query(
    `INSERT INTO operacoes_cliente
       (client_id, construtora_id, usuario_id, tipo, resource_tipo, resource_id, status_http, resposta)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8::jsonb)
     ON CONFLICT (client_id) DO NOTHING`,
    [
      clientId,
      construtoraId,
      usuarioId || null,
      tipo,
      resourceTipo || null,
      resourceId || null,
      statusHttp,
      JSON.stringify(resposta),
    ]
  );
}

/**
 * Envolve um handler de escrita: se client_id já existir, devolve a resposta gravada.
 * O handler deve retornar { status, body, resourceTipo?, resourceId? }.
 */
function comIdempotencia(tipo, handler) {
  return async (req, res) => {
    const clientId = normalizarClientId(req.body, req.headers);
    const construtoraId = req.usuario && req.usuario.construtoraId;

    if (clientId && construtoraId) {
      const existente = await buscarOperacao(require('./db'), clientId, construtoraId);
      if (existente) {
        return res.status(existente.status_http).json(existente.resposta);
      }
    }

    const resultado = await handler(req, res, clientId);
    // handler pode ter respondido sozinho
    if (res.headersSent) return;

    if (resultado && resultado.status && resultado.body !== undefined) {
      if (clientId && construtoraId && resultado.status >= 200 && resultado.status < 300) {
        try {
          await gravarOperacao(require('./db'), {
            clientId,
            construtoraId,
            usuarioId: req.usuario.id,
            tipo,
            resourceTipo: resultado.resourceTipo,
            resourceId: resultado.resourceId,
            statusHttp: resultado.status,
            resposta: resultado.body,
          });
        } catch (err) {
          // corrida: outro request gravou primeiro
          if (err.code === '23505') {
            const existente = await buscarOperacao(require('./db'), clientId, construtoraId);
            if (existente) {
              return res.status(existente.status_http).json(existente.resposta);
            }
          }
          throw err;
        }
      }
      return res.status(resultado.status).json(resultado.body);
    }
  };
}

module.exports = {
  normalizarClientId,
  buscarOperacao,
  gravarOperacao,
  comIdempotencia,
};
