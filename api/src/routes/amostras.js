const router = require('express').Router();
const pool = require('../db');
const { autenticar } = require('../middleware/auth');
const { montarExemplar } = require('../exemplares');
const { normalizarClientId, buscarOperacao, gravarOperacao } = require('../idempotencia');

// Amostra e corpos de prova: o técnico da obra molda a partir de um
// caminhão aceito. O laboratório só lança resultado de rompimento depois.
//
// Regras:
//   1. Sem token -> 401.
//   2. Laboratório não cria amostra (só lê/lança resultado em outra rota).
//   3. Caminhão de outra construtora -> 403.
//   4. Caminhão recusado ou sem descarga encerrada -> 409/400.
//   5. Duas idades (configuráveis; padrão 7 e 28) com dois corpos cada.

router.use(autenticar);

router.use((req, res, next) => {
  if (!req.usuario.construtoraId) {
    return res.status(403).json({ erro: 'Acesso negado: o seu usuário não está ligado a uma construtora.' });
  }
  next();
});

const MSG_PERFIL = 'Acesso negado: o seu perfil não tem acesso a este recurso.';
const permitir = (...perfis) => (req, res, next) =>
  perfis.includes(req.usuario.perfil) ? next() : res.status(403).json({ erro: MSG_PERFIL });

// Laboratório consulta por identificação e lista por peça; não cria amostra.
const bloquearLabEscrita = (req, res, next) => {
  if (req.usuario.perfil === 'laboratorio') {
    return res.status(403).json({
      erro: 'Acesso negado: o perfil de laboratório não cria amostras nem molda corpos de prova.',
    });
  }
  next();
};

const idValido = (v) => /^\d{1,9}$/.test(String(v));
const rota = (fn) => async (req, res) => {
  try {
    await fn(req, res);
  } catch (err) {
    console.error(err);
    if (!res.headersSent) res.status(500).json({ erro: 'Erro interno.' });
  }
};

const ISO = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(Z|[+-](\d{2}):(\d{2}))$/;
function instante(v) {
  if (typeof v !== 'string') return null;
  const m = ISO.exec(v.trim());
  if (!m) return null;
  const [ano, mes, dia, hora, minuto] = [m[1], m[2], m[3], m[4], m[5]].map(Number);
  const segundo = m[6] === undefined ? 0 : Number(m[6]);
  const diasNoMes = new Date(Date.UTC(ano, mes, 0)).getUTCDate();
  if (ano < 2000 || ano > 2100 || mes < 1 || mes > 12 || dia < 1 || dia > diasNoMes) return null;
  if (hora > 23 || minuto > 59 || segundo > 59) return null;
  if (m[8] !== undefined && (Number(m[8]) > 23 || Number(m[9]) > 59)) return null;
  const d = new Date(v.trim());
  return Number.isNaN(d.getTime()) ? null : d;
}

async function idadesDaConstrutora(executor, construtoraId) {
  await executor.query(
    'INSERT INTO configuracoes_idades (construtora_id) VALUES ($1) ON CONFLICT (construtora_id) DO NOTHING',
    [construtoraId]
  );
  const { rows } = await executor.query(
    'SELECT idades FROM configuracoes_idades WHERE construtora_id = $1',
    [construtoraId]
  );
  return rows[0]?.idades || [7, 28];
}

function formatarAmostra(a, corpos) {
  return {
    id: a.id,
    caminhao_id: a.caminhao_id,
    numero_nota: a.numero_nota,
    placa: a.placa,
    lote_id: a.lote_id,
    lote_numero: a.lote_numero,
    coletada_em: a.coletada_em,
    corpos_prova: corpos.map((c) => ({
      id: c.id,
      identificacao: c.identificacao,
      idade: c.idade,
      resultado: c.resultado != null ? Number(c.resultado) : null,
    })),
  };
}

