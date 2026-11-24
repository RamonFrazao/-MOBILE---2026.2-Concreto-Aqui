// Dados de teste da T08. Rode depois do seed da T07:
//   node sql/seed_caminhoes.js   (se ainda não rodou)
//   node sql/seed_prazos.js
// Pode rodar de novo sem duplicar: se a nota DEMO-0003 já existe, não faz nada.
//
// Deixa caminhões em cada situação do prazo de descarga:
//   DEMO-0001 — descarga encerrada DENTRO do prazo.
//   DEMO-0002 — descarga encerrada FORA do prazo (continua no lote e no relatório).
//   DEMO-0003 — descarregando, com bastante tempo.
//   DEMO-0004 — descarregando, faltando ~12 minutos: já está na faixa de aviso
//               e, se você esperar, ESTOURA ao vivo.
//   DEMO-0005 — descarregando, prazo já estourado: encerrar a descarga grava
//               "fora do prazo".
require('dotenv').config();
const pool = require('../src/db');

async function main() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const cons = await client.query(`SELECT id FROM construtoras WHERE nome = $1`, ['Construtora Bom Conselho']);
    const A = cons.rows[0];
    if (!A) throw new Error('Rode antes o seed principal (npm run seed): a construtora de teste não existe.');

    const ja = await client.query(`SELECT 1 FROM caminhoes WHERE numero_nota = 'DEMO-0003' LIMIT 1`);
    if (ja.rows[0]) {
      await client.query('ROLLBACK');
      console.log('Os caminhões de teste do prazo (DEMO-0003...) já existem; nada a fazer.');
      return;
    }

    const d1 = (await client.query(`SELECT id, lote_id, central_id, primeiro_contato_em FROM caminhoes WHERE numero_nota = 'DEMO-0001'`)).rows[0];
    const d2 = (await client.query(`SELECT id, primeiro_contato_em FROM caminhoes WHERE numero_nota = 'DEMO-0002'`)).rows[0];
    if (!d1 || !d2) throw new Error('Rode antes: node sql/seed_caminhoes.js');

    await client.query(
      'INSERT INTO configuracoes_prazo (construtora_id) VALUES ($1) ON CONFLICT (construtora_id) DO NOTHING', [A.id]
    );

    // Duas descargas já encerradas: uma dentro do prazo, outra fora.
    await client.query(
      `UPDATE caminhoes SET descarga_fim_em = primeiro_contato_em + interval '80 minutes', fora_do_prazo = false WHERE id = $1`, [d1.id]
    );
    await client.query(
      `UPDATE caminhoes SET descarga_fim_em = primeiro_contato_em + interval '100 minutes', fora_do_prazo = true WHERE id = $1`, [d2.id]
    );

    const classe = (await client.query(
      `SELECT id, nome, fck FROM classes_concreto WHERE construtora_id = $1 ORDER BY fck, id LIMIT 1`, [A.id]
    )).rows[0];
    const peca = (await client.query(`SELECT peca_id FROM lote_pecas WHERE lote_id = $1 ORDER BY peca_id LIMIT 1`, [d1.lote_id])).rows[0];
    const tecnico = (await client.query(`SELECT id FROM usuarios WHERE username = 'tecnico'`)).rows[0];

    // Um pedido grande, para os caminhões novos não terem divergência de volume.
    await client.query('SELECT pg_advisory_xact_lock(1005, $1)', [A.id]);
    const { rows: [{ proximo }] } = await client.query(
      'SELECT COALESCE(MAX(numero), 0) + 1 AS proximo FROM pedidos WHERE construtora_id = $1', [A.id]
    );
    const pedidoId = (await client.query(
      `INSERT INTO pedidos (construtora_id, numero, central_id, classe_id, peca_id, volume, prevista_para)
       VALUES ($1, $2, $3, $4, $5, 30, now()) RETURNING id`,
      [A.id, proximo, d1.central_id, classe.id, peca.peca_id]
    )).rows[0].id;

    const novo = (nota, placa, minutosDesdeContato) => client.query(
      `INSERT INTO caminhoes
         (central_id, lote_id, pedido_id, numero_nota, placa, volume, traco, aditivo_retardador,
          classe_nota, fck_nota, primeiro_contato_em, chegada_obra_em, registrado_por, prazo_minutos)
       VALUES ($1, $2, $3, $4, $5, 6, '1 : 2,1 : 2,8 : 0,45', false, $6, $7,
               now() - ($8 || ' minutes')::interval,
               now() - (GREATEST($8::int - 10, 0) || ' minutes')::interval, $9,
               (SELECT prazo_descarga_minutos FROM configuracoes_prazo WHERE construtora_id = $10))`,
      [d1.central_id, d1.lote_id, pedidoId, nota, placa, classe.nome, classe.fck, String(minutosDesdeContato),
       tecnico ? tecnico.id : null, A.id]
    );

    await novo('DEMO-0003', 'DEM-1A03', 20);
    await novo('DEMO-0004', 'DEM-1A04', 78);
    await novo('DEMO-0005', 'DEM-1A05', 100);

    await client.query('COMMIT');
    console.log('Seed do prazo concluído: DEMO-0001 (encerrada no prazo), DEMO-0002 (encerrada fora do prazo), DEMO-0003 (com tempo), DEMO-0004 (faltando ~12 min), DEMO-0005 (prazo estourado).');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Seed do prazo falhou, nada foi gravado:', err.message);
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
}

main();
