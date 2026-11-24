// Aceitação do lote — fck,est conforme NBR 12655:2015 (amostragem parcial).
//
// Documentação do que foi implementado (entrega):
//
// 1) Exemplares de 28 dias, ordenados do menor para o maior: f1 ≤ f2 ≤ … ≤ fn
// 2) Casos excepcionais (2 ≤ n ≤ 5): fck,est = Ψ6 × f1
// 3) 6 ≤ n < 20: m = floor(n/2);
//      fck,est = 2 × (f1+…+f(m-1))/(m-1) − fm   (se m = 1: 2×f1 − f1 = f1)
//    e fck,est não pode ser menor que Ψ6 × f1
// 4) n ≥ 20: fck,est = fcm − 1,65 × sd  (sd com n−1 graus de liberdade)
//    e também não menor que Ψ6 × f1 (Ψ6 para n≥16)
// 5) Ψ6 e condição de preparo (A / B / C) vêm da tabela coeficientes_psi6
//    e do cadastro do lote — não estão fixos no código da fórmula.
// 6) Aceito se fck,est ≥ fck_projeto. Reprovado exige decisão do engenheiro.
// 7) Resultados de 7 dias são só alerta; não entram no fck,est.

/** Ψ6: interpolação linear entre os n tabulados, se necessário. */
function psi6DeTabela(linhas, n) {
  if (!linhas.length) return null;
  const map = new Map(linhas.map((r) => [Number(r.n_exemplares), Number(r.psi6)]));
  if (map.has(n)) return map.get(n);
  if (n >= 16) return map.get(16) ?? map.get(Math.max(...map.keys()));
  const keys = [...map.keys()].sort((a, b) => a - b);
  if (n <= keys[0]) return map.get(keys[0]);
  if (n >= keys[keys.length - 1]) return map.get(keys[keys.length - 1]);
  let lo = keys[0];
  let hi = keys[keys.length - 1];
  for (const k of keys) {
    if (k <= n) lo = k;
    if (k >= n) {
      hi = k;
      break;
    }
  }
  if (lo === hi) return map.get(lo);
  const t = (n - lo) / (hi - lo);
  return map.get(lo) + t * (map.get(hi) - map.get(lo));
}

/**
 * @param {number[]} valores — resistências dos exemplares de 28 dias (já com valor)
 * @param {string} condicao — 'A' | 'B' | 'C'
 * @param {Array<{n_exemplares, psi6}>} tabelaPsi
 */
function calcularFckEst(valores, condicao, tabelaPsi) {
  const ordenados = valores
    .map(Number)
    .filter((v) => Number.isFinite(v))
    .sort((a, b) => a - b);
  const n = ordenados.length;
  if (n < 2) {
    return {
      ok: false,
      erro: 'São necessários pelo menos 2 exemplares de 28 dias com resultado para calcular o fck,est.',
      n,
      ordenados,
    };
  }

  const psi = psi6DeTabela(
    tabelaPsi.filter((r) => r.condicao_preparo === condicao || (condicao !== 'A' && ['B', 'C'].includes(r.condicao_preparo))),
    n
  );
  // Prefer exact condition rows
  const psiExato = psi6DeTabela(
    tabelaPsi.filter((r) => r.condicao_preparo === condicao),
    n
  );
  const psi6 = psiExato != null ? psiExato : psi;
  if (psi6 == null) {
    return { ok: false, erro: 'Coeficiente Ψ6 não cadastrado para esta condição de preparo.', n, ordenados };
  }

  const f1 = ordenados[0];
  let fckEst;
  let regra;

  if (n <= 5) {
    // Casos excepcionais (6.2.3.3)
    fckEst = psi6 * f1;
    regra = 'excepcional_2_a_5';
  } else if (n < 20) {
    // 6 ≤ n < 20
    const m = Math.floor(n / 2);
    const menores = ordenados.slice(0, m);
    let parcial;
    if (m === 1) {
      parcial = menores[0];
    } else {
      const somaExcetoUltimo = menores.slice(0, m - 1).reduce((s, v) => s + v, 0);
      parcial = (2 * somaExcetoUltimo) / (m - 1) - menores[m - 1];
    }
    const minimo = psi6 * f1;
    fckEst = Math.max(parcial, minimo);
    regra = 'parcial_6_a_19';
  } else {
    // n ≥ 20
    const media = ordenados.reduce((s, v) => s + v, 0) / n;
    const varSum = ordenados.reduce((s, v) => s + (v - media) ** 2, 0);
    const sd = Math.sqrt(varSum / (n - 1));
    const estat = media - 1.65 * sd;
    const minimo = psi6 * f1;
    fckEst = Math.max(estat, minimo);
    regra = 'parcial_n_ge_20';
  }

  // arredondamento prático a 0,1 MPa
  fckEst = Math.round(fckEst * 10) / 10;

  return {
    ok: true,
    fck_est: fckEst,
    n,
    ordenados,
    psi6: Math.round(psi6 * 1000) / 1000,
    condicao_preparo: condicao,
    regra,
    f1,
    minimo_psi: Math.round(psi6 * f1 * 10) / 10,
  };
}

module.exports = { calcularFckEst, psi6DeTabela };