/** Gera a próxima identificação única na construtora: CP-AAAA-NNNNN */
async function proximaIdentificacao(client, construtoraId) {
  await client.query(
    'INSERT INTO sequencias_corpo_prova (construtora_id) VALUES ($1) ON CONFLICT (construtora_id) DO NOTHING',
    [construtoraId]
  );
  const { rows: [seq] } = await client.query(
    `UPDATE sequencias_corpo_prova
        SET ultimo = ultimo + 1
      WHERE construtora_id = $1
  RETURNING ultimo`,
    [construtoraId]
  );
  const ano = new Date().getFullYear();
  const n = String(seq.ultimo).padStart(5, '0');
  return `CP-${ano}-${n}`;
}

/** Cadeia completa: CP → amostra → caminhão/nota → lote → peças → pavimento → obra */
async function carregarCadeiaPorIdentificacao(executor, identificacao, construtoraId) {
  const { rows: [cp] } = await executor.query(
    `SELECT cp.id, cp.identificacao, cp.idade, cp.resultado, cp.situacao,
            cp.cura_inicio_em, cp.descartado_em, cp.motivo_descarte, cp.amostra_id,
            a.coletada_em, a.caminhao_id,
            c.numero_nota, c.placa, c.volume, c.volume_efetivo, c.classe_nota, c.fck_nota,
            c.primeiro_contato_em, c.chegada_obra_em, c.descarga_inicio_em, c.descarga_fim_em,
            c.fora_do_prazo, c.recusado, c.lote_id,
            l.numero AS lote_numero, l.data_concretagem, l.fck_projeto, l.status AS lote_status,
            l.obra_id, o.nome AS obra_nome, o.endereco AS obra_endereco,
            ce.nome AS central_nome
       FROM corpos_prova cp
       JOIN amostras a ON a.id = cp.amostra_id
       JOIN caminhoes c ON c.id = a.caminhao_id
       JOIN lotes l ON l.id = c.lote_id
       JOIN obras o ON o.id = l.obra_id
       JOIN centrais ce ON ce.id = c.central_id
      WHERE lower(cp.identificacao) = lower($1)
        AND l.construtora_id = $2`,
    [identificacao, construtoraId]
  );
  if (!cp) return null;

  const { rows: pecas } = await executor.query(
    `SELECT p.id, p.tipo, p.identificacao, pv.nome AS pavimento, o.nome AS obra
       FROM lote_pecas lp
       JOIN pecas p ON p.id = lp.peca_id
       JOIN pavimentos pv ON pv.id = p.pavimento_id
       JOIN obras o ON o.id = pv.obra_id
      WHERE lp.lote_id = $1
      ORDER BY pv.nome, p.tipo, p.identificacao`,
    [cp.lote_id]
  );

  const { rows: irmaos } = await executor.query(
    `SELECT id, identificacao, idade, resultado, situacao
       FROM corpos_prova
      WHERE amostra_id = $1
      ORDER BY idade, id`,
    [cp.amostra_id]
  );

  return {
    corpo_prova: {
      id: cp.id,
      identificacao: cp.identificacao,
      idade: cp.idade,
      resultado: cp.resultado != null ? Number(cp.resultado) : null,
      situacao: cp.situacao,
      cura_inicio_em: cp.cura_inicio_em,
      descartado_em: cp.descartado_em,
      motivo_descarte: cp.motivo_descarte,
    },
    amostra: {
      id: cp.amostra_id,
      coletada_em: cp.coletada_em,
      corpos_prova: irmaos.map((i) => ({
        id: i.id,
        identificacao: i.identificacao,
        idade: i.idade,
        resultado: i.resultado != null ? Number(i.resultado) : null,
        situacao: i.situacao,
      })),
    },
    caminhao: {
      id: cp.caminhao_id,
      numero_nota: cp.numero_nota,
      placa: cp.placa,
      volume: cp.volume != null ? Number(cp.volume) : null,
      volume_efetivo: cp.volume_efetivo != null ? Number(cp.volume_efetivo) : null,
      classe_nota: cp.classe_nota,
      fck_nota: cp.fck_nota,
      central_nome: cp.central_nome,
      primeiro_contato_em: cp.primeiro_contato_em,
      chegada_obra_em: cp.chegada_obra_em,
      descarga_inicio_em: cp.descarga_inicio_em,
      descarga_fim_em: cp.descarga_fim_em,
      fora_do_prazo: cp.fora_do_prazo,
      recusado: cp.recusado,
    },
    lote: {
      id: cp.lote_id,
      numero: cp.lote_numero,
      data_concretagem: cp.data_concretagem,
      fck_projeto: cp.fck_projeto,
      status: cp.lote_status,
    },
    obra: {
      id: cp.obra_id,
      nome: cp.obra_nome,
      endereco: cp.obra_endereco,
    },
    pecas: pecas.map((p) => ({
      id: p.id,
      tipo: p.tipo,
      identificacao: p.identificacao,
      pavimento: p.pavimento,
      rotulo: `${p.tipo === 'pilar' ? 'Pilar' : p.tipo === 'viga' ? 'Viga' : p.tipo === 'laje' ? 'Laje' : 'Fundação'} ${p.identificacao}`,
    })),
    // Texto pronto para etiqueta / compartilhar
    etiqueta: [
      cp.identificacao,
      `Obra: ${cp.obra_nome}`,
      `Lote: ${cp.lote_numero}`,
      `Nota: ${cp.numero_nota} · Placa: ${cp.placa}`,
      `Idade: ${cp.idade} dias`,
      pecas.length
        ? `Peças: ${pecas.map((p) => `${p.tipo} ${p.identificacao}`).join(', ')}`
        : null,
    ].filter(Boolean).join('\n'),
  };
}

