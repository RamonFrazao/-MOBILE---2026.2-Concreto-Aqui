const router = require('express').Router();
const pool = require('../db');
const { autenticar } = require('../middleware/auth');

// Cura, descarte e remessa de corpos de prova.
//
// Máquina de estados do CP:
//   moldado → em_cura → em_remessa → no_laboratorio → rompido
//                  ↘ descartado (motivo obrigatório; não some do sistema)
//
// Regras:
//   - Início de cura: só obra, CP em moldado.
//   - Remessa: laboratório de destino, data, lista de CPs em_cura (ou moldado? só em_cura).
//   - CP só em uma remessa ativa por vez.
//   - Lab vê remessas destinadas a ele / da construtora.

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

const SITUACOES = new Set(['moldado', 'em_cura', 'em_remessa', 'no_laboratorio', 'rompido', 'descartado']);

function formatarCorpo(r) {
  return {
    id: r.id,
    identificacao: r.identificacao,
    idade: r.idade,
    resultado: r.resultado != null ? Number(r.resultado) : null,
    situacao: r.situacao,
    cura_inicio_em: r.cura_inicio_em || null,
    descartado_em: r.descartado_em || null,
    motivo_descarte: r.motivo_descarte || null,
    amostra_id: r.amostra_id,
    numero_nota: r.numero_nota,
    placa: r.placa,
    lote_numero: r.lote_numero,
  };
}

async function corpoDaConstrutora(executor, corpoId, construtoraId) {
  const { rows: [r] } = await executor.query(
    `SELECT cp.id, cp.identificacao, cp.idade, cp.resultado, cp.situacao,
            cp.cura_inicio_em, cp.descartado_em, cp.motivo_descarte, cp.amostra_id,
            c.numero_nota, c.placa, l.numero AS lote_numero, l.construtora_id
       FROM corpos_prova cp
       JOIN amostras a ON a.id = cp.amostra_id
       JOIN caminhoes c ON c.id = a.caminhao_id
       JOIN lotes l ON l.id = c.lote_id
      WHERE cp.id = $1`,
    [corpoId]
  );
  if (!r) return null;
  if (r.construtora_id !== construtoraId) return { forbidden: true };
  return r;
}

// -------------------------------------------------------------------------
// Início da cura na obra
// -------------------------------------------------------------------------
router.post('/corpos-prova/:id/cura', permitir('obra'), rota(async (req, res) => {
  const { id } = req.params;
  if (!idValido(id)) return res.status(400).json({ erro: 'Identificador de corpo de prova inválido.' });

  const inicio = instante(req.body?.cura_inicio_em) || new Date();
  const corpo = await corpoDaConstrutora(pool, Number(id), req.usuario.construtoraId);
  if (!corpo) return res.status(404).json({ erro: 'Corpo de prova não encontrado.' });
  if (corpo.forbidden) return res.status(403).json({ erro: 'Acesso negado: este corpo de prova pertence a outra construtora.' });

  if (corpo.situacao === 'descartado') {
    return res.status(409).json({ erro: `O corpo ${corpo.identificacao} foi descartado e não entra em cura.` });
  }
  if (corpo.situacao !== 'moldado') {
    return res.status(409).json({
      erro: `O corpo ${corpo.identificacao} está em situação "${corpo.situacao}"; só se registra cura a partir de "moldado".`,
    });
  }

  const { rows: [salvo] } = await pool.query(
    `UPDATE corpos_prova
        SET situacao = 'em_cura', cura_inicio_em = $2
      WHERE id = $1 AND situacao = 'moldado'
  RETURNING id, identificacao, idade, resultado, situacao, cura_inicio_em, descartado_em, motivo_descarte, amostra_id`,
    [corpo.id, inicio.toISOString()]
  );
  if (!salvo) {
    return res.status(409).json({ erro: `O corpo ${corpo.identificacao} não está mais em "moldado".` });
  }
  res.json(formatarCorpo({ ...corpo, ...salvo }));
}));

