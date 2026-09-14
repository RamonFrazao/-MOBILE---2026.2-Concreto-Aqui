-- Concreto Aqui — esquema mínimo para T01 (login) e para demonstrar a
-- recusa de dados de outra construtora. O restante do domínio (caminhão,
-- amostra, exemplar, corpo de prova) continua no mock do app até a E2.

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
  -- só perfis "construtora" pertencem a uma construtora; obra e laboratório
  -- atendem qualquer uma, então ficam com construtora_id nulo por enquanto.
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