// Lista amostras de um lote (para a tela do lote mostrar quantas já foram coletadas).
router.get('/', permitir('obra', 'construtora'), rota(async (req, res) => {
  const params = [req.usuario.construtoraId];
  let filtro = ' AND l.construtora_id = $1';
  if (req.query.lote_id !== undefined) {
    if (!idValido(req.query.lote_id)) return res.status(400).json({ erro: 'Identificador de lote inválido.' });
    params.push(Number(req.query.lote_id));
    filtro += ` AND c.lote_id = $${params.length}`;
  }
  if (req.query.caminhao_id !== undefined) {
    if (!idValido(req.query.caminhao_id)) return res.status(400).json({ erro: 'Identificador de caminhão inválido.' });
    params.push(Number(req.query.caminhao_id));
    filtro += ` AND a.caminhao_id = $${params.length}`;
  }

  const { rows } = await pool.query(
    `SELECT a.id, a.caminhao_id, a.coletada_em, c.numero_nota, c.placa, c.lote_id, l.numero AS lote_numero
       FROM amostras a
       JOIN caminhoes c ON c.id = a.caminhao_id
       JOIN lotes l ON l.id = c.lote_id
      WHERE c.numero_nota IS NOT NULL ${filtro}
      ORDER BY a.coletada_em DESC, a.id DESC
      LIMIT 500`,
    params
  );

  if (rows.length === 0) return res.json([]);

  const ids = rows.map((r) => r.id);
  const { rows: corpos } = await pool.query(
    `SELECT id, amostra_id, idade, resultado, identificacao FROM corpos_prova
      WHERE amostra_id = ANY($1::int[]) ORDER BY idade, id`,
    [ids]
  );
  const porAmostra = new Map();
  for (const c of corpos) {
    if (!porAmostra.has(c.amostra_id)) porAmostra.set(c.amostra_id, []);
    porAmostra.get(c.amostra_id).push(c);
  }

  res.json(rows.map((a) => formatarAmostra(a, porAmostra.get(a.id) || [])));
}));

// Idades configuradas (obra e construtora leem; construtora altera).
router.get('/idades', permitir('obra', 'construtora'), rota(async (req, res) => {
  const idades = await idadesDaConstrutora(pool, req.usuario.construtoraId);
  res.json({ idades });
}));