// -------------------------------------------------------------------------
// Descarte com motivo (não some do sistema)
// -------------------------------------------------------------------------
router.post('/corpos-prova/:id/descartar', permitir('obra'), rota(async (req, res) => {
  const { id } = req.params;
  if (!idValido(id)) return res.status(400).json({ erro: 'Identificador de corpo de prova inválido.' });

  const motivo = typeof req.body?.motivo === 'string' ? req.body.motivo.trim() : '';
  if (!motivo || motivo.length < 3) {
    return res.status(400).json({ erro: 'Informe o motivo do descarte (pelo menos 3 caracteres).' });
  }
  if (motivo.length > 500) {
    return res.status(400).json({ erro: 'O motivo do descarte aceita no máximo 500 caracteres.' });
  }

  const corpo = await corpoDaConstrutora(pool, Number(id), req.usuario.construtoraId);
  if (!corpo) return res.status(404).json({ erro: 'Corpo de prova não encontrado.' });
  if (corpo.forbidden) return res.status(403).json({ erro: 'Acesso negado: este corpo de prova pertence a outra construtora.' });

  if (corpo.situacao === 'descartado') {
    return res.status(409).json({ erro: `O corpo ${corpo.identificacao} já está descartado.` });
  }
  if (corpo.situacao === 'rompido' || corpo.situacao === 'no_laboratorio' || corpo.situacao === 'em_remessa') {
    return res.status(409).json({
      erro: `O corpo ${corpo.identificacao} está em "${corpo.situacao}" e não pode ser descartado pela obra.`,
    });
  }

  const { rows: [salvo] } = await pool.query(
    `UPDATE corpos_prova
        SET situacao = 'descartado', descartado_em = now(), motivo_descarte = $2
      WHERE id = $1 AND situacao IN ('moldado', 'em_cura')
  RETURNING id, identificacao, idade, resultado, situacao, cura_inicio_em, descartado_em, motivo_descarte, amostra_id`,
    [corpo.id, motivo]
  );
  if (!salvo) {
    return res.status(409).json({ erro: `Não foi possível descartar o corpo ${corpo.identificacao}.` });
  }
  res.json(formatarCorpo({ ...corpo, ...salvo }));
}));

// -------------------------------------------------------------------------
// Remessas
// -------------------------------------------------------------------------

function formatarRemessa(r, itens = []) {
  return {
    id: r.id,
    laboratorio_id: r.laboratorio_id,
    laboratorio_nome: r.laboratorio_nome,
    enviada_em: r.enviada_em,
    status: r.status,
    recebida_em: r.recebida_em,
    criado_em: r.criado_em,
    qtd_corpos: itens.length || Number(r.qtd_corpos) || 0,
    corpos_prova: itens.map((i) => ({
      id: i.id,
      identificacao: i.identificacao,
      idade: i.idade,
      situacao: i.situacao,
      resultado: i.resultado != null ? Number(i.resultado) : null,
    })),
  };
}

// Lista remessas da construtora (obra/construtora) ou do laboratório do usuário.
router.get('/', permitir('obra', 'construtora', 'laboratorio'), rota(async (req, res) => {
  const params = [req.usuario.construtoraId];
  let filtro = ' WHERE r.construtora_id = $1';

  if (req.usuario.perfil === 'laboratorio') {
    // Lab só vê remessas destinadas a ele — obrigatório ter laboratorioId no token.
    if (!req.usuario.laboratorioId) {
      return res.status(403).json({
        erro: 'Acesso negado: seu usuário de laboratório não está ligado a um laboratório.',
      });
    }
    params.push(req.usuario.laboratorioId);
    filtro += ` AND r.laboratorio_id = $${params.length}`;
  }

  if (req.query.status) {
    const st = String(req.query.status);
    if (!['enviada', 'recebida', 'cancelada'].includes(st)) {
      return res.status(400).json({ erro: 'Status de remessa inválido.' });
    }
    params.push(st);
    filtro += ` AND r.status = $${params.length}`;
  }

  const { rows } = await pool.query(
    `SELECT r.id, r.laboratorio_id, lab.nome AS laboratorio_nome,
            r.enviada_em, r.status, r.recebida_em, r.criado_em,
            (SELECT COUNT(*)::int FROM remessa_itens ri WHERE ri.remessa_id = r.id) AS qtd_corpos
       FROM remessas r
       JOIN laboratorios lab ON lab.id = r.laboratorio_id
      ${filtro}
      ORDER BY r.enviada_em DESC, r.id DESC
      LIMIT 200`,
    params
  );
  res.json(rows.map((r) => formatarRemessa(r)));
}));

