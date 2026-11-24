// Dados de teste da T07. Rode depois dos seeds anteriores (principal, obras,
// cadastros, classes, pedidos e lotes):
//   node sql/seed_caminhoes.js
// Pode rodar de novo sem duplicar: se já existe caminhão "DEMO-..." não faz nada.
//
// Cria dois pedidos novos (para não gastar os pedidos 2 e 3 do seed da T05,
// que servem para testar o cancelamento) e registra um caminhão em cada:
//   Nota DEMO-0001 — confere com o pedido (nenhuma divergência).
//   Nota DEMO-0002 — classe C20 e fck 20 contra um pedido de C25, e 7 m³ contra
//                    um saldo de 5 m³: três divergências (classe, fck e volume).
// Os dois entram no primeiro lote em andamento da construtora de teste.
require('dotenv').config();
const pool = require('../src/db');

async function main() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const cons = await client.query(`SELECT id FROM construtoras WHERE nome = $1`, ['Construtora Bom Conselho']);
    const A = cons.rows[0];
    if (!A) throw new Error('Rode antes o seed principal (npm run seed): a construtora de teste não existe.');

    const ja = await client.query(`SELECT 1 FROM caminhoes WHERE numero_nota LIKE 'DEMO-%' LIMIT 1`);
    if (ja.rows[0]) {
      await client.query('ROLLBACK');
      console.log('Os caminhões de teste (DEMO-...) já existem; nada a fazer.');
      return;
    }

    const lote = (await client.query(
      `SELECT l.id, l.obra_id FROM lotes l
        WHERE l.construtora_id = $1 AND l.status = 'em_andamento' AND l.obra_id IS NOT NULL
        ORDER BY l.data_concretagem, l.id LIMIT 1`, [A.id]
    )).rows[0];
    if (!lote) throw new Error('Nenhum lote em andamento. Rode antes: node sql/seed_lotes.js');

    // Uma peça do lote, para o destino do pedido bater com o lote.
    const peca = (await client.query(
      `SELECT peca_id FROM lote_pecas WHERE lote_id = $1 ORDER BY peca_id LIMIT 1`, [lote.id]
    )).rows[0];
    if (!peca) throw new Error('O lote em andamento não tem peças.');

    const central = (await client.query(
      `SELECT id FROM centrais WHERE construtora_id = $1 AND ativo ORDER BY id LIMIT 1`, [A.id]
    )).rows[0];
    if (!central) throw new Error('Nenhuma central ativa. Rode antes: node sql/seed_cadastros.js');

    const classe = (await client.query(
      `SELECT id, nome, fck FROM classes_concreto WHERE construtora_id = $1 ORDER BY fck, id LIMIT 1`, [A.id]
    )).rows[0];
    if (!classe) throw new Error('Nenhuma classe cadastrada. Rode antes o seed principal.');

    const tecnico = (await client.query(`SELECT id FROM usuarios WHERE username = 'tecnico'`)).rows[0];
    const registradoPor = tecnico ? tecnico.id : null;

    // A nota registrada guarda o prazo de descarga que valia na chegada
    // (T08); a configuração da construtora é criada com os valores padrão.
    await client.query(
      'INSERT INTO configuracoes_prazo (construtora_id) VALUES ($1) ON CONFLICT (construtora_id) DO NOTHING', [A.id]
    );

    await client.query('SELECT pg_advisory_xact_lock(1005, $1)', [A.id]);
    const { rows: [{ proximo }] } = await client.query(
      'SELECT COALESCE(MAX(numero), 0) + 1 AS proximo FROM pedidos WHERE construtora_id = $1', [A.id]
    );

    const novoPedido = async (numero, volume) => (await client.query(
      `INSERT INTO pedidos (construtora_id, numero, central_id, classe_id, peca_id, volume, prevista_para)
       VALUES ($1, $2, $3, $4, $5, $6, now()) RETURNING id`,
      [A.id, numero, central.id, classe.id, peca.peca_id, volume]
    )).rows[0].id;

    const p1 = await novoPedido(proximo, 6);
    const p2 = await novoPedido(proximo + 1, 5);

    const novoCaminhao = (pedidoId, nota, placa, volume, classeNota, fckNota, contato, chegada) => client.query(
      `INSERT INTO caminhoes
         (central_id, lote_id, pedido_id, numero_nota, placa, volume, traco, consumo_cimento,
          aditivos, aditivo_retardador, classe_nota, fck_nota, primeiro_contato_em, chegada_obra_em, registrado_por,
          prazo_minutos)
       VALUES ($1, $2, $3, $4, $5, $6, '1 : 2,1 : 2,8 : 0,45', 320, 'plastificante', false,
               $7, $8, now() - $9::interval, now() - $10::interval, $11,
               (SELECT prazo_descarga_minutos FROM configuracoes_prazo WHERE construtora_id = $12))`,
      [central.id, lote.id, pedidoId, nota, placa, volume, classeNota, fckNota, contato, chegada, registradoPor, A.id]
    );

    // Confere: mesma classe e mesmo fck do pedido, e o volume cabe no saldo.
    await novoCaminhao(p1, 'DEMO-0001', 'DEM-1A01', 6, classe.nome, classe.fck, '3 hours', '2 hours 30 minutes');
    // Diverge: C20/fck 20 contra o pedido, e 7 m³ contra um saldo de 5 m³.
    await novoCaminhao(p2, 'DEMO-0002', 'DEM-1A02', 7, 'C20', 20, '2 hours', '1 hour 40 minutes');

    await client.query('COMMIT');
    console.log(`Seed de caminhões concluído: pedidos ${proximo} e ${proximo + 1}, com as notas DEMO-0001 (confere) e DEMO-0002 (3 divergências).`);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Seed de caminhões falhou, nada foi gravado:', err.message);
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
}

main();
