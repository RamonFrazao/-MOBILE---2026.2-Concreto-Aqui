# Concreto Aqui

Controle tecnológico do concreto, do caminhão até a peça.

O técnico registra a descarga com a hora de verdade. O laboratório lança o rompimento sem julgar a estrutura. A construtora vê o exemplar, o `fck,est` e o relatório que se mostra à fiscalização — inclusive o caminhão recusado e o que descarregou fora do prazo.

## O problema

Na obra, o resultado do concreto se perde entre a nota fiscal, o papel do corpo de prova e a planilha do lote.

- A hora da descarga anotada depois não serve para apurar o prazo.
- O laudo devolve um número em MPa e não diz de qual pilar ele saiu.
- A média dos dois corpos de prova muda a aceitação. A norma manda usar o maior.
- Canteiro sem sinal não pode esperar a internet para guardar a hora.

## O que o sistema faz

| Quem | O que registra |
|---|---|
| Técnico da obra | Caminhão, início e fim da descarga, abatimento, moldagem, cura e remessa |
| Laboratório | Data do rompimento, idade real em dias e resistência em MPa |
| Construtora | Exemplares, `fck,est`, aceitação do lote e relatório |

Regras que o servidor aplica, e que a planilha costuma errar:

- O prazo fecha na **hora de fim** da descarga, com o relógio do servidor.
- Cada corpo de prova recebe uma identificação que não se repete na obra (`CP-AAAA-NNNNN`).
- Dois corpos da mesma amostra e da mesma idade formam um **exemplar**. O resultado é o **maior** dos dois, não a média.
- Corpo rompido aos 30 dias não vira ensaio de 28. A idade real fica gravada.
- O `fck,est` sai dos exemplares de 28 dias, pela amostragem parcial da NBR 12655, e é comparado com o `fck` de projeto. O resultado de 7 dias é alerta, não julgamento.
- Lote reprovado não condena a estrutura. O sistema registra a decisão do engenheiro.
- Sem rede, o lançamento fica no aparelho com um identificador próprio. Enviar duas vezes não cria dois registros.
- O relatório do lote mostra recusados e fora do prazo. Eles não são omitidos.

O laboratório não vê e não altera pedido, lote nem aceitação.

## Stack

- **App:** Flutter (obra, laboratório e construtora no mesmo aplicativo)
- **API:** Node.js e Express
- **Banco:** PostgreSQL
- **Sessão:** JWT, com permissão por perfil

## Como rodar

Pré-requisitos: Node.js 18+, PostgreSQL, Flutter.

### 1. Banco e API

```bash
cd "Projeto Mobile/api"
npm install