router.get('/:id', permitir('obra', 'construtora', 'laboratorio'), rota(async (req, res) => {
  const { id } = req.params;
  if (!idValido(id)) return res.status(400).json({ erro: 'Identificador de remessa inválido.' });

  const { rows: [r] } = await pool.query(
    `SELECT r.id, r.laboratorio_id, lab.nome AS laboratorio_nome, r.construtora_id,
            r.enviada_em, r.status, r.recebida_em, r.criado_em
       FROM remessas r
       JOIN laboratorios lab ON lab.id = r.laboratorio_id
      WHERE r.id = $1`,
    [Number(id)]
  );
  if (!r) return res.status(404).json({ erro: 'Remessa não encontrada.' });
  if (r.construtora_id !== req.usuario.construtoraId) {
    return res.status(403).json({ erro: 'Acesso negado: esta remessa pertence a outra construtora.' });
  }
  if (req.usuario.perfil === 'laboratorio') {
    if (!req.usuario.laboratorioId) {
      return res.status(403).json({
        erro: 'Acesso negado: seu usuário de laboratório não está ligado a um laboratório.',
      });
    }
    if (r.laboratorio_id !== req.usuario.laboratorioId) {
      return res.status(403).json({ erro: 'Acesso negado: esta remessa não é do seu laboratório.' });
    }
  }

  const { rows: itens } = await pool.query(
    `SELECT cp.id, cp.identificacao, cp.idade, cp.situacao, cp.resultado
       FROM remessa_itens ri
       JOIN corpos_prova cp ON cp.id = ri.corpo_prova_id
      WHERE ri.remessa_id = $1
      ORDER BY cp.identificacao`,
    [r.id]
  );
  res.json(formatarRemessa(r, itens));
}));

// Cria remessa: laboratório de destino, data e lista de CPs.
router.post('/', permitir('obra'), rota(async (req, res) => {
  const corpo = req.body || {};
  const labId = Number(corpo.laboratorio_id);
  const enviada = instante(corpo.enviada_em) || new Date();
  let ids = corpo.corpos_prova_ids;
  if (!Array.isArray(ids)) ids = [];
  ids = [...new Set(ids.map((v) => Number(v)).filter((n) => Number.isInteger(n) && n > 0))];

  if (!Number.isInteger(labId) || labId < 1) {
    return res.status(400).json({ erro: 'Informe o laboratório de destino.' });
  }
  if (ids.length === 0) {
    return res.status(400).json({ erro: 'Inclua pelo menos um corpo de prova na remessa.' });
  }

  const { rows: [lab] } = await pool.query(
    `SELECT id, nome FROM laboratorios
      WHERE id = $1 AND construtora_id = $2 AND ativo = true`,
    [labId, req.usuario.construtoraId]
  );
  if (!lab) {
    return res.status(404).json({ erro: 'Laboratório não encontrado ou inativo nesta construtora.' });
  }

  // Carrega e valida cada CP.
  const { rows: cps } = await pool.query(
    `SELECT cp.id, cp.identificacao, cp.idade, cp.situacao, cp.resultado, l.construtora_id
       FROM corpos_prova cp
       JOIN amostras a ON a.id = cp.amostra_id
       JOIN caminhoes c ON c.id = a.caminhao_id
       JOIN lotes l ON l.id = c.lote_id
      WHERE cp.id = ANY($1::int[])`,
    [ids]
  );
  if (cps.length !== ids.length) {
    return res.status(404).json({ erro: 'Um ou mais corpos de prova não foram encontrados.' });
  }
  for (const cp of cps) {
    if (cp.construtora_id !== req.usuario.construtoraId) {
      return res.status(403).json({ erro: 'Acesso negado: há corpo de prova de outra construtora.' });
    }
    if (cp.situacao === 'descartado') {
      return res.status(409).json({ erro: `O corpo ${cp.identificacao} foi descartado e não entra em remessa.` });
    }
    if (cp.situacao !== 'em_cura') {
      return res.status(409).json({
        erro: `O corpo ${cp.identificacao} está em "${cp.situacao}"; só entram em remessa corpos em cura.`,
      });
    }
  }

  // Já em outra remessa ativa?
  const { rows: ocupados } = await pool.query(
    `SELECT cp.identificacao, ri.remessa_id
       FROM remessa_itens ri
       JOIN remessas r ON r.id = ri.remessa_id
       JOIN corpos_prova cp ON cp.id = ri.corpo_prova_id
      WHERE ri.corpo_prova_id = ANY($1::int[])
        AND r.status IN ('enviada', 'recebida')`,
    [ids]
  );
  if (ocupados.length) {
    return res.status(409).json({
      erro: `Corpo de prova só entra em uma remessa por vez: ${ocupados.map((o) => o.identificacao).join(', ')}.`,
    });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const { rows: [rem] } = await client.query(
      `INSERT INTO remessas (construtora_id, laboratorio_id, enviada_em, registrada_por, status)
       VALUES ($1, $2, $3, $4, 'enviada')
       RETURNING id, laboratorio_id, enviada_em, status, recebida_em, criado_em`,
      [req.usuario.construtoraId, labId, enviada.toISOString(), req.usuario.id]
    );

    for (const cp of cps) {
      await client.query(
        `INSERT INTO remessa_itens (remessa_id, corpo_prova_id) VALUES ($1, $2)`,
        [rem.id, cp.id]
      );
      await client.query(
        `UPDATE corpos_prova SET situacao = 'em_remessa' WHERE id = $1 AND situacao = 'em_cura'`,
        [cp.id]
      );
    }
    await client.query('COMMIT');

    const { rows: itens } = await pool.query(
      `SELECT cp.id, cp.identificacao, cp.idade, cp.situacao, cp.resultado
         FROM remessa_itens ri
         JOIN corpos_prova cp ON cp.id = ri.corpo_prova_id
        WHERE ri.remessa_id = $1
        ORDER BY cp.identificacao`,
      [rem.id]
    );
    res.status(201).json(formatarRemessa({ ...rem, laboratorio_nome: lab.nome }, itens));
  } catch (err) {
    await client.query('ROLLBACK');
    if (err.code === 'unique_violation' || (err.message && err.message.includes('já está em outra remessa'))) {
      return res.status(409).json({ erro: 'Corpo de prova só entra em uma remessa por vez.' });
    }
    throw err;
  } finally {
    client.release();
  }
}));

