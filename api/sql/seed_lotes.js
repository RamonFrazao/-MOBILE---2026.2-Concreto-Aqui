// Dados de teste da T06. Rode depois dos seeds anteriores (principal,
// obras, cadastros, classes e pedidos):
//   node sql/seed_lotes.js
// Pode rodar de novo sem duplicar: se a construtora de teste já tem lotes
// novos (com obra), não faz nada.
//
// Resultado, na construtora de teste:
//   Lote 12/10 — em andamento, abrange 2 peças, fck 25 MPa, com 2 caminhões
//                (8 m³ + 7 m³ = 15 m³). Não pode ser excluído; pode ser encerrado.
//   Lote 13/10 — em andamento, abrange 1 peça, fck 30 MPa, sem caminhão.
//                Pode ser excluído e pode ser encerrado.
//   Lote 14/10 — já encerrado, com 1 caminhão (6 m³). Não recebe caminhão novo.
require('dotenv').config();
const pool = require('../src/db');

async function main() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const cons = await client.query(`SELECT id FROM construtoras WHERE nome = $1`, ['Construtora Bom Conselho']);
    const A = cons.rows[0];
    if (!A) throw new Error('Rode antes o seed principal (npm run seed): a construtora de teste não existe.');

    const ja = await client.query(
      `SELECT 1 FROM lotes WHERE construtora_id = $1 AND obra_id IS NOT NULL LIMIT 1`, [A.id]
    );
    if (ja.rows[0]) {
      await client.query('ROLLBACK');
      console.log('Já existem lotes novos para a construtora de teste; nada a fazer.');
      return;
    }

    const obra = (await client.query(
      `SELECT o.id FROM obras o
        WHERE o.construtora_id = $1
          AND EXISTS (SELECT 1 FROM pavimentos pv JOIN pecas pc ON pc.pavimento_id = pv.id WHERE pv.obra_id = o.id)
        ORDER BY o.id LIMIT 1`, [A.id]
    )).rows[0];
    if (!obra) throw new Error('Nenhuma obra com peças. Rode antes: node sql/seed_obras.js');

    const pecas = (await client.query(
      `SELECT pc.id, pc.tipo, pc.identificacao
         FROM pecas pc JOIN pavimentos pv ON pv.id = pc.pavimento_id
        WHERE pv.obra_id = $1 ORDER BY pc.id`, [obra.id]
    )).rows;

    const central = (await client.query(
      `SELECT id FROM centrais WHERE construtora_id = $1 AND ativo ORDER BY id LIMIT 1`, [A.id]
    )).rows[0];
    if (!central) throw new Error('Nenhuma central ativa. Rode antes: node sql/seed_cadastros.js');

    const rotulos = { pilar: 'Pilar', viga: 'Viga', laje: 'Laje', fundacao: 'Fundação' };
    const rotulo = (p) => `${rotulos[p.tipo] || p.tipo} ${p.identificacao}`;

    // Pega peças em sequência; se a obra tiver poucas, reaproveita (datas
    // diferentes são concretagens diferentes, então não há conflito).
    const pega = (i) => pecas[i % pecas.length];

    const novoLote = async (dia, fck, lista, status) => {
      const data = `2026-10-${dia}`;
      const id = (await client.query(
        `INSERT INTO lotes (construtora_id, numero, peca, status, obra_id, data_concretagem, fck_projeto)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         RETURNING id`,
        [A.id, `${dia}/10`, lista.map(rotulo).join(', ').slice(0, 200), status, obra.id, data, fck]
      )).rows[0].id;
      for (const p of lista) {
        await client.query(
          `INSERT INTO lote_pecas (lote_id, peca_id, data_concretagem) VALUES ($1, $2, $3)`,
          [id, p.id, data]
        );
      }
      return id;
    };

    const l1 = await novoLote('12', 25, [pega(0), pega(1)], 'em_andamento');
    await novoLote('13', 30, [pega(2)], 'em_andamento');
    const l3 = await novoLote('14', 25, [pega(0)], 'em_andamento');

    await client.query(
      `INSERT INTO caminhoes (central_id, lote_id, placa, volume) VALUES
       ($1, $2, 'LOT-1A01', 8),
       ($1, $2, 'LOT-1A02', 7),
       ($1, $3, 'LOT-3A01', 6)`,
      [central.id, l1, l3]
    );

    // O 14/10 é encerrado por último, como na vida real: primeiro recebe o
    // caminhão, depois encerra (lote encerrado não aceita caminhão novo).
    await client.query(
      `UPDATE lotes SET status = 'encerrado', encerrado_em = now() WHERE id = $1`,
      [l3]
    );

    await client.query('COMMIT');
    console.log('Seed de lotes concluído: 12/10 (2 caminhões, 15 m³), 13/10 (sem caminhão) e 14/10 (encerrado, 1 caminhão).');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Seed de lotes falhou, nada foi gravado:', err.message);
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
}

main();
