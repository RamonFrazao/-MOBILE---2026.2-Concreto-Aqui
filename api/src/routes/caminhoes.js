const router = require('express').Router();
const pool = require('../db');
const { autenticar } = require('../middleware/auth');
const {
  lerConfig, prazoDoCaminhao, situacaoPrazo, estaForaDoPrazo,
  sqlLimite, sqlRestanteSegundos, sqlExcedeuMinutos,
} = require('../prazos');

// O caminhão que chega vem com a nota de entrega. O técnico da obra
// registra os dados da nota, ligando o caminhão ao lote e ao pedido, e o
// sistema compara a nota com o pedido e mostra as divergências antes de
// qualquer coisa descer da betoneira.
//
// Regras gerais, na ordem em que são conferidas:
//   1. Sem token válido -> 401.
//   2. Perfil "laboratorio" -> 403 em todas as rotas daqui (o laboratório
//      só lança resultado de rompimento).
//   3. O usuário precisa estar ligado a uma construtora.
//   4. Registrar caminhão é só do técnico da obra (perfil "obra"); ver os
//      caminhões e a comparação com o pedido, também da construtora.
//   5. Lote, pedido e central de outra construtora -> 403 com mensagem clara.
router.use(autenticar);

router.use((req, res, next) => {
  if (req.usuario.perfil === 'laboratorio') {
    return res.status(403).json({
      erro: 'Acesso negado: o perfil de laboratório não acessa pedidos, lotes nem caminhões.',
    });
  }
  next();
});

router.use((req, res, next) => {
  if (!req.usuario.construtoraId) {
    return res.status(403).json({ erro: 'Acesso negado: o seu usuário não está ligado a uma construtora.' });
  }
  next();
});

// A construtora sempre tem a sua configuração de prazo (com os valores
// padrão do schema) antes de qualquer consulta que dependa dela.
router.use((req, res, next) => {
  lerConfig(pool, req.usuario.construtoraId).then(() => next(), next);
});

const MSG_PERFIL = 'Acesso negado: o seu perfil não tem acesso a este recurso.';
const permitir = (...perfis) => (req, res, next) => {
  if (!perfis.includes(req.usuario.perfil)) return res.status(403).json({ erro: MSG_PERFIL });
  next();
};

const idValido = (v) => /^\d{1,9}$/.test(String(v));
const VOLUME_MAXIMO = 20; // m³: acima disso não cabe numa betoneira
const FCK_MAXIMO = 200;
const CONSUMO_MAXIMO = 1000; // kg/m³

const rota = (fn) => async (req, res) => {
  try {
    await fn(req, res);
  } catch (err) {
    console.error(err);
    if (!res.headersSent) res.status(500).json({ erro: 'Erro interno.' });
  }
};

const texto = (v) => (typeof v === 'string' ? v.trim() : '');

