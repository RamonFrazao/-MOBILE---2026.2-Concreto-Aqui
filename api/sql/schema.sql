-- Concreto Aqui — esquema do banco.
-- Todos os comandos usam IF NOT EXISTS: pode rodar este arquivo de novo
-- por cima de um banco que já existe, sem perder nada. Ele só cria o que
-- ainda não existe.

CREATE TABLE IF NOT EXISTS construtoras (
  id SERIAL PRIMARY KEY,
  nome TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS usuarios (
  id SERIAL PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  senha_hash TEXT NOT NULL,
  perfil TEXT NOT NULL CHECK (perfil IN ('construtora', 'obra', 'laboratorio')),
  nome TEXT NOT NULL,
  construtora_id INTEGER REFERENCES construtoras(id)
);

CREATE TABLE IF NOT EXISTS classes_concreto (
  id SERIAL PRIMARY KEY,
  construtora_id INTEGER REFERENCES construtoras(id) NOT NULL,
  nome TEXT NOT NULL,
  fck INTEGER NOT NULL,
  abatimento TEXT,
  agregado TEXT
);

CREATE TABLE IF NOT EXISTS lotes (
  id SERIAL PRIMARY KEY,
  construtora_id INTEGER REFERENCES construtoras(id) NOT NULL,
  numero TEXT NOT NULL,
  peca TEXT NOT NULL,
  classe_id INTEGER REFERENCES classes_concreto(id),
  volume NUMERIC,
  status TEXT NOT NULL DEFAULT 'aguardando_caminhao'
);

-- ---------------------------------------------------------------------
-- Obras, pavimentos e peças (T02)
-- Uma obra tem pavimentos; um pavimento tem peças (pilar, viga, laje,
-- fundação). A peça é o destino final do concreto: é ela que responde
-- "onde foi parar esse concreto?" 28 dias depois.
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS obras (
  id SERIAL PRIMARY KEY,
  construtora_id INTEGER NOT NULL REFERENCES construtoras(id),
  nome TEXT NOT NULL,
  endereco TEXT NOT NULL,
  responsavel_tecnico TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS pavimentos (
  id SERIAL PRIMARY KEY,
  obra_id INTEGER NOT NULL REFERENCES obras(id) ON DELETE CASCADE,
  nome TEXT NOT NULL
);

-- Nome de pavimento não se repete dentro da mesma obra (sem diferenciar
-- maiúscula de minúscula: "Térreo" e "térreo" são o mesmo pavimento).
CREATE UNIQUE INDEX IF NOT EXISTS pavimentos_obra_nome_uq
  ON pavimentos (obra_id, lower(nome));

CREATE TABLE IF NOT EXISTS pecas (
  id SERIAL PRIMARY KEY,
  pavimento_id INTEGER NOT NULL REFERENCES pavimentos(id) ON DELETE CASCADE,
  tipo TEXT NOT NULL CHECK (tipo IN ('pilar', 'viga', 'laje', 'fundacao')),
  identificacao TEXT NOT NULL
);

-- A identificação da peça não se repete dentro do mesmo pavimento
-- (também sem diferenciar maiúscula de minúscula: "P7" e "p7" colidem).
CREATE UNIQUE INDEX IF NOT EXISTS pecas_pavimento_identificacao_uq
  ON pecas (pavimento_id, lower(identificacao));

-- Cada vez que concreto é lançado numa peça, fica um registro aqui.
-- A chave estrangeira para pecas NÃO tem ON DELETE CASCADE de propósito:
-- mesmo que alguém tente apagar a peça direto no banco, o Postgres
-- recusa enquanto existir lançamento apontando para ela.
CREATE TABLE IF NOT EXISTS lancamentos (
  id SERIAL PRIMARY KEY,
  peca_id INTEGER NOT NULL REFERENCES pecas(id),
  lote_id INTEGER REFERENCES lotes(id),
  data_lancamento DATE NOT NULL
);

CREATE INDEX IF NOT EXISTS lancamentos_peca_idx ON lancamentos (peca_id);

-- ---------------------------------------------------------------------
-- Centrais e laboratórios (T03)
-- A central vende o concreto: é só cadastro, nunca tem tela nem login.
-- O laboratório ensaia o concreto: é cadastro, mas pode receber um
-- usuário de acesso (perfil "laboratorio") depois de criado.
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS centrais (
  id SERIAL PRIMARY KEY,
  construtora_id INTEGER NOT NULL REFERENCES construtoras(id),
  nome TEXT NOT NULL,
  cnpj TEXT NOT NULL,
  contato TEXT NOT NULL,
  ativo BOOLEAN NOT NULL DEFAULT true
);

-- CNPJ não se repete dentro da mesma construtora (cada construtora tem
-- o seu próprio cadastro; duas construtoras podem comprar da mesma
-- central sem conflito aqui).
CREATE UNIQUE INDEX IF NOT EXISTS centrais_construtora_cnpj_uq
  ON centrais (construtora_id, cnpj);

CREATE TABLE IF NOT EXISTS laboratorios (
  id SERIAL PRIMARY KEY,
  construtora_id INTEGER NOT NULL REFERENCES construtoras(id),
  nome TEXT NOT NULL,
  cnpj TEXT NOT NULL,
  contato TEXT NOT NULL,
  ativo BOOLEAN NOT NULL DEFAULT true
);

CREATE UNIQUE INDEX IF NOT EXISTS laboratorios_construtora_cnpj_uq
  ON laboratorios (construtora_id, cnpj);

-- O usuário de acesso de um laboratório pertence a ele. Fica nulo para
-- os perfis "construtora" e "obra".
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS laboratorio_id INTEGER REFERENCES laboratorios(id);

-- De qual central veio o concreto deste lote.
ALTER TABLE lotes ADD COLUMN IF NOT EXISTS central_id INTEGER REFERENCES centrais(id);

-- Um registro por caminhão que chegou — é o que permite contar "quantos
-- caminhões vieram de cada central". A chegada de caminhão em si
-- (nota, prazo de 90 min) é modelada em detalhe numa história futura;
-- esta tabela já existe para dar suporte a essa contagem desde já.
CREATE TABLE IF NOT EXISTS caminhoes (
  id SERIAL PRIMARY KEY,
  central_id INTEGER NOT NULL REFERENCES centrais(id),
  lote_id INTEGER REFERENCES lotes(id),
  placa TEXT,
  criado_em TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS caminhoes_central_idx ON caminhoes (central_id);
