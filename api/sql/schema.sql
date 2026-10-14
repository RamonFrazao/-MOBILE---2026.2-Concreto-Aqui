-- Concreto Aqui — esquema do banco.
-- Todos os comandos usam IF NOT EXISTS (ou um bloco DO que confere antes
-- de agir): pode rodar este arquivo de novo por cima de um banco que já
-- existe, sem perder nada. Ele só cria/ajusta o que ainda não existe.

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

CREATE UNIQUE INDEX IF NOT EXISTS pavimentos_obra_nome_uq
  ON pavimentos (obra_id, lower(nome));

CREATE TABLE IF NOT EXISTS pecas (
  id SERIAL PRIMARY KEY,
  pavimento_id INTEGER NOT NULL REFERENCES pavimentos(id) ON DELETE CASCADE,
  tipo TEXT NOT NULL CHECK (tipo IN ('pilar', 'viga', 'laje', 'fundacao')),
  identificacao TEXT NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS pecas_pavimento_identificacao_uq
  ON pecas (pavimento_id, lower(identificacao));

-- Sem ON DELETE CASCADE de propósito: o Postgres recusa apagar uma peça
-- enquanto existir lançamento apontando para ela.
CREATE TABLE IF NOT EXISTS lancamentos (
  id SERIAL PRIMARY KEY,
  peca_id INTEGER NOT NULL REFERENCES pecas(id),
  lote_id INTEGER REFERENCES lotes(id),
  data_lancamento DATE NOT NULL
);

CREATE INDEX IF NOT EXISTS lancamentos_peca_idx ON lancamentos (peca_id);

-- ---------------------------------------------------------------------
-- Centrais e laboratórios (T03)
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS centrais (
  id SERIAL PRIMARY KEY,
  construtora_id INTEGER NOT NULL REFERENCES construtoras(id),
  nome TEXT NOT NULL,
  cnpj TEXT NOT NULL,
  contato TEXT NOT NULL,
  ativo BOOLEAN NOT NULL DEFAULT true
);

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

ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS laboratorio_id INTEGER REFERENCES laboratorios(id);
ALTER TABLE lotes ADD COLUMN IF NOT EXISTS central_id INTEGER REFERENCES centrais(id);

CREATE TABLE IF NOT EXISTS caminhoes (
  id SERIAL PRIMARY KEY,
  central_id INTEGER NOT NULL REFERENCES centrais(id),
  lote_id INTEGER REFERENCES lotes(id),
  placa TEXT,
  criado_em TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS caminhoes_central_idx ON caminhoes (central_id);

-- ---------------------------------------------------------------------
-- Classes de concreto, em campos estruturados (T04)
-- A classe reúne o que se especifica ao comprar: fck, abatimento com
-- tolerância, dimensão do agregado e aditivos. A tolerância é o que a
-- história da chegada do caminhão (T09) vai usar para decidir se ele
-- entra ou volta — por isso mora aqui, em dado, e não em número escrito
-- no código.
-- Os campos antigos (abatimento TEXT, agregado TEXT, criados antes desta
-- história) ficam para trás, sem uso: nada os lê mais, mas também nada
-- os apaga, para não perder dado de quem já tinha classes cadastradas.
-- ---------------------------------------------------------------------

ALTER TABLE classes_concreto ADD COLUMN IF NOT EXISTS abatimento_alvo INTEGER;
ALTER TABLE classes_concreto ADD COLUMN IF NOT EXISTS abatimento_tolerancia INTEGER;
ALTER TABLE classes_concreto ADD COLUMN IF NOT EXISTS agregado_mm NUMERIC;
ALTER TABLE classes_concreto ADD COLUMN IF NOT EXISTS aditivo_retardador BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE classes_concreto ADD COLUMN IF NOT EXISTS aditivos_outros TEXT;

-- Preenche as classes que já existiam antes desta história (lidas do
-- seed inicial), lendo o texto livre antigo que os campos novos
-- substituem. Se você tiver outras classes além de C25/C30, preencha
-- abatimento_alvo/abatimento_tolerancia/agregado_mm manualmente para
-- elas antes de seguir — os dois ALTER COLUMN ... SET NOT NULL logo
-- abaixo falham enquanto sobrar alguma linha nula.
UPDATE classes_concreto
   SET abatimento_alvo = 100, abatimento_tolerancia = 20, agregado_mm = 19
 WHERE nome = 'C25' AND abatimento_alvo IS NULL;
UPDATE classes_concreto
   SET abatimento_alvo = 90, abatimento_tolerancia = 20, agregado_mm = 19
 WHERE nome = 'C30' AND abatimento_alvo IS NULL;

ALTER TABLE classes_concreto ALTER COLUMN abatimento_alvo SET NOT NULL;
ALTER TABLE classes_concreto ALTER COLUMN abatimento_tolerancia SET NOT NULL;
ALTER TABLE classes_concreto ALTER COLUMN agregado_mm SET NOT NULL;

-- A tolerância é obrigatória (NOT NULL acima) e não aceita valor
-- negativo (CHECK abaixo). Postgres não tem "ADD CONSTRAINT IF NOT
-- EXISTS", por isso o bloco DO confere antes de tentar criar de novo.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'classes_concreto_tolerancia_nao_negativa'
  ) THEN
    ALTER TABLE classes_concreto
      ADD CONSTRAINT classes_concreto_tolerancia_nao_negativa CHECK (abatimento_tolerancia >= 0);
  END IF;
END $$;

-- Nome de classe não se repete dentro da mesma construtora (sem
-- diferenciar maiúscula de minúscula).
CREATE UNIQUE INDEX IF NOT EXISTS classes_concreto_construtora_nome_uq
  ON classes_concreto (construtora_id, lower(nome));

-- ---------------------------------------------------------------------
-- Pedidos (T05)
-- O pedido registra o que foi comprado: central, classe, volume em m³,
-- data e hora previstas e a peça de destino. É a referência da conferência
-- na chegada (T07): nota com fck diferente do pedido é divergência.
-- Um pedido pode receber vários caminhões (caminhoes.pedido_id), e o
-- volume já entregue é a soma do volume desses caminhões.
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS pedidos (
  id SERIAL PRIMARY KEY,
  construtora_id INTEGER NOT NULL REFERENCES construtoras(id),
  -- Número próprio do pedido, sequencial dentro de cada construtora
  -- (1, 2, 3...). Quem atribui é a API, dentro de uma transação.
  numero INTEGER NOT NULL,
  central_id INTEGER NOT NULL REFERENCES centrais(id),
  classe_id INTEGER NOT NULL REFERENCES classes_concreto(id),
  peca_id INTEGER NOT NULL REFERENCES pecas(id),
  volume NUMERIC(10, 2) NOT NULL CHECK (volume > 0),
  prevista_para TIMESTAMPTZ NOT NULL,
  status TEXT NOT NULL DEFAULT 'aberto' CHECK (status IN ('aberto', 'cancelado')),
  criado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
  cancelado_em TIMESTAMPTZ
);

-- Backstop do número próprio: mesmo que duas requisições se cruzem, o
-- banco não deixa dois pedidos da mesma construtora com o mesmo número.
CREATE UNIQUE INDEX IF NOT EXISTS pedidos_construtora_numero_uq
  ON pedidos (construtora_id, numero);

CREATE INDEX IF NOT EXISTS pedidos_peca_idx ON pedidos (peca_id);

-- Cada caminhão que chega passa a poder apontar para o pedido a que
-- pertence, com o volume que trouxe. Vários caminhões, um pedido.
ALTER TABLE caminhoes ADD COLUMN IF NOT EXISTS pedido_id INTEGER REFERENCES pedidos(id);
ALTER TABLE caminhoes ADD COLUMN IF NOT EXISTS volume NUMERIC(10, 2) CHECK (volume > 0);
CREATE INDEX IF NOT EXISTS caminhoes_pedido_idx ON caminhoes (pedido_id);

-- Pedido cancelado não recebe caminhão. A regra "só cancela enquanto
-- nenhum caminhão chegou" é conferida na API; este gatilho garante o
-- outro lado direto no banco: depois de cancelado, nenhum caminhão pode
-- ser ligado ao pedido (FOR SHARE faz o cancelamento e a chegada de um
-- caminhão se enfileirarem em vez de se cruzarem).
CREATE OR REPLACE FUNCTION caminhoes_pedido_aberto() RETURNS trigger AS $$
DECLARE
  situacao TEXT;
BEGIN
  IF NEW.pedido_id IS NOT NULL THEN
    SELECT status INTO situacao FROM pedidos WHERE id = NEW.pedido_id FOR SHARE;
    IF situacao = 'cancelado' THEN
      RAISE EXCEPTION 'Pedido cancelado não recebe caminhão'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS caminhoes_pedido_aberto_tg ON caminhoes;
CREATE TRIGGER caminhoes_pedido_aberto_tg
  BEFORE INSERT OR UPDATE OF pedido_id ON caminhoes
  FOR EACH ROW EXECUTE FUNCTION caminhoes_pedido_aberto();
