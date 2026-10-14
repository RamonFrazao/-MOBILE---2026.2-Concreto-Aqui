// Dados de teste da T04. Rode depois do schema e do seed principal:
//   node sql/seed_classes.js
// Pode rodar de novo sem duplicar.
//
// Resultado, na construtora de teste:
//   C25 — a do seed principal, que já tem pedidos (lotes): não pode ser excluída.
//   C30 — nova, com aditivo retardador e plastificante, sem pedido: pode ser excluída.
require('dotenv').config();
const pool = require('../src/db');

async function main() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const cons = await client.query(
      `SELECT id FROM construtoras WHERE nome = $1`,
      ['Construtora Bom Conselho']
    );
    const A = cons.rows[0];
    if (!A) {
      throw new Error('Rode antes o seed principal (npm run seed): a construtora de teste não existe.');
    }

    const ja = await client.query(
      `SELECT id FROM classes_concreto WHERE construtora_id = $1 AND lower(nome) = 'c30'`,
      [A.id]
    );
    if (ja.rows[0]) {
      await client.query('ROLLBACK');
      console.log('A classe C30 de teste já existe; nada a fazer.');
      return;
    }

    await client.query(
      `INSERT INTO classes_concreto
         (construtora_id, nome, fck, abatimento_alvo, abatimento_tolerancia,
          agregado_mm, aditivo_retardador, aditivos_outros)
       VALUES ($1, 'C30', 30, 90, 20, 19, true, 'plastificante')`,
      [A.id]
    );

    await client.query('COMMIT');
    console.log('Seed de classes concluído: C30 (retardador + plastificante, sem pedido) criada.');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Seed de classes falhou, nada foi gravado:', err.message);
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
}

main();