function numero(v) {
  if (typeof v === 'number') return Number.isFinite(v) ? v : null;
  if (typeof v === 'string' && v.trim() !== '') {
    const n = Number(v.replace(',', '.'));
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

const vazio = (v) => v === undefined || v === null || (typeof v === 'string' && v.trim() === '');

// Data e hora de verdade: só aceita o formato ISO COM fuso (Z ou +hh:mm),
// para o servidor nunca interpretar a hora no fuso dele em vez do da obra.
// O calendário é conferido à parte: o parser do JavaScript aceita
// "2026-02-31" e o transforma em 03/03 sem avisar, e um horário que vira
// outro dia calcularia o prazo de descarga errado.
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

// Placa brasileira, no padrão antigo (ABC-1234) ou Mercosul (ABC-1D23).
function placaValida(v) {
  if (typeof v !== 'string') return null;
  const p = v.toUpperCase().replace(/[\s-]/g, '');
  return /^[A-Z]{3}\d[A-Z0-9]\d{2}$/.test(p) ? `${p.slice(0, 3)}-${p.slice(3)}` : null;
}

const ROTULOS_TIPO = { pilar: 'Pilar', viga: 'Viga', laje: 'Laje', fundacao: 'Fundação' };
const rotuloPeca = (tipo, identificacao) => `${ROTULOS_TIPO[tipo] || tipo} ${identificacao}`;
const fmt = (n) => Number(n).toFixed(2).replace('.', ',');

// ---------------------------------------------------------------------
// Comparação da nota com o pedido
// ---------------------------------------------------------------------

// Devolve uma linha por item comparado. O volume compara o que o caminhão
// traz com o SALDO do pedido na hora em que ele chegou (o pedido de 8 m³
// pode vir em vários caminhões: um de 5 m³ não é divergência, um que
// passa do saldo é). Além de fck, classe e volume, a nota também é
// conferida quanto à central e a peça de destino do pedido estar no lote.
function conferir(r) {
  const norm = (s) => String(s).toUpperCase().replace(/\s+/g, '');
  const volume = Number(r.volume);
  const saldo = Math.max(0, Number(r.saldo_antes));
  const excesso = volume - saldo;
  const itens = [];

  const classeDiverge = norm(r.classe_nota) !== norm(r.pedido_classe_nome);
  itens.push({
    campo: 'classe', rotulo: 'Classe',
    pedido: r.pedido_classe_nome, nota: r.classe_nota, diverge: classeDiverge,
    detalhe: classeDiverge ? `A nota veio ${r.classe_nota}; o pedido era ${r.pedido_classe_nome}.` : null,
  });

  const fckDiverge = Number(r.fck_nota) !== Number(r.pedido_fck);
  itens.push({
    campo: 'fck', rotulo: 'fck',
    pedido: `${r.pedido_fck} MPa`, nota: `${r.fck_nota} MPa`, diverge: fckDiverge,
    detalhe: fckDiverge ? `A nota traz fck ${r.fck_nota} MPa; o pedido era de ${r.pedido_fck} MPa.` : null,
  });

  const volumeDiverge = excesso > 0.004;
  itens.push({
    campo: 'volume', rotulo: 'Volume',
    pedido: `saldo de ${fmt(saldo)} m³ (pedido de ${fmt(r.pedido_volume)} m³)`,
    nota: `${fmt(volume)} m³`, diverge: volumeDiverge,
    detalhe: volumeDiverge
      ? `O caminhão traz ${fmt(volume)} m³ e o saldo do pedido era ${fmt(saldo)} m³: passa em ${fmt(excesso)} m³.`
      : null,
  });

  const centralDiverge = r.central_id !== r.pedido_central_id;
  itens.push({
    campo: 'central', rotulo: 'Central',
    pedido: r.pedido_central_nome, nota: r.central_nome, diverge: centralDiverge,
    detalhe: centralDiverge ? `A nota é da ${r.central_nome}; o pedido era da ${r.pedido_central_nome}.` : null,
  });

  const destino = rotuloPeca(r.destino_tipo, r.destino_identificacao);
  itens.push({
    campo: 'destino', rotulo: 'Peça de destino',
    pedido: destino,
    nota: r.destino_no_lote ? `lote ${r.lote_numero} abrange a peça` : `lote ${r.lote_numero} não abrange a peça`,
    diverge: !r.destino_no_lote,
    detalhe: r.destino_no_lote ? null : `A peça de destino do pedido (${destino}) não faz parte do lote ${r.lote_numero}.`,
  });

  return itens;
}

function formatar(r) {
  const conferencia = conferir(r);
  const situacao = situacaoPrazo(r);
  const qtd = conferencia.filter((i) => i.diverge).length;
  return {
    id: r.id,
    numero_nota: r.numero_nota,
    placa: r.placa,
    volume: Number(r.volume),
    traco: r.traco,
    consumo_cimento: r.consumo_cimento === null ? null : Number(r.consumo_cimento),
    aditivos: r.aditivos,
    aditivo_retardador: r.aditivo_retardador,
    classe_nota: r.classe_nota,
    fck_nota: r.fck_nota,
    primeiro_contato_em: r.primeiro_contato_em,
    chegada_obra_em: r.chegada_obra_em,
    registrado_em: r.registrado_em,
    central_id: r.central_id,
    central_nome: r.central_nome,
    lote_id: r.lote_id,
    lote_numero: r.lote_numero,
    pedido_id: r.pedido_id,
    pedido_numero: r.pedido_numero,
    construtora_id: r.construtora_id,
    // Prazo de descarga: limite a partir do primeiro contato; a hora de fim
    // da descarga (registrada pelo técnico) fecha a conta e decide a situação.
    prazo_minutos: r.prazo_minutos,
    aviso_minutos: r.aviso_minutos,
    limite_em: r.limite_em,
    restante_segundos: r.descarga_fim_em ? null : Number(r.restante_segundos),
    descarga_inicio_em: r.descarga_inicio_em,
    descarga_fim_em: r.descarga_fim_em,
    volume_efetivo: r.volume_efetivo != null ? Number(r.volume_efetivo) : null,
    recusado: !!r.recusado,
    situacao_prazo: situacao,
    fora_do_prazo: estaForaDoPrazo(situacao),
    excedeu_minutos: Number(r.excedeu_minutos),
    agora_servidor: r.agora_servidor,
    conferencia,
    qtd_divergencias: qtd,
    confere: qtd === 0,
  };
}

const SELECT_CAMINHOES = `
  SELECT c.id, c.numero_nota, c.placa, c.volume, c.traco, c.consumo_cimento, c.aditivos,
         c.aditivo_retardador, c.classe_nota, c.fck_nota, c.primeiro_contato_em,
         c.chegada_obra_em, c.criado_em AS registrado_em,
         c.prazo_minutos, c.descarga_inicio_em, c.descarga_fim_em, c.volume_efetivo,
         c.fora_do_prazo, c.recusado, cf.aviso_minutos,
         ${sqlLimite('c')} AS limite_em,
         ${sqlRestanteSegundos('c')} AS restante_segundos,
         ${sqlExcedeuMinutos('c')} AS excedeu_minutos,
         now() AS agora_servidor,
         c.central_id, ce.nome AS central_nome,
         c.lote_id, l.numero AS lote_numero, l.construtora_id,
         c.pedido_id, p.numero AS pedido_numero, p.volume AS pedido_volume,
         p.central_id AS pedido_central_id, pce.nome AS pedido_central_nome,
         cl.nome AS pedido_classe_nome, cl.fck AS pedido_fck,
         pc.tipo AS destino_tipo, pc.identificacao AS destino_identificacao,
         p.volume - COALESCE((SELECT SUM(COALESCE(c2.volume_efetivo, c2.volume)) FROM caminhoes c2
                               WHERE c2.pedido_id = c.pedido_id AND c2.id < c.id), 0) AS saldo_antes,
         EXISTS (SELECT 1 FROM lote_pecas lp
                  WHERE lp.lote_id = c.lote_id AND lp.peca_id = p.peca_id) AS destino_no_lote
    FROM caminhoes c
    JOIN centrais ce ON ce.id = c.central_id
    JOIN lotes l ON l.id = c.lote_id
    LEFT JOIN configuracoes_prazo cf ON cf.construtora_id = l.construtora_id
    JOIN pedidos p ON p.id = c.pedido_id
    JOIN centrais pce ON pce.id = p.central_id
    JOIN classes_concreto cl ON cl.id = p.classe_id
    JOIN pecas pc ON pc.id = p.peca_id
   WHERE c.numero_nota IS NOT NULL
`;

// ---------------------------------------------------------------------
// Listagem e opções
// ---------------------------------------------------------------------

// Os caminhões com nota registrada, os que chegaram por último primeiro.
// Filtros: ?lote_id= e ?pedido_id=. Caminhões do desenho antigo (sem
// nota) ficam fora.
router.get('/', permitir('obra', 'construtora'), rota(async (req, res) => {
  const params = [req.usuario.construtoraId];
  let filtro = ' AND l.construtora_id = $1';
  for (const [chave, coluna] of [['lote_id', 'c.lote_id'], ['pedido_id', 'c.pedido_id']]) {
    if (req.query[chave] !== undefined) {
      if (!idValido(req.query[chave])) {
        return res.status(400).json({ erro: `Identificador inválido em ${chave}.` });
      }
      params.push(Number(req.query[chave]));
      filtro += ` AND ${coluna} = $${params.length}`;
    }
  }
  const { rows } = await pool.query(
    `${SELECT_CAMINHOES}${filtro} ORDER BY c.chegada_obra_em DESC, c.id DESC LIMIT 100`,
    params
  );
  res.json(rows.map(formatar));
}));

// O que o formulário de registro precisa: lotes em andamento, pedidos
// abertos (com o que já foi entregue) e as centrais ativas.
router.get('/opcoes', permitir('obra'), rota(async (req, res) => {
  const c = req.usuario.construtoraId;

  const lotes = await pool.query(
    `SELECT l.id, l.numero, l.obra_id, o.nome AS obra_nome, l.fck_projeto,
            to_char(l.data_concretagem, 'YYYY-MM-DD') AS data_concretagem
       FROM lotes l JOIN obras o ON o.id = l.obra_id
      WHERE l.construtora_id = $1 AND l.status = 'em_andamento'
      ORDER BY l.data_concretagem DESC, l.id DESC`,
    [c]
  );
  const pedidos = await pool.query(
    `SELECT p.id, p.numero, o.id AS obra_id, o.nome AS obra_nome,
            p.central_id, ce.nome AS central_nome,
            cl.nome AS classe_nome, cl.fck, p.volume,
            COALESCE((SELECT SUM(COALESCE(ca.volume_efetivo, ca.volume)) FROM caminhoes ca WHERE ca.pedido_id = p.id), 0) AS volume_entregue,
            pc.tipo AS peca_tipo, pc.identificacao AS peca_identificacao
       FROM pedidos p
       JOIN centrais ce ON ce.id = p.central_id
       JOIN classes_concreto cl ON cl.id = p.classe_id
       JOIN pecas pc ON pc.id = p.peca_id
       JOIN pavimentos pv ON pv.id = pc.pavimento_id
       JOIN obras o ON o.id = pv.obra_id
      WHERE p.construtora_id = $1 AND p.status = 'aberto'
      ORDER BY o.nome, p.numero`,
    [c]
  );
  const centrais = await pool.query(
    'SELECT id, nome FROM centrais WHERE construtora_id = $1 AND ativo ORDER BY nome',
    [c]
  );

  res.json({
    lotes: lotes.rows,
    pedidos: pedidos.rows.map((p) => ({ ...p, volume: Number(p.volume), volume_entregue: Number(p.volume_entregue) })),
    centrais: centrais.rows,
  });
}));

router.get('/:id', permitir('obra', 'construtora'), rota(async (req, res) => {
  const { id } = req.params;
  if (!idValido(id)) return res.status(400).json({ erro: 'Identificador de caminhão inválido.' });

  const { rows } = await pool.query(`${SELECT_CAMINHOES} AND c.id = $1`, [Number(id)]);
  if (!rows[0]) return res.status(404).json({ erro: 'Caminhão não encontrado.' });
  if (rows[0].construtora_id !== req.usuario.construtoraId) {
    return res.status(403).json({ erro: 'Acesso negado: este caminhão pertence a outra construtora.' });
  }
  res.json(formatar(rows[0]));
}));

// ---------------------------------------------------------------------
// Prazo de descarga
// ---------------------------------------------------------------------

// Encerra a descarga do caminhão. O técnico registra a hora de início e a
// hora de fim (horas de verdade, com fuso) e o volume efetivamente
// descarregado. A hora de fim fecha a conta do prazo (T08) e grava se
// ficou dentro ou fora. Depois de encerrado, as horas não mudam mais:
// qualquer tentativa de alterar é recusada na API (409).
router.post('/:id/encerrar-descarga', permitir('obra'), rota(async (req, res) => {
  const { id } = req.params;
  if (!idValido(id)) return res.status(400).json({ erro: 'Identificador de caminhão inválido.' });

  const corpo = req.body || {};
  const inicio = instante(corpo.descarga_inicio_em);
  const fim = instante(corpo.descarga_fim_em);
  const volumeEfetivo = numero(corpo.volume_efetivo);

  const faltando = [];
  if (!inicio) faltando.push('hora de início da descarga (formato ISO, com fuso)');
  if (!fim) faltando.push('hora de fim da descarga (formato ISO, com fuso)');
  if (volumeEfetivo === null) faltando.push('volume efetivamente descarregado');
  if (faltando.length) {
    return res.status(400).json({ erro: `Preencha: ${faltando.join(', ')}.` });
  }
  if (volumeEfetivo <= 0 || volumeEfetivo > VOLUME_MAXIMO) {
    return res.status(400).json({ erro: `Volume efetivo deve ser maior que zero e no máximo ${VOLUME_MAXIMO} m³.` });
  }
  if (fim.getTime() < inicio.getTime()) {
    return res.status(400).json({ erro: 'Hora de fim anterior à de início é recusada.' });
  }

  const { rows: [atual] } = await pool.query(
    `SELECT c.id, c.numero_nota, c.descarga_fim_em, c.volume, c.primeiro_contato_em,
            c.prazo_minutos, l.construtora_id
       FROM caminhoes c JOIN lotes l ON l.id = c.lote_id
      WHERE c.id = $1 AND c.numero_nota IS NOT NULL`,
    [Number(id)]
  );
  if (!atual) return res.status(404).json({ erro: 'Caminhão não encontrado.' });
  if (atual.construtora_id !== req.usuario.construtoraId) {
    return res.status(403).json({ erro: 'Acesso negado: este caminhão pertence a outra construtora.' });
  }
  if (atual.descarga_fim_em) {
    return res.status(409).json({
      erro: `A descarga do caminhão da nota ${atual.numero_nota} já foi encerrada e não aceita alteração das horas.`,
    });
  }

  // Fora do prazo se a hora de fim ultrapassa o limite (primeiro contato + prazo).
  const limite = new Date(atual.primeiro_contato_em.getTime() + Number(atual.prazo_minutos) * 60 * 1000);
  const fora = fim.getTime() > limite.getTime();

  const { rows: [feito] } = await pool.query(
    `UPDATE caminhoes
        SET descarga_inicio_em = $2,
            descarga_fim_em = $3,
            volume_efetivo = $4,
            fora_do_prazo = $5
      WHERE id = $1 AND descarga_fim_em IS NULL
  RETURNING id`,
    [atual.id, inicio.toISOString(), fim.toISOString(), volumeEfetivo, fora]
  );
  if (!feito) {
    return res.status(409).json({
      erro: `A descarga do caminhão da nota ${atual.numero_nota} já foi encerrada e não aceita alteração das horas.`,
    });
  }

  const { rows: [salvo] } = await pool.query(`${SELECT_CAMINHOES} AND c.id = $1`, [atual.id]);
  const payload = formatar(salvo);
  if (typeof clientId !== 'undefined' && clientId) {
    await gravarOperacao(pool, {
      clientId,
      construtoraId: req.usuario.construtoraId,
      usuarioId: req.usuario.id,
      tipo: 'encerrar_descarga',
      resourceTipo: 'caminhao',
      resourceId: salvo.id,
      statusHttp: 200,
      resposta: payload,
    });
  }
  res.json(payload);
}));

// Relatório do prazo de descarga: o resumo de todos os caminhões e a lista
// dos que ficaram fora do prazo (descarga encerrada depois do prazo, ou
// ainda aberta com o prazo já estourado), os que mais passaram primeiro.
// Filtros: ?lote_id= e ?obra_id=.
router.get('/relatorio/prazo', permitir('obra', 'construtora'), rota(async (req, res) => {
  const params = [req.usuario.construtoraId];
  let filtro = ' AND l.construtora_id = $1';
  for (const [chave, coluna] of [['lote_id', 'c.lote_id'], ['obra_id', 'l.obra_id']]) {
    if (req.query[chave] !== undefined) {
      if (!idValido(req.query[chave])) return res.status(400).json({ erro: `Identificador inválido em ${chave}.` });
      params.push(Number(req.query[chave]));
      filtro += ` AND ${coluna} = $${params.length}`;
    }
  }
  const { rows } = await pool.query(`${SELECT_CAMINHOES}${filtro} ORDER BY c.chegada_obra_em DESC, c.id DESC LIMIT 1000`, params);
  const itens = rows.map(formatar);

  const contagem = { no_prazo: 0, atencao: 0, estourado: 0, encerrada_no_prazo: 0, encerrada_fora_do_prazo: 0 };
  for (const i of itens) if (contagem[i.situacao_prazo] !== undefined) contagem[i.situacao_prazo] += 1;
  const fora = itens.filter((i) => i.fora_do_prazo).sort((a, b) => b.excedeu_minutos - a.excedeu_minutos);

  res.json({ resumo: { total: itens.length, ...contagem, fora_do_prazo: fora.length }, caminhoes: fora });
}));

// ---------------------------------------------------------------------
// Registro do caminhão
// ---------------------------------------------------------------------

router.post('/', permitir('obra'), rota(async (req, res) => {
  // Idempotência: client_id do aparelho evita duplicar caminhão ao reenviar a fila.
  const clientId = normalizarClientId(req.body, req.headers);
  if (clientId) {
    const op = await buscarOperacao(pool, clientId, req.usuario.construtoraId);
    if (op) return res.status(op.status_http).json(op.resposta);
  }

  const construtoraId = req.usuario.construtoraId;
  const corpo = req.body || {};

  const loteId = numero(corpo.lote_id);
  const pedidoId = numero(corpo.pedido_id);
  const centralId = numero(corpo.central_id);
  const numeroNota = texto(corpo.numero_nota);
  const placa = placaValida(corpo.placa);
  const volumeBruto = numero(corpo.volume);
  const traco = texto(corpo.traco);
  const classeNota = texto(corpo.classe_nota);
  const fckNota = numero(corpo.fck_nota);
  const contato = instante(corpo.primeiro_contato_em);

  // O que falta (ou veio num formato que não serve).
  const faltando = [];
  if (loteId === null || !Number.isInteger(loteId)) faltando.push('lote');
  if (pedidoId === null || !Number.isInteger(pedidoId)) faltando.push('pedido');
  if (centralId === null || !Number.isInteger(centralId)) faltando.push('central');
  if (!numeroNota) faltando.push('número da nota');
  if (typeof corpo.placa !== 'string' || corpo.placa.trim() === '') faltando.push('placa');
  if (volumeBruto === null) faltando.push('volume');
  if (!traco) faltando.push('traço');
  if (!classeNota) faltando.push('classe da nota');
  if (fckNota === null) faltando.push('fck da nota');
  if (!contato) faltando.push('data e hora do primeiro contato do cimento com a água (formato ISO, com fuso)');
  if (faltando.length) {
    return res.status(400).json({ erro: `Preencha: ${faltando.join(', ')}.` });
  }

  if (numeroNota.length > 40) return res.status(400).json({ erro: 'O número da nota aceita no máximo 40 caracteres.' });
  if (traco.length > 200) return res.status(400).json({ erro: 'O traço aceita no máximo 200 caracteres.' });
  if (classeNota.length > 30) return res.status(400).json({ erro: 'A classe da nota aceita no máximo 30 caracteres.' });
  if (!placa) return res.status(400).json({ erro: 'Placa inválida. Use o formato ABC-1234 ou ABC-1D23.' });

  const volume = Math.round(volumeBruto * 100) / 100;
  if (volume <= 0) return res.status(400).json({ erro: 'O volume do caminhão precisa ser maior que zero (em m³).' });
  if (volume > VOLUME_MAXIMO) {
    return res.status(400).json({ erro: `O volume do caminhão não pode passar de ${VOLUME_MAXIMO} m³ (o que cabe numa betoneira).` });
  }

  if (!Number.isInteger(fckNota) || fckNota <= 0 || fckNota > FCK_MAXIMO) {
    return res.status(400).json({ erro: `O fck da nota precisa ser um número inteiro maior que zero, em MPa (até ${FCK_MAXIMO}).` });
  }

  let consumo = null;
  if (!vazio(corpo.consumo_cimento)) {
    const c = numero(corpo.consumo_cimento);
    if (c === null || c <= 0 || c > CONSUMO_MAXIMO) {
      return res.status(400).json({ erro: `O consumo de cimento precisa ser maior que zero, em kg/m³ (até ${CONSUMO_MAXIMO}).` });
    }
    consumo = Math.round(c * 100) / 100;
  }

  const aditivos = texto(corpo.aditivos) || null;
  if (aditivos && aditivos.length > 200) return res.status(400).json({ erro: 'Os aditivos aceitam no máximo 200 caracteres.' });

  let retardador = false;
  if (corpo.aditivo_retardador !== undefined && corpo.aditivo_retardador !== null) {
    if (typeof corpo.aditivo_retardador !== 'boolean') {
      return res.status(400).json({ erro: 'Informe "aditivo_retardador" como true ou false.' });
    }
    retardador = corpo.aditivo_retardador;
  }

  // Os dois horários são coisas diferentes: o primeiro contato do cimento
  // com a água (na central) e a chegada à obra. Sem a chegada, vale o
  // momento do registro.
  const agora = new Date();
  const tolerancia = 5 * 60 * 1000; // 5 min de folga para relógios desencontrados
  let chegada = agora;
  if (!vazio(corpo.chegada_obra_em)) {
    chegada = instante(corpo.chegada_obra_em);
    if (!chegada) {
      return res.status(400).json({ erro: 'Hora de chegada à obra inválida (formato ISO, com fuso).' });
    }
  }
  if (contato.getTime() > agora.getTime() + tolerancia) {
    return res.status(400).json({ erro: 'O primeiro contato do cimento com a água não pode estar no futuro.' });
  }
  if (chegada.getTime() > agora.getTime() + tolerancia) {
    return res.status(400).json({ erro: 'A chegada à obra não pode estar no futuro.' });
  }
  if (chegada.getTime() < contato.getTime()) {
    return res.status(400).json({
      erro: 'A chegada à obra não pode ser antes do primeiro contato do cimento com a água: a mistura começa na central, antes de o caminhão chegar.',
    });
  }

  // Central, lote e pedido: existem, são desta construtora e estão em condição de receber.
  const { rows: [central] } = await pool.query('SELECT id, construtora_id, nome FROM centrais WHERE id = $1', [centralId]);
  if (!central) return res.status(400).json({ erro: 'Central não encontrada.' });
  if (central.construtora_id !== construtoraId) {
    return res.status(403).json({ erro: 'Acesso negado: esta central pertence a outra construtora.' });
  }

  const { rows: [lote] } = await pool.query(
    'SELECT id, construtora_id, numero, status, obra_id FROM lotes WHERE id = $1', [loteId]
  );
  if (!lote) return res.status(400).json({ erro: 'Lote não encontrado.' });
  if (lote.construtora_id !== construtoraId) {
    return res.status(403).json({ erro: 'Acesso negado: este lote pertence a outra construtora.' });
  }

  const { rows: [pedido] } = await pool.query(
    `SELECT p.id, p.numero, p.status, p.construtora_id, o.id AS obra_id
       FROM pedidos p
       JOIN pecas pc ON pc.id = p.peca_id
       JOIN pavimentos pv ON pv.id = pc.pavimento_id
       JOIN obras o ON o.id = pv.obra_id
      WHERE p.id = $1`,
    [pedidoId]
  );
  if (!pedido) return res.status(400).json({ erro: 'Pedido não encontrado.' });
  if (pedido.construtora_id !== construtoraId) {
    return res.status(403).json({ erro: 'Acesso negado: este pedido pertence a outra construtora.' });
  }

  if (lote.status !== 'em_andamento') {
    return res.status(409).json({
      erro: lote.status === 'encerrado'
        ? `O lote ${lote.numero} está encerrado e não recebe caminhão novo.`
        : `O lote ${lote.numero} não está em andamento e não recebe caminhão.`,
    });
  }
  if (pedido.status !== 'aberto') {
    return res.status(409).json({ erro: `O pedido ${pedido.numero} está cancelado e não recebe caminhão.` });
  }
  if (lote.obra_id === null || lote.obra_id !== pedido.obra_id) {
    return res.status(400).json({ erro: `O lote ${lote.numero} e o pedido ${pedido.numero} são de obras diferentes.` });
  }

  // Número de nota não se repete para a mesma central.
  const { rows: repetidos } = await pool.query(
    `SELECT c.placa FROM caminhoes c
      WHERE c.central_id = $1 AND lower(c.numero_nota) = lower($2)`,
    [centralId, numeroNota]
  );
  if (repetidos[0]) {
    return res.status(409).json({
      erro: `A nota ${numeroNota} da ${central.nome} já foi registrada (caminhão ${repetidos[0].placa}). Número de nota não se repete para a mesma central.`,
    });
  }

  const registradoPor = Number.isInteger(req.usuario.sub) ? req.usuario.sub : null;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    // Um caminhão por vez por pedido: a comparação com o saldo do pedido
    // depende da ordem de chegada.
    await client.query('SELECT pg_advisory_xact_lock(1007, $1)', [pedido.id]);
    // O prazo de descarga vem da configuração (maior se a nota traz aditivo
    // retardador) e fica gravado no caminhão: mudar a configuração depois
    // não muda o prazo de quem já chegou.
    const prazo = prazoDoCaminhao(await lerConfig(client, construtoraId), retardador);
    const { rows: [novo] } = await client.query(
      `INSERT INTO caminhoes
         (central_id, lote_id, pedido_id, numero_nota, placa, volume, traco, consumo_cimento,
          aditivos, aditivo_retardador, classe_nota, fck_nota,
          primeiro_contato_em, chegada_obra_em, registrado_por, prazo_minutos)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
       RETURNING id`,
      [centralId, lote.id, pedido.id, numeroNota, placa, volume, traco, consumo,
       aditivos, retardador, classeNota, fckNota,
       contato.toISOString(), chegada.toISOString(), registradoPor, prazo]
    );
    await client.query('COMMIT');

    const { rows: [salvo] } = await pool.query(`${SELECT_CAMINHOES} AND c.id = $1`, [novo.id]);
    const payload = formatar(salvo);
    if (clientId) {
      await gravarOperacao(pool, {
        clientId,
        construtoraId: req.usuario.construtoraId,
        usuarioId: req.usuario.id,
        tipo: 'registrar_caminhao',
        resourceTipo: 'caminhao',
        resourceId: salvo.id,
        statusHttp: 201,
        resposta: payload,
      });
    }
    res.status(201).json(payload);
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    // 23505: o banco barrou uma nota repetida que a checagem acima não pegou (corrida).
    if (err.code === '23505') {
      return res.status(409).json({
        erro: `A nota ${numeroNota} da ${central.nome} já foi registrada. Número de nota não se repete para a mesma central.`,
      });
    }
    // 23514: gatilhos do banco (lote encerrado ou pedido cancelado entre a checagem e o registro).
    if (err.code === '23514' && /encerrado/.test(err.message)) {
      return res.status(409).json({ erro: `O lote ${lote.numero} está encerrado e não recebe caminhão novo.` });
    }
    if (err.code === '23514' && /cancelado/.test(err.message)) {
      return res.status(409).json({ erro: `O pedido ${pedido.numero} está cancelado e não recebe caminhão.` });
    }
    throw err;
  } finally {
    client.release();
  }
}));

module.exports = router;
