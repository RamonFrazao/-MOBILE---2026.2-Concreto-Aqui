const router = require('express').Router();
const pool = require('../db');
const { autenticar } = require('../middleware/auth');
const { exigirPerfil } = require('../middleware/perfil');

// Cadastro de classe é só da construtora. A tolerância do abatimento
// mora aqui, em dado, porque é ela que a chegada do caminhão vai usar
// para decidir se ele entra ou volta — nunca um número escrito no código.
router.use(autenticar, exigirPerfil('construtora'));

const MAX_TEXTO = 200;
const texto = (v) => (typeof v === 'string' ? v.trim() : '');
const idValido = (v) => /^\d{1,9}$/.test(String(v));

// Converte o valor recebido em número, ou devolve null se não for um
// número de verdade (vazio, texto, booleano, lista...).
function numero(v) {
  if (typeof v === 'number') return Number.isFinite(v) ? v : null;
  if (typeof v === 'string' && v.trim() !== '') {
    const n = Number(v);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

const rota = (fn) => async (req, res) => {
  try {
    await fn(req, res);
  } catch (err) {
    console.error(err);
    if (!res.headersSent) res.status(500).json({ erro: 'Erro interno.' });
  }
};

const COLUNAS = `c.id, c.nome, c.fck, c.abatimento_alvo, c.abatimento_tolerancia,
                 c.agregado_mm, c.aditivo_retardador, c.aditivos_outros`;

// O Postgres devolve NUMERIC como texto; aqui vira número de novo.
function formatar(linha) {
  return { ...linha, agregado_mm: Number(linha.agregado_mm) };
}

// Lista as classes da construtora logada, cada uma com quantos pedidos
// (lotes) já usam essa classe.
router.get('/', rota(async (req, res) => {
  const { rows } = await pool.query(
    `SELECT ${COLUNAS},
            ((SELECT COUNT(*) FROM pedidos pe WHERE pe.classe_id = c.id)
             + (SELECT COUNT(*) FROM lotes l WHERE l.classe_id = c.id))::int AS qtd_pedidos
       FROM classes_concreto c
      WHERE c.construtora_id = $1
      ORDER BY c.fck, c.nome`,
    [req.usuario.construtoraId]
  );
  res.json(rows.map(formatar));
}));

router.post('/', rota(async (req, res) => {
  const corpo = req.body || {};
  const nome = texto(corpo.nome);
  const fck = numero(corpo.fck);
  const alvo = numero(corpo.abatimento_alvo);
  const tolerancia = numero(corpo.abatimento_tolerancia);
  const agregado = numero(corpo.agregado_mm);

  const faltando = [];
  if (!nome) faltando.push('nome da classe');
  if (fck === null) faltando.push('fck');
  if (alvo === null) faltando.push('abatimento');
  if (tolerancia === null) faltando.push('tolerância');
  if (agregado === null) faltando.push('dimensão do agregado');
  if (faltando.length) {
    return res.status(400).json({
      erro: `Preencha, com números válidos onde for o caso: ${faltando.join(', ')}.`,
    });
  }

  if (nome.length > MAX_TEXTO) {
    return res.status(400).json({ erro: `O nome da classe aceita no máximo ${MAX_TEXTO} caracteres.` });
  }
  if (!Number.isInteger(fck) || fck <= 0) {
    return res.status(400).json({ erro: 'O fck precisa ser um número inteiro maior que zero (em MPa).' });
  }
  if (!Number.isInteger(alvo) || alvo <= 0) {
    return res.status(400).json({ erro: 'O abatimento precisa ser um número inteiro maior que zero (em mm).' });
  }
  if (tolerancia < 0) {
    return res.status(400).json({ erro: 'A tolerância não aceita valor negativo.' });
  }
  if (!Number.isInteger(tolerancia)) {
    return res.status(400).json({ erro: 'A tolerância precisa ser um número inteiro (em mm).' });
  }
  if (agregado <= 0) {
    return res.status(400).json({ erro: 'A dimensão do agregado precisa ser maior que zero (em mm).' });
  }

  // Aditivo retardador: se vier, tem que ser verdadeiro ou falso.
  let retardador = false;
  if (corpo.aditivo_retardador !== undefined && corpo.aditivo_retardador !== null) {
    if (typeof corpo.aditivo_retardador !== 'boolean') {
      return res.status(400).json({ erro: 'Informe "aditivo_retardador" como true ou false.' });
    }
    retardador = corpo.aditivo_retardador;
  }

  const outros = texto(corpo.aditivos_outros) || null;
  if (outros && outros.length > MAX_TEXTO) {
    return res.status(400).json({ erro: `Os outros aditivos aceitam no máximo ${MAX_TEXTO} caracteres.` });
  }

  try {
    const { rows } = await pool.query(
      `INSERT INTO classes_concreto
         (construtora_id, nome, fck, abatimento_alvo, abatimento_tolerancia,
          agregado_mm, aditivo_retardador, aditivos_outros)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       RETURNING id, nome, fck, abatimento_alvo, abatimento_tolerancia,
                 agregado_mm, aditivo_retardador, aditivos_outros`,
      [req.usuario.construtoraId, nome, fck, alvo, tolerancia, agregado, retardador, outros]
    );
    res.status(201).json({ ...formatar(rows[0]), qtd_pedidos: 0 });
  } catch (err) {
    if (err.code === '23505') {
      return res.status(409).json({ erro: `Já existe uma classe chamada "${nome}".` });
    }
    // 23514 = violação de CHECK (a tolerância negativa, se de algum jeito
    // passasse pela validação acima, é barrada aqui pelo próprio banco).
    if (err.code === '23514') {
      return res.status(400).json({ erro: 'A tolerância não aceita valor negativo.' });
    }
    throw err;
  }
}));

async function classeDaConstrutora(req, res) {
  const { id } = req.params;
  if (!idValido(id)) {
    res.status(400).json({ erro: 'Identificador de classe inválido.' });
    return null;
  }
  const { rows } = await pool.query('SELECT id, nome, construtora_id FROM classes_concreto WHERE id = $1', [id]);
  const classe = rows[0];
  if (!classe) {
    res.status(404).json({ erro: 'Classe não encontrada.' });
    return null;
  }
  if (classe.construtora_id !== req.usuario.construtoraId) {
    res.status(403).json({ erro: 'Acesso negado: esta classe pertence a outra construtora.' });
    return null;
  }
  return classe;
}

// Exclui a classe — só se nenhum pedido (lote) usa ela. Apagar uma
// classe com pedido feito faria o pedido perder a especificação contra a
// qual o concreto vai ser conferido na chegada.
router.delete('/:id', rota(async (req, res) => {
  const classe = await classeDaConstrutora(req, res);
  if (!classe) return;

  // Pedido feito = pedido registrado (tabela pedidos) ou lote aberto
  // com esta classe (tabela lotes, do desenho anterior).
  const { rows } = await pool.query(
    `SELECT ((SELECT COUNT(*) FROM pedidos WHERE classe_id = $1)
           + (SELECT COUNT(*) FROM lotes WHERE classe_id = $1))::int AS qtd`,
    [classe.id]
  );
  if (rows[0].qtd > 0) {
    return res.status(409).json({
      erro: `Não é possível excluir: a classe ${classe.nome} já tem pedido feito (${rows[0].qtd}).`,
    });
  }

  try {
    await pool.query('DELETE FROM classes_concreto WHERE id = $1', [classe.id]);
  } catch (err) {
    // 23503 = violação de chave estrangeira: um pedido passou a usar esta
    // classe entre a checagem acima e o DELETE. O banco barra, e a
    // resposta continua sendo a mesma.
    if (err.code === '23503') {
      return res.status(409).json({
        erro: `Não é possível excluir: a classe ${classe.nome} já tem pedido feito.`,
      });
    }
    throw err;
  }
  res.status(204).end();
}));

module.exports = router;