// Laboratório confirma recebimento da remessa → CPs passam a no_laboratorio.
router.post('/:id/receber', permitir('laboratorio'), rota(async (req, res) => {
  const { id } = req.params;
  if (!idValido(id)) return res.status(400).json({ erro: 'Identificador de remessa inválido.' });

  const { rows: [r] } = await pool.query(
    `SELECT id, construtora_id, laboratorio_id, status FROM remessas WHERE id = $1`,
    [Number(id)]
  );
  if (!r) return res.status(404).json({ erro: 'Remessa não encontrada.' });
  if (r.construtora_id !== req.usuario.construtoraId) {
    return res.status(403).json({ erro: 'Acesso negado: esta remessa pertence a outra construtora.' });
  }
  if (!req.usuario.laboratorioId) {
    return res.status(403).json({
      erro: 'Acesso negado: seu usuário de laboratório não está ligado a um laboratório.',
    });
  }
  if (r.laboratorio_id !== req.usuario.laboratorioId) {
    return res.status(403).json({ erro: 'Acesso negado: esta remessa não é do seu laboratório.' });
  }
  if (r.status !== 'enviada') {
    return res.status(409).json({ erro: `A remessa está como "${r.status}" e não pode ser recebida.` });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      `UPDATE remessas SET status = 'recebida', recebida_em = now() WHERE id = $1 AND status = 'enviada'`,
      [r.id]
    );
    await client.query(
      `UPDATE corpos_prova cp
          SET situacao = 'no_laboratorio'
         FROM remessa_itens ri
        WHERE ri.remessa_id = $1 AND ri.corpo_prova_id = cp.id AND cp.situacao = 'em_remessa'`,
      [r.id]
    );
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }

  const { rows: [full] } = await pool.query(
    `SELECT r.id, r.laboratorio_id, lab.nome AS laboratorio_nome,
            r.enviada_em, r.status, r.recebida_em, r.criado_em
       FROM remessas r JOIN laboratorios lab ON lab.id = r.laboratorio_id
      WHERE r.id = $1`,
    [r.id]
  );
  const { rows: itens } = await pool.query(
    `SELECT cp.id, cp.identificacao, cp.idade, cp.situacao, cp.resultado
       FROM remessa_itens ri JOIN corpos_prova cp ON cp.id = ri.corpo_prova_id
      WHERE ri.remessa_id = $1 ORDER BY cp.identificacao`,
    [r.id]
  );
  res.json(formatarRemessa(full, itens));
}));