router.put('/idades', bloquearLabEscrita, permitir('construtora'), rota(async (req, res) => {
  const corpo = req.body || {};
  let idades = corpo.idades;
  if (!Array.isArray(idades) || idades.length === 0) {
    return res.status(400).json({ erro: 'Informe pelo menos uma idade de rompimento (em dias).' });
  }
  idades = idades.map((v) => {
    if (typeof v === 'number' && Number.isInteger(v)) return v;
    if (typeof v === 'string' && /^\d{1,3}$/.test(v.trim())) return Number(v.trim());
    return null;
  });
  if (idades.some((v) => v === null || v < 1 || v > 365)) {
    return res.status(400).json({ erro: 'Cada idade deve ser um inteiro de 1 a 365 dias.' });
  }
  // Remove duplicatas e ordena.
  idades = [...new Set(idades)].sort((a, b) => a - b);

  await pool.query(
    `INSERT INTO configuracoes_idades (construtora_id, idades, atualizado_em)
     VALUES ($1, $2, now())
     ON CONFLICT (construtora_id) DO UPDATE
       SET idades = EXCLUDED.idades, atualizado_em = now()`,
    [req.usuario.construtoraId, idades]
  );
  res.json({ idades });
}));

// Cria a amostra ligada a um caminhão aceito + molda 2 corpos por idade.
router.post('/', bloquearLabEscrita, permitir('obra'), rota(async (req, res) => {
  const clientId = normalizarClientId(req.body, req.headers);
  if (clientId) {
    const op = await buscarOperacao(pool, clientId, req.usuario.construtoraId);
    if (op) return res.status(op.status_http).json(op.resposta);
  }

  const corpo = req.body || {};
  const caminhaoId = Number(corpo.caminhao_id);
  const coletada = instante(corpo.coletada_em);

  if (!Number.isInteger(caminhaoId) || caminhaoId < 1) {
    return res.status(400).json({ erro: 'Informe o caminhão (caminhao_id).' });
  }
  if (!coletada) {
    return res.status(400).json({
      erro: 'Informe a data e hora da coleta (formato ISO, com fuso).',
    });
  }

  const { rows: [cam] } = await pool.query(
    `SELECT c.id, c.numero_nota, c.placa, c.lote_id, c.recusado, c.descarga_fim_em,
            l.construtora_id, l.numero AS lote_numero
       FROM caminhoes c
       JOIN lotes l ON l.id = c.lote_id
      WHERE c.id = $1 AND c.numero_nota IS NOT NULL`,
    [caminhaoId]
  );
  if (!cam) return res.status(404).json({ erro: 'Caminhão não encontrado.' });
  if (cam.construtora_id !== req.usuario.construtoraId) {
    return res.status(403).json({ erro: 'Acesso negado: este caminhão pertence a outra construtora.' });
  }
  if (cam.recusado) {
    return res.status(409).json({
      erro: `Caminhão da nota ${cam.numero_nota} foi recusado e não aceita amostra.`,
    });
  }
  if (!cam.descarga_fim_em) {
    return res.status(409).json({
      erro: `A descarga do caminhão da nota ${cam.numero_nota} ainda não foi encerrada. Encerre a descarga antes de coletar a amostra.`,
    });
  }

  // Já existe amostra neste caminhão?
  const { rows: [existente] } = await pool.query(
    'SELECT id FROM amostras WHERE caminhao_id = $1',
    [caminhaoId]
  );
  if (existente) {
    return res.status(409).json({
      erro: `Já existe amostra para o caminhão da nota ${cam.numero_nota}.`,
    });
  }

  const idades = await idadesDaConstrutora(pool, req.usuario.construtoraId);

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const { rows: [amostra] } = await client.query(
      `INSERT INTO amostras (caminhao_id, coletada_em, registrada_por)
       VALUES ($1, $2, $3)
       RETURNING id, caminhao_id, coletada_em`,
      [caminhaoId, coletada.toISOString(), req.usuario.id]
    );

    const corpos = [];
    for (const idade of idades) {
      // Dois corpos por idade, cada um com identificação única na construtora.
      for (let i = 0; i < 2; i++) {
        const identificacao = await proximaIdentificacao(client, req.usuario.construtoraId);
        const { rows: [cp] } = await client.query(
          `INSERT INTO corpos_prova (amostra_id, idade, identificacao, moldado_em, situacao)
           VALUES ($1, $2, $3, $4, 'moldado')
           RETURNING id, idade, resultado, identificacao, situacao, moldado_em`,
          [amostra.id, idade, identificacao, coletada.toISOString()]
        );
        corpos.push(cp);
      }
    }
    await client.query('COMMIT');

    const payload = formatarAmostra({
      ...amostra,
      numero_nota: cam.numero_nota,
      placa: cam.placa,
      lote_id: cam.lote_id,
      lote_numero: cam.lote_numero,
    }, corpos);
    if (clientId) {
      await gravarOperacao(pool, {
        clientId,
        construtoraId: req.usuario.construtoraId,
        usuarioId: req.usuario.id,
        tipo: 'moldar_amostra',
        resourceTipo: 'amostra',
        resourceId: payload.id,
        statusHttp: 201,
        resposta: payload,
      });
    }
    res.status(201).json(payload);
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}));

