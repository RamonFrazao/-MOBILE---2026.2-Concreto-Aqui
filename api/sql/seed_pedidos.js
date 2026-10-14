// Dados de teste da T05. Rode depois dos seeds anteriores (principal,
// obras, cadastros e classes):
//   node sql/seed_pedidos.js
// Pode rodar de novo sem duplicar: se a construtora de teste já tem
// pedidos, não faz nada.
//
// Resultado, na construtora de teste:
//   Pedido 1 — 8 m³, já com 2 caminhões (4 m³ + 3,5 m³): mostra "mais de um
//              caminhão" e o volume já entregue (7,5 de 8). NÃO pode ser cancelado.
//   Pedido 2 — 6 m³, sem nenhum caminhão: pode ser cancelado.
//   Pedido 3 — 5 m³, sem nenhum caminhão: pode ser cancelado.
require('dotenv').config();
const pool = require('../src/db');

async function main() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const cons = await client.query(`SELECT id FROM construtoras WHERE nome = $1`, ['Construtora Bom Conselho']);
    const A = cons.rows[0];
    if (!A) throw new Error('Rode antes o seed principal (npm run seed): a construtora de teste não existe.');

    const ja = await client.query(`SELECT 1 FROM pedidos WHERE construtora_id = $1 LIMIT 1`, [A.id]);
    if (ja.rows[0]) {
      await client.query('ROLLBACK');
      console.log('Já existem pedidos para a construtora de teste; nada a fazer.');
      return;
    }

    const central = (await client.query(
      `SELECT id FROM centrais WHERE construtora_id = $1 AND ativo ORDER BY id LIMIT 1`, [A.id]
    )).rows[0];
    if (!central) throw new Error('Nenhuma central ativa. Rode antes: node sql/seed_cadastros.js');

    const classe = (await client.query(
      `SELECT id FROM classes_concreto WHERE construtora_id = $1 ORDER BY fck, id LIMIT 1`, [A.id]
    )).rows[0];
    if (!classe) throw new Error('Nenhuma classe cadastrada. Rode antes o seed principal.');

    const pecas = (await client.query(
      `SELECT pc.id
         FROM pecas pc
         JOIN pavimentos pv ON pv.id = pc.pavimento_id
         JOIN obras o ON o.id = pv.obra_id
        WHERE o.construtora_id = $1
        ORDER BY pc.id LIMIT 2`, [A.id]
    )).rows;
    if (pecas.length === 0) throw new Error('Nenhuma peça cadastrada. Rode antes: node sql/seed_obras.js');
    const peca1 = pecas[0].id;
    const peca2 = (pecas[1] || pecas[0]).id;

    const novo = async (numero, pecaId, volume, previsto) => (await client.query(
      `INSERT INTO pedidos (construtora_id, numero, central_id, classe_id, peca_id, volume, prevista_para)
       VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id`,
      [A.id, numero, central.id, classe.id, pecaId, volume, previsto]
    )).rows[0].id;

    const p1 = await novo(1, peca1, 8, '2026-10-20T11:00:00Z');
    await novo(2, peca2, 6, '2026-10-21T11:30:00Z');
    await novo(3, peca1, 5, '2026-10-22T12:00:00Z');

    await client.query(
      `INSERT INTO caminhoes (central_id, pedido_id, placa, volume) VALUES
       ($1, $2, 'RST-1A01', 4),
       ($1, $2, 'RST-1A02', 3.5)`,
      [central.id, p1]
    );

    await client.query('COMMIT');
    console.log('Seed de pedidos concluído: pedidos 1 (com 2 caminhões), 2 e 3 (sem caminhão).');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Seed de pedidos falhou, nada foi gravado:', err.message);
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
}

main();