// -------------------------------------------------------------------------
// Lançamento de resultado de rompimento (só laboratório)
// Data do rompimento + idade real (a partir da moldagem) + resistência MPa.
// Correção = novo lançamento com motivo; o anterior permanece.
// Obra e construtora só leem — não editam.
// -------------------------------------------------------------------------

function idadeRealDias(moldadoEm, rompidoEm) {
  const ms = rompidoEm.getTime() - moldadoEm.getTime();
  if (ms < 0) return null;
  // Dias com 2 casas: não arredonda 30 para 28.
  return Math.round((ms / (1000 * 60 * 60 * 24)) * 100) / 100;
}

async function carregarCorpoParaLab(executor, corpoId, usuario) {
  const { rows: [r] } = await executor.query(
    `SELECT cp.id, cp.identificacao, cp.idade, cp.resultado, cp.situacao,
            cp.moldado_em, cp.criado_em, a.coletada_em, a.id AS amostra_id,
            c.numero_nota, c.placa, l.numero AS lote_numero, l.construtora_id,
            (
              SELECT ri.remessa_id FROM remessa_itens ri
              JOIN remessas rm ON rm.id = ri.remessa_id
              WHERE ri.corpo_prova_id = cp.id AND rm.status IN ('enviada', 'recebida')
              ORDER BY rm.id DESC LIMIT 1
            ) AS remessa_id,
            (
              SELECT rm.laboratorio_id FROM remessa_itens ri
              JOIN remessas rm ON rm.id = ri.remessa_id
              WHERE ri.corpo_prova_id = cp.id AND rm.status IN ('enviada', 'recebida')
              ORDER BY rm.id DESC LIMIT 1
            ) AS laboratorio_id
       FROM corpos_prova cp
       JOIN amostras a ON a.id = cp.amostra_id
       JOIN caminhoes c ON c.id = a.caminhao_id
       JOIN lotes l ON l.id = c.lote_id
      WHERE cp.id = $1`,
    [corpoId]
  );
  if (!r) return null;
  if (r.construtora_id !== usuario.construtoraId) return { forbidden: true };
  if (usuario.perfil === 'laboratorio') {
    if (!usuario.laboratorioId) return { forbidden: true };
    if (r.laboratorio_id !== usuario.laboratorioId) return { forbidden: true };
  }
  return r;
}

// Detalhe do CP para o lab lançar: inclui moldado_em e idade real sugerida.
router.get('/corpos-prova/:id/para-rompimento', permitir('laboratorio'), rota(async (req, res) => {
  const { id } = req.params;
  if (!idValido(id)) return res.status(400).json({ erro: 'Identificador de corpo de prova inválido.' });
  if (!req.usuario.laboratorioId) {
    return res.status(403).json({
      erro: 'Acesso negado: seu usuário de laboratório não está ligado a um laboratório.',
    });
  }

  const corpo = await carregarCorpoParaLab(pool, Number(id), req.usuario);
  if (!corpo) return res.status(404).json({ erro: 'Corpo de prova não encontrado.' });
  if (corpo.forbidden) {
    return res.status(403).json({ erro: 'Acesso negado: este corpo de prova não é do seu laboratório.' });
  }

  const ref = corpo.moldado_em || corpo.coletada_em || corpo.criado_em;
  const agora = new Date();
  const idadeSugerida = ref ? idadeRealDias(new Date(ref), agora) : null;

  const { rows: historico } = await pool.query(
    `SELECT id, rompido_em, idade_real_dias, resistencia_mpa, idade_nominal,
            motivo_correcao, corrige_resultado_id, criado_em
       FROM resultados_rompimento
      WHERE corpo_prova_id = $1
      ORDER BY criado_em DESC`,
    [corpo.id]
  );

  res.json({
    id: corpo.id,
    identificacao: corpo.identificacao,
    idade_nominal: corpo.idade,
    situacao: corpo.situacao,
    resultado_vigente: corpo.resultado != null ? Number(corpo.resultado) : null,
    moldado_em: ref,
    idade_real_sugerida_dias: idadeSugerida,
    numero_nota: corpo.numero_nota,
    placa: corpo.placa,
    lote_numero: corpo.lote_numero,
    historico: historico.map((h) => ({
      id: h.id,
      rompido_em: h.rompido_em,
      idade_real_dias: Number(h.idade_real_dias),
      resistencia_mpa: Number(h.resistencia_mpa),
      idade_nominal: h.idade_nominal,
      motivo_correcao: h.motivo_correcao,
      corrige_resultado_id: h.corrige_resultado_id,
      criado_em: h.criado_em,
    })),
  });
}));