// Recusar caminhão (para o critério "caminhão recusado não aceita amostra").
// Só o técnico da obra; só se ainda não tiver amostra.
router.post('/caminhoes/:id/recusar', bloquearLabEscrita, permitir('obra'), rota(async (req, res) => {
  const { id } = req.params;
  if (!idValido(id)) return res.status(400).json({ erro: 'Identificador de caminhão inválido.' });

  const { rows: [cam] } = await pool.query(
    `SELECT c.id, c.numero_nota, c.recusado, c.descarga_fim_em, l.construtora_id
       FROM caminhoes c JOIN lotes l ON l.id = c.lote_id
      WHERE c.id = $1 AND c.numero_nota IS NOT NULL`,
    [Number(id)]
  );
  if (!cam) return res.status(404).json({ erro: 'Caminhão não encontrado.' });
  if (cam.construtora_id !== req.usuario.construtoraId) {
    return res.status(403).json({ erro: 'Acesso negado: este caminhão pertence a outra construtora.' });
  }
  if (cam.recusado) {
    return res.status(409).json({ erro: `O caminhão da nota ${cam.numero_nota} já está recusado.` });
  }

  const { rows: [am] } = await pool.query('SELECT id FROM amostras WHERE caminhao_id = $1', [cam.id]);
  if (am) {
    return res.status(409).json({
      erro: `Já existe amostra para o caminhão da nota ${cam.numero_nota}; não é possível recusá-lo depois.`,
    });
  }

  await pool.query('UPDATE caminhoes SET recusado = true WHERE id = $1', [cam.id]);
  res.json({ id: cam.id, recusado: true, numero_nota: cam.numero_nota });
}));


// ---------------------------------------------------------------------
// Consulta pela identificação (obra, construtora E laboratório)
// Resolve o problema central: o laudo volta até a peça certa.
// ---------------------------------------------------------------------

router.get('/corpos-prova/:identificacao', permitir('obra', 'construtora', 'laboratorio'), rota(async (req, res) => {
  const raw = (req.params.identificacao || '').trim();
  if (!raw || raw.length > 40) {
    return res.status(400).json({ erro: 'Identificação inválida.' });
  }
  const cadeia = await carregarCadeiaPorIdentificacao(pool, raw, req.usuario.construtoraId);
  if (!cadeia) {
    // Pode existir em outra construtora: não revela.
    const existe = await pool.query(
      'SELECT 1 FROM corpos_prova WHERE lower(identificacao) = lower($1) LIMIT 1',
      [raw]
    );
    if (existe.rows[0]) {
      return res.status(403).json({ erro: 'Acesso negado: este corpo de prova pertence a outra construtora.' });
    }
    return res.status(404).json({ erro: 'Corpo de prova não encontrado.' });
  }
  res.json(cadeia);
}));

