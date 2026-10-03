// Dados de teste da T02. Rode depois do schema e do seed principal:
//   node sql/seed_obras.js
// Pode rodar de novo sem duplicar: se a obra de teste já existe, não faz nada.
// Nomes, endereço e responsável são fictícios.
require('dotenv').config();
const pool = require('../src/db');

async function main() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const cons = await client.query(
      `SELECT id, nome FROM construtoras WHERE nome IN ($1, $2)`,
      ['Construtora Bom Conselho', 'Construtora Nordeste']
    );
    const A = cons.rows.find((c) => c.nome === 'Construtora Bom Conselho');
    const B = cons.rows.find((c) => c.nome === 'Construtora Nordeste');
    if (!A || !B) {
      throw new Error('Rode antes o seed principal (npm run seed): as construtoras de teste não existem.');
    }

    const ja = await client.query(
      `SELECT id FROM obras WHERE construtora_id = $1 AND nome = $2`,
      [A.id, 'Residencial Bom Conselho']
    );
    if (ja.rows[0]) {
      await client.query('ROLLBACK');
      console.log('A obra de teste já existe; nada a fazer.');
      return;
    }

    // --- Construtora A (a que os usuários de teste enxergam)
    const obraA = (await client.query(
      `INSERT INTO obras (construtora_id, nome, endereco, responsavel_tecnico)
       VALUES ($1, $2, $3, $4) RETURNING id`,
      [A.id, 'Residencial Bom Conselho', 'Rua das Acácias, 120 - Centro', 'Eng. Carlos Mendes']
    )).rows[0].id;

    const pav = {};
    for (const nome of ['Térreo', '2º pavimento', '3º pavimento']) {
      pav[nome] = (await client.query(
        'INSERT INTO pavimentos (obra_id, nome) VALUES ($1, $2) RETURNING id',
        [obraA, nome]
      )).rows[0].id;
    }

    const pecas = [
      ['Térreo', 'fundacao', 'B1'],
      ['2º pavimento', 'laje', 'L-201'],
      ['3º pavimento', 'pilar', 'P1'],
      ['3º pavimento', 'pilar', 'P7'],
      ['3º pavimento', 'laje', 'L-301'],
    ];
    const idPeca = {};
    for (const [pavNome, tipo, ident] of pecas) {
      idPeca[ident] = (await client.query(
        'INSERT INTO pecas (pavimento_id, tipo, identificacao) VALUES ($1, $2, $3) RETURNING id',
        [pav[pavNome], tipo, ident]
      )).rows[0].id;
    }

    // Um lançamento: o pilar P7 recebeu o lote 12/03. É ele que permite
    // testar "peça com concreto lançado não pode ser excluída".
    const lote = await client.query(
      `SELECT id FROM lotes WHERE construtora_id = $1 AND numero = $2`,
      [A.id, '12/03']
    );
    await client.query(
      `INSERT INTO lancamentos (peca_id, lote_id, data_lancamento) VALUES ($1, $2, $3)`,
      [idPeca['P7'], lote.rows[0] ? lote.rows[0].id : null, '2026-03-12']
    );

    // --- Construtora B: uma obra só para provar que a A não enxerga a dela
    const obraB = (await client.query(
      `INSERT INTO obras (construtora_id, nome, endereco, responsavel_tecnico)
       VALUES ($1, $2, $3, $4) RETURNING id`,
      [B.id, 'Edifício Nordeste Center', 'Av. Principal, 900', 'Eng. Ana Lima']
    )).rows[0].id;

    await client.query('COMMIT');
    console.log('Seed de obras concluído.');
    console.log(`  Obra da construtora A (Residencial Bom Conselho): id ${obraA}`);
    console.log(`  Peça com concreto lançado (P7, 12/03/2026): id ${idPeca['P7']}`);
    console.log(`  Peça sem concreto (P1): id ${idPeca['P1']}`);
    console.log(`  Obra de OUTRA construtora (para testar a recusa): id ${obraB}`);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Seed de obras falhou, nada foi gravado:', err.message);
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
}

main();
