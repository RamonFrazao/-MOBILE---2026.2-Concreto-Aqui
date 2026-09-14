require('dotenv').config();
const bcrypt = require('bcrypt');
const pool = require('../src/db');

async function main() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const { rows: [construtoraA] } = await client.query(
      `INSERT INTO construtoras (nome) VALUES ($1) RETURNING id`,
      ['Construtora Bom Conselho']
    );
    // Esta segunda construtora existe só para provar que a API recusa
    // pedidos de dados que não são da construtora logada.
    const { rows: [construtoraB] } = await client.query(
      `INSERT INTO construtoras (nome) VALUES ($1) RETURNING id`,
      ['Construtora Nordeste']
    );

    const senhaHash = await bcrypt.hash('1234', 10);

    await client.query(
      `INSERT INTO usuarios (username, senha_hash, perfil, nome, construtora_id) VALUES ($1,$2,$3,$4,$5)`,
      ['construtora', senhaHash, 'construtora', 'Escritório técnico', construtoraA.id]
    );
    await client.query(
      `INSERT INTO usuarios (username, senha_hash, perfil, nome, construtora_id) VALUES ($1,$2,$3,$4,$5)`,
      ['tecnico', senhaHash, 'obra', 'Técnico no canteiro', construtoraA.id]
    );
    await client.query(
      `INSERT INTO usuarios (username, senha_hash, perfil, nome, construtora_id) VALUES ($1,$2,$3,$4,$5)`,
      ['lab', senhaHash, 'laboratorio', 'Laboratorista', construtoraA.id]
    );

    const { rows: [classeA] } = await client.query(
      `INSERT INTO classes_concreto (construtora_id, nome, fck, abatimento, agregado)
       VALUES ($1,$2,$3,$4,$5) RETURNING id`,
      [construtoraA.id, 'C25', 25, '100 ± 20 mm', '19 mm']
    );
    await client.query(
      `INSERT INTO lotes (construtora_id, numero, peca, classe_id, volume, status) VALUES ($1,$2,$3,$4,$5,$6)`,
      [construtoraA.id, '12/03', 'Pilares do 3º pavimento', classeA.id, 8, 'aceito']
    );
    await client.query(
      `INSERT INTO lotes (construtora_id, numero, peca, classe_id, volume, status) VALUES ($1,$2,$3,$4,$5,$6)`,
      [construtoraA.id, '14/03', 'Laje do 2º pavimento L-201', classeA.id, 6, 'aguardando_caminhao']
    );

    const { rows: [classeB] } = await client.query(
      `INSERT INTO classes_concreto (construtora_id, nome, fck, abatimento, agregado)
       VALUES ($1,$2,$3,$4,$5) RETURNING id`,
      [construtoraB.id, 'C30', 30, '90 ± 20 mm', '19 mm']
    );
    await client.query(
      `INSERT INTO lotes (construtora_id, numero, peca, classe_id, volume, status) VALUES ($1,$2,$3,$4,$5,$6)`,
      [construtoraB.id, '19/07', 'Fundação bloco B', classeB.id, 10, 'aguardando_caminhao']
    );

    await client.query('COMMIT');
    console.log('Seed concluído: construtora A (login "construtora"/"tecnico"/"lab") e construtora B (só para teste de recusa, código de lote 19/07).');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Seed falhou, nada foi gravado:', err);
  } finally {
    client.release();
    await pool.end();
  }
}

main();