// A partir de uma peça: todos os corpos de prova que a cobrem
// (via lotes que incluem a peça).
router.get('/pecas/:pecaId/corpos-prova', permitir('obra', 'construtora', 'laboratorio'), rota(async (req, res) => {
  const { pecaId } = req.params;
  if (!idValido(pecaId)) return res.status(400).json({ erro: 'Identificador de peça inválido.' });

  const { rows: [peca] } = await pool.query(
    `SELECT p.id, p.tipo, p.identificacao, pv.nome AS pavimento, o.id AS obra_id, o.nome AS obra_nome,
            o.construtora_id
       FROM pecas p
       JOIN pavimentos pv ON pv.id = p.pavimento_id
       JOIN obras o ON o.id = pv.obra_id
      WHERE p.id = $1`,
    [Number(pecaId)]
  );
  if (!peca) return res.status(404).json({ erro: 'Peça não encontrada.' });
  if (peca.construtora_id !== req.usuario.construtoraId) {
    return res.status(403).json({ erro: 'Acesso negado: esta peça pertence a outra construtora.' });
  }

  const { rows } = await pool.query(
    `SELECT cp.id, cp.identificacao, cp.idade, cp.resultado,
            a.id AS amostra_id, a.coletada_em,
            c.id AS caminhao_id, c.numero_nota, c.placa,
            l.id AS lote_id, l.numero AS lote_numero, l.data_concretagem
       FROM lote_pecas lp
       JOIN lotes l ON l.id = lp.lote_id
       JOIN caminhoes c ON c.lote_id = l.id
       JOIN amostras a ON a.caminhao_id = c.id
       JOIN corpos_prova cp ON cp.amostra_id = a.id
      WHERE lp.peca_id = $1
        AND l.construtora_id = $2
      ORDER BY l.data_concretagem DESC, cp.idade, cp.identificacao`,
    [peca.id, req.usuario.construtoraId]
  );

  res.json({
    peca: {
      id: peca.id,
      tipo: peca.tipo,
      identificacao: peca.identificacao,
      pavimento: peca.pavimento,
      obra: peca.obra_nome,
      rotulo: `${peca.tipo === 'pilar' ? 'Pilar' : peca.tipo === 'viga' ? 'Viga' : peca.tipo === 'laje' ? 'Laje' : 'Fundação'} ${peca.identificacao}`,
    },
    corpos_prova: rows.map((r) => ({
      id: r.id,
      identificacao: r.identificacao,
      idade: r.idade,
      resultado: r.resultado != null ? Number(r.resultado) : null,
      amostra_id: r.amostra_id,
      coletada_em: r.coletada_em,
      caminhao: { id: r.caminhao_id, numero_nota: r.numero_nota, placa: r.placa },
      lote: { id: r.lote_id, numero: r.lote_numero, data_concretagem: r.data_concretagem },
    })),
  });
}));



// Exemplares de uma amostra (por idade) — cálculo no servidor
router.get('/:id/exemplares', permitir('obra', 'construtora'), rota(async (req, res) => {
  const { id } = req.params;
  if (!idValido(id)) return res.status(400).json({ erro: 'Identificador de amostra inválido.' });

  const { rows: [am] } = await pool.query(
    `SELECT a.id, a.coletada_em, c.numero_nota, c.placa, l.id AS lote_id, l.numero AS lote_numero, l.construtora_id
       FROM amostras a
       JOIN caminhoes c ON c.id = a.caminhao_id
       JOIN lotes l ON l.id = c.lote_id
      WHERE a.id = $1`,
    [Number(id)]
  );
  if (!am) return res.status(404).json({ erro: 'Amostra não encontrada.' });
  if (am.construtora_id !== req.usuario.construtoraId) {
    return res.status(403).json({ erro: 'Acesso negado: esta amostra pertence a outra construtora.' });
  }

  const { rows: corpos } = await pool.query(
    `SELECT id, identificacao, idade, resultado, situacao
       FROM corpos_prova WHERE amostra_id = $1 ORDER BY idade, id`,
    [am.id]
  );

  const porIdade = new Map();
  for (const c of corpos) {
    if (!porIdade.has(c.idade)) porIdade.set(c.idade, []);
    porIdade.get(c.idade).push(c);
  }
  const exemplares = [];
  for (const [idade, lista] of [...porIdade.entries()].sort((a, b) => a[0] - b[0])) {
    exemplares.push(montarExemplar(am.id, idade, lista, {
      lote_id: am.lote_id,
      lote_numero: am.lote_numero,
      numero_nota: am.numero_nota,
      placa: am.placa,
      coletada_em: am.coletada_em,
    }));
  }

  res.json({
    amostra_id: am.id,
    regra: 'O resultado do exemplar é o maior valor entre os corpos da mesma amostra e idade — nunca a média.',
    exemplares,
  });
}));


module.exports = router;
