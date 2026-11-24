// Exemplar = corpos de prova da MESMA amostra e da MESMA idade.
// Resultado do exemplar = MAIOR valor entre os dois — nunca a média.
// (NBR: o menor costuma refletir falha de moldagem/cura, não do concreto.)
//
// Se um corpo foi descartado, usa o que restou e sinaliza incompleto.
// Todo cálculo é feito no servidor.

/**
 * Monta o exemplar a partir dos corpos de uma amostra+idade.
 * @param {Array<{id, identificacao, resultado, situacao}>} corpos
 */
function montarExemplar(amostraId, idade, corpos, meta = {}) {
  const ativos = corpos.filter((c) => c.situacao !== 'descartado');
  const descartados = corpos.filter((c) => c.situacao === 'descartado');
  const comResultado = ativos.filter((c) => c.resultado != null && Number.isFinite(Number(c.resultado)));

  let valor = null;
  let usadoId = null;
  let incompleto = descartados.length > 0 || ativos.length < 2;
  let pendente = false;

  if (comResultado.length === 0) {
    pendente = ativos.length > 0; // ainda esperando rompimento
  } else if (comResultado.length === 1) {
    valor = Number(comResultado[0].resultado);
    usadoId = comResultado[0].id;
    // um só resultado: se o outro foi descartado → incompleto; se ainda não rompeu → pendente parcial
    if (ativos.length > 1 && ativos.some((c) => c.resultado == null)) {
      pendente = true;
      valor = null;
      usadoId = null;
    } else {
      incompleto = true; // só um valor válido (descarte ou único CP)
    }
  } else {
    // dois ou mais com resultado: pega o MAIOR
    let maior = comResultado[0];
    for (const c of comResultado) {
      if (Number(c.resultado) > Number(maior.resultado)) maior = c;
    }
    valor = Number(maior.resultado);
    usadoId = maior.id;
    incompleto = descartados.length > 0 || ativos.length < 2;
  }

  const corposFmt = corpos.map((c) => ({
    id: c.id,
    identificacao: c.identificacao,
    resultado: c.resultado != null ? Number(c.resultado) : null,
    situacao: c.situacao,
    usado_no_exemplar: usadoId != null && c.id === usadoId,
    descartado: c.situacao === 'descartado',
  }));

  return {
    amostra_id: amostraId,
    idade,
    valor, // null se pendente
    incompleto,
    pendente: pendente && valor == null,
    sinalizado: incompleto && valor != null, // usou o que restou após descarte
    corpos: corposFmt,
    ...meta,
  };
}

/**
 * Agrupa corpos por (amostra_id, idade) e monta exemplares.
 */
function exemplaresDeCorpos(rows) {
  const grupos = new Map();
  for (const r of rows) {
    const key = `${r.amostra_id}:${r.idade}`;
    if (!grupos.has(key)) {
      grupos.set(key, {
        amostra_id: r.amostra_id,
        idade: r.idade,
        meta: {
          lote_id: r.lote_id,
          lote_numero: r.lote_numero,
          numero_nota: r.numero_nota,
          placa: r.placa,
          coletada_em: r.coletada_em,
        },
        corpos: [],
      });
    }
    grupos.get(key).corpos.push({
      id: r.id,
      identificacao: r.identificacao,
      resultado: r.resultado,
      situacao: r.situacao,
    });
  }

  const lista = [];
  for (const g of grupos.values()) {
    lista.push(montarExemplar(g.amostra_id, g.idade, g.corpos, g.meta));
  }
  // por idade, depois amostra
  lista.sort((a, b) => a.idade - b.idade || a.amostra_id - b.amostra_id);
  return lista;
}

module.exports = { montarExemplar, exemplaresDeCorpos };