// Lança (ou corrige) resultado. Correção: enviar motivo_correcao.
router.post('/corpos-prova/:id/resultados', permitir('laboratorio'), rota(async (req, res) => {
  const { id } = req.params;
  if (!idValido(id)) return res.status(400).json({ erro: 'Identificador de corpo de prova inválido.' });
  if (!req.usuario.laboratorioId) {
    return res.status(403).json({
      erro: 'Acesso negado: seu usuário de laboratório não está ligado a um laboratório.',
    });
  }

  const body = req.body || {};
  const rompido = instante(body.rompido_em);
  const resistencia = typeof body.resistencia_mpa === 'number'
    ? body.resistencia_mpa
    : (typeof body.resistencia_mpa === 'string' ? Number(String(body.resistencia_mpa).replace(',', '.')) : null);
  const motivo = typeof body.motivo_correcao === 'string' ? body.motivo_correcao.trim() : '';

  if (!rompido) {
    return res.status(400).json({ erro: 'Informe a data e hora do rompimento (formato ISO, com fuso).' });
  }
  if (resistencia == null || !Number.isFinite(resistencia) || resistencia <= 0 || resistencia > 200) {
    return res.status(400).json({ erro: 'Informe a resistência em MPa (número maior que zero).' });
  }

  const corpo = await carregarCorpoParaLab(pool, Number(id), req.usuario);
  if (!corpo) return res.status(404).json({ erro: 'Corpo de prova não encontrado.' });
  if (corpo.forbidden) {
    return res.status(403).json({ erro: 'Acesso negado: este corpo de prova não é do seu laboratório.' });
  }
  if (corpo.situacao === 'descartado') {
    return res.status(409).json({ erro: `O corpo ${corpo.identificacao} foi descartado.` });
  }
  if (!['no_laboratorio', 'em_remessa', 'rompido'].includes(corpo.situacao)) {
    return res.status(409).json({
      erro: `O corpo ${corpo.identificacao} está em "${corpo.situacao}"; só se lança resultado após chegar ao laboratório.`,
    });
  }

  const ref = new Date(corpo.moldado_em || corpo.coletada_em || corpo.criado_em);
  const idadeReal = idadeRealDias(ref, rompido);
  if (idadeReal == null) {
    return res.status(400).json({
      erro: 'A data do rompimento não pode ser anterior à moldagem/coleta do corpo de prova.',
    });
  }

  // Idade real pode ser informada pelo cliente, mas a API recalcula e confere.
  let idadeInformada = body.idade_real_dias;
  if (idadeInformada != null) {
    idadeInformada = typeof idadeInformada === 'number' ? idadeInformada : Number(String(idadeInformada).replace(',', '.'));
    if (!Number.isFinite(idadeInformada) || Math.abs(idadeInformada - idadeReal) > 0.5) {
      return res.status(400).json({
        erro: `Idade real conferida pela API: ${idadeReal} dias (a partir da moldagem). Valor informado diverge demais.`,
        idade_real_dias: idadeReal,
        moldado_em: ref.toISOString(),
      });
    }
  }

  const jaTemResultado = corpo.resultado != null || corpo.situacao === 'rompido';
  if (jaTemResultado && (!motivo || motivo.length < 3)) {
    return res.status(400).json({
      erro: 'Já existe resultado para este corpo. Correção exige motivo (novo lançamento, sem apagar o anterior).',
    });
  }

  let corrigeId = null;
  if (jaTemResultado) {
    const { rows: [ult] } = await pool.query(
      `SELECT id FROM resultados_rompimento WHERE corpo_prova_id = $1 ORDER BY criado_em DESC LIMIT 1`,
      [corpo.id]
    );
    corrigeId = ult ? ult.id : null;
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const { rows: [lanc] } = await client.query(
      `INSERT INTO resultados_rompimento
         (corpo_prova_id, rompido_em, idade_real_dias, resistencia_mpa, idade_nominal,
          motivo_correcao, corrige_resultado_id, lancado_por)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       RETURNING id, rompido_em, idade_real_dias, resistencia_mpa, idade_nominal,
                 motivo_correcao, corrige_resultado_id, criado_em`,
      [
        corpo.id,
        rompido.toISOString(),
        idadeReal,
        resistencia,
        corpo.idade,
        jaTemResultado ? motivo : null,
        corrigeId,
        req.usuario.id,
      ]
    );
    await client.query(
      `UPDATE corpos_prova
          SET resultado = $2, situacao = 'rompido'
        WHERE id = $1`,
      [corpo.id, resistencia]
    );
    await client.query('COMMIT');

    res.status(201).json({
      lancamento: {
        id: lanc.id,
        rompido_em: lanc.rompido_em,
        idade_real_dias: Number(lanc.idade_real_dias),
        resistencia_mpa: Number(lanc.resistencia_mpa),
        idade_nominal: lanc.idade_nominal,
        motivo_correcao: lanc.motivo_correcao,
        corrige_resultado_id: lanc.corrige_resultado_id,
        criado_em: lanc.criado_em,
      },
      corpo_prova: {
        id: corpo.id,
        identificacao: corpo.identificacao,
        situacao: 'rompido',
        resultado: resistencia,
        idade_nominal: corpo.idade,
        moldado_em: ref.toISOString(),
      },
    });
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}));

// Histórico de lançamentos (obra e lab leem; obra NÃO edita).
router.get('/corpos-prova/:id/resultados', permitir('obra', 'construtora', 'laboratorio'), rota(async (req, res) => {
  const { id } = req.params;
  if (!idValido(id)) return res.status(400).json({ erro: 'Identificador de corpo de prova inválido.' });

  const corpo = await carregarCorpoParaLab(pool, Number(id), req.usuario);
  if (!corpo) return res.status(404).json({ erro: 'Corpo de prova não encontrado.' });
  if (corpo.forbidden) {
    return res.status(403).json({ erro: 'Acesso negado.' });
  }

  const { rows } = await pool.query(
    `SELECT id, rompido_em, idade_real_dias, resistencia_mpa, idade_nominal,
            motivo_correcao, corrige_resultado_id, criado_em
       FROM resultados_rompimento
      WHERE corpo_prova_id = $1
      ORDER BY criado_em DESC`,
    [corpo.id]
  );

  const ref = corpo.moldado_em || corpo.coletada_em || corpo.criado_em;
  res.json({
    corpo_prova: {
      id: corpo.id,
      identificacao: corpo.identificacao,
      idade_nominal: corpo.idade,
      situacao: corpo.situacao,
      resultado_vigente: corpo.resultado != null ? Number(corpo.resultado) : null,
      moldado_em: ref,
    },
    lancamentos: rows.map((h) => ({
      id: h.id,
      rompido_em: h.rompido_em,
      idade_real_dias: Number(h.idade_real_dias),
      resistencia_mpa: Number(h.resistencia_mpa),
      idade_nominal: h.idade_nominal,
      motivo_correcao: h.motivo_correcao,
      corrige_resultado_id: h.corrige_resultado_id,
      criado_em: h.criado_em,
    })),
  });
}));

// Obra NÃO pode alterar resultado (rota explícita de recusa).
router.put('/corpos-prova/:id/resultados', permitir('obra', 'construtora', 'laboratorio'), rota(async (req, res) => {
  if (req.usuario.perfil === 'obra' || req.usuario.perfil === 'construtora') {
    return res.status(403).json({
      erro: 'Resultado lançado não pode ser editado pelo perfil da obra. O laboratório registra correção como novo lançamento.',
    });
  }
  return res.status(405).json({
    erro: 'Use POST /remessas/corpos-prova/:id/resultados para lançar ou corrigir o resultado.',
  });
}));


module.exports = router;
