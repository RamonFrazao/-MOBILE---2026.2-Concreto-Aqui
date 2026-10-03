// Dados de teste da T03. Rode depois do schema e dos seeds anteriores:
//   node sql/seed_cadastros.js
// Pode rodar de novo sem duplicar: se a central de teste já existe, não
// faz nada.
require('dotenv').config();
const bcrypt = require('bcrypt');
const pool = require('../src/db');

async function main() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const cons = await client.query(
      `SELECT id, nome FROM construtoras WHERE nome = $1`,
      ['Construtora Bom Conselho']
    );
    const A = cons.rows[0];
    if (!A) {
      throw new Error('Rode antes o seed principal (npm run seed): a construtora de teste não existe.');
    }

    const ja = await client.query(
      `SELECT id FROM centrais WHERE construtora_id = $1 AND cnpj = $2`,
      [A.id, '11.222.333/0001-44']
    );
    if (ja.rows[0]) {
      await client.query('ROLLBACK');
      console.log('Os cadastros de teste já existem; nada a fazer.');
      return;
    }

    // --- Central com movimento (não pode ser excluída, só desativada)
    const centralComMovimento = (await client.query(
      `INSERT INTO centrais (construtora_id, nome, cnpj, contato)
       VALUES ($1, $2, $3, $4) RETURNING id`,
      [A.id, 'Central Concrelama', '11.222.333/0001-44', '(87) 99900-1122']
    )).rows[0].id;

    // --- Central sem movimento (pode ser excluída, só para comparar)
    await client.query(
      `INSERT INTO centrais (construtora_id, nome, cnpj, contato)
       VALUES ($1, $2, $3, $4)`,
      [A.id, 'Central Concremix', '55.666.777/0001-88', '(87) 99800-3344']
    );

    const lote = await client.query(
      `SELECT id FROM lotes WHERE construtora_id = $1 AND numero = $2`,
      [A.id, '12/03']
    );
    const loteId = lote.rows[0] ? lote.rows[0].id : null;

    await client.query(
      `INSERT INTO caminhoes (central_id, lote_id, placa) VALUES
       ($1, $2, 'QRZ-4C18'),
       ($1, $2, 'QRZ-4C19'),
       ($1, $2, 'QRZ-4C20')`,
      [centralComMovimento, loteId]
    );

    // --- Laboratório com usuário de acesso (não pode ser excluído, só
    // desativado) e laboratório sem usuário (pode ser excluído)
    const labComUsuario = (await client.query(
      `INSERT INTO laboratorios (construtora_id, nome, cnpj, contato)
       VALUES ($1, $2, $3, $4) RETURNING id`,
      [A.id, 'Laboratório UAST', '22.333.444/0001-55', '(87) 99700-5566']
    )).rows[0].id;

    await client.query(
      `INSERT INTO laboratorios (construtora_id, nome, cnpj, contato)
       VALUES ($1, $2, $3, $4)`,
      [A.id, 'Laboratório Central de Ensaios', '66.777.888/0001-99', '(87) 99600-7788']
    );

    // O usuário "lab" do seed principal passa a pertencer a este
    // laboratório, se ele já existir (idempotente: não falha se não
    // existir ainda).
    await client.query(
      `UPDATE usuarios SET laboratorio_id = $1 WHERE username = 'lab'`,
      [labComUsuario]
    );

    await client.query('COMMIT');
    console.log('Seed de cadastros concluído.');
    console.log(`  Central com movimento (3 caminhões): id ${centralComMovimento}`);
    console.log(`  Laboratório com usuário vinculado ("lab"): id ${labComUsuario}`);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Seed de cadastros falhou, nada foi gravado:', err.message);
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
}

main();
