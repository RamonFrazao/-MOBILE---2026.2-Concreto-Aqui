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

-- ---------------------------------------------------------------------
-- Lotes (T06)
-- O lote é a unidade de julgamento: reúne as peças concretadas na mesma
-- condição ("os pilares do 3º pavimento, dia 12/03") e guarda o fck de
-- projeto, o número contra o qual o resultado será comparado na
-- aceitação. Um lote recebe vários caminhões (caminhoes.lote_id).
-- A tabela lotes já existia, num desenho anterior (peça em texto livre,
-- sem obra nem data). Aqui ela ganha os campos novos sem perder nada:
-- as linhas antigas ficam como estavam, sem obra, e fora da listagem.
-- ---------------------------------------------------------------------

ALTER TABLE lotes ADD COLUMN IF NOT EXISTS obra_id INTEGER REFERENCES obras(id);
ALTER TABLE lotes ADD COLUMN IF NOT EXISTS data_concretagem DATE;
ALTER TABLE lotes ADD COLUMN IF NOT EXISTS fck_projeto INTEGER CHECK (fck_projeto > 0);
ALTER TABLE lotes ADD COLUMN IF NOT EXISTS encerrado_em TIMESTAMPTZ;

-- O lote nasce "em andamento" e termina "encerrado". (Linhas antigas
-- podem ter outras situações, como "aceito"; nada as lê como em andamento.)
ALTER TABLE lotes ALTER COLUMN status SET DEFAULT 'em_andamento';

-- Necessário para a ligação abaixo (peça -> lote -> data) ser conferida
-- pelo próprio banco.
CREATE UNIQUE INDEX IF NOT EXISTS lotes_id_data_uq ON lotes (id, data_concretagem);

-- O código do lote ("12/03", "12/03-2"...) não se repete dentro da mesma
-- construtora. Se o seu banco antigo já tiver dois lotes com o mesmo
-- código, o índice não é criado (só avisa) e a API segue garantindo a
-- unicidade dos novos.
DO $$
BEGIN
  CREATE UNIQUE INDEX IF NOT EXISTS lotes_construtora_numero_uq ON lotes (construtora_id, numero);
EXCEPTION WHEN unique_violation THEN
  RAISE NOTICE 'Índice lotes_construtora_numero_uq não criado: já existem códigos de lote repetidos numa construtora.';
END $$;

-- Quais peças o lote abrange. A chave (peca_id, data_concretagem) é única:
-- uma peça pertence a um lote por concretagem — não pode estar em dois
-- lotes da mesma data. A data aqui é cópia da data do lote, e a chave
-- estrangeira composta garante que as duas nunca divirjam.
CREATE TABLE IF NOT EXISTS lote_pecas (
  lote_id INTEGER NOT NULL,
  peca_id INTEGER NOT NULL REFERENCES pecas(id),
  data_concretagem DATE NOT NULL,
  PRIMARY KEY (lote_id, peca_id),
  FOREIGN KEY (lote_id, data_concretagem)
    REFERENCES lotes (id, data_concretagem) ON DELETE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS lote_pecas_peca_data_uq
  ON lote_pecas (peca_id, data_concretagem);

-- Lote encerrado não recebe caminhão novo. A API confere ao encerrar; este
-- gatilho garante o outro lado direto no banco (FOR SHARE faz o
-- encerramento e a chegada de um caminhão se enfileirarem em vez de se
-- cruzarem).
CREATE OR REPLACE FUNCTION caminhoes_lote_em_andamento() RETURNS trigger AS $$
DECLARE
  situacao TEXT;
BEGIN
  IF NEW.lote_id IS NOT NULL THEN
    SELECT status INTO situacao FROM lotes WHERE id = NEW.lote_id FOR SHARE;
    IF situacao = 'encerrado' THEN
      RAISE EXCEPTION 'Lote encerrado não recebe caminhão'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS caminhoes_lote_em_andamento_tg ON caminhoes;
CREATE TRIGGER caminhoes_lote_em_andamento_tg
  BEFORE INSERT OR UPDATE OF lote_id ON caminhoes
  FOR EACH ROW EXECUTE FUNCTION caminhoes_lote_em_andamento();

-- ---------------------------------------------------------------------
-- Caminhão com os dados da nota de entrega (T07)
-- A nota é o documento que vem com a betoneira. Aqui o técnico da obra
-- registra o caminhão que chegou, ligado ao lote e ao pedido, e o app
-- compara a nota com o pedido antes de qualquer coisa descer.
--
-- Dois horários, de propósito separados:
--   primeiro_contato_em — quando o cimento encostou na água, lá na central.
--                         É dela que sai o prazo de descarga (T08). Tem de
--                         ser data e hora de verdade, nunca texto.
--   chegada_obra_em     — quando o caminhão chegou à obra.
-- (criado_em, que já existia, é só quando o registro foi gravado.)
--
-- A tabela caminhoes já existia (central, lote, placa, pedido, volume).
-- As linhas antigas ficam como estavam, sem nota, e fora da listagem.
-- ---------------------------------------------------------------------

ALTER TABLE caminhoes ADD COLUMN IF NOT EXISTS numero_nota TEXT;
ALTER TABLE caminhoes ADD COLUMN IF NOT EXISTS traco TEXT;
ALTER TABLE caminhoes ADD COLUMN IF NOT EXISTS consumo_cimento NUMERIC(7, 2) CHECK (consumo_cimento > 0);
ALTER TABLE caminhoes ADD COLUMN IF NOT EXISTS aditivos TEXT;
ALTER TABLE caminhoes ADD COLUMN IF NOT EXISTS aditivo_retardador BOOLEAN NOT NULL DEFAULT false;
-- Classe e fck como vêm escritos na nota (é com eles que se compara o pedido).
ALTER TABLE caminhoes ADD COLUMN IF NOT EXISTS classe_nota TEXT;
ALTER TABLE caminhoes ADD COLUMN IF NOT EXISTS fck_nota INTEGER CHECK (fck_nota > 0);
ALTER TABLE caminhoes ADD COLUMN IF NOT EXISTS primeiro_contato_em TIMESTAMPTZ;
ALTER TABLE caminhoes ADD COLUMN IF NOT EXISTS chegada_obra_em TIMESTAMPTZ;
ALTER TABLE caminhoes ADD COLUMN IF NOT EXISTS registrado_por INTEGER REFERENCES usuarios(id);

-- Número de nota não se repete para a mesma central (sem diferenciar
-- maiúscula de minúscula). Caminhões antigos, sem nota, não entram na regra.
CREATE UNIQUE INDEX IF NOT EXISTS caminhoes_central_nota_uq
  ON caminhoes (central_id, lower(numero_nota));

-- Caminhão com nota registrada tem a nota completa: lote, pedido, placa,
-- volume, traço, classe, fck e os DOIS horários. O próprio banco recusa
-- um registro de nota pela metade.
-- (Postgres não tem "ADD CONSTRAINT IF NOT EXISTS"; o bloco DO confere antes.)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'caminhoes_nota_completa') THEN
    ALTER TABLE caminhoes ADD CONSTRAINT caminhoes_nota_completa CHECK (
      numero_nota IS NULL OR (
        lote_id IS NOT NULL AND pedido_id IS NOT NULL AND placa IS NOT NULL
        AND volume IS NOT NULL AND traco IS NOT NULL AND classe_nota IS NOT NULL
        AND fck_nota IS NOT NULL AND primeiro_contato_em IS NOT NULL
        AND chegada_obra_em IS NOT NULL
      )
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'caminhoes_chegada_apos_contato') THEN
    ALTER TABLE caminhoes ADD CONSTRAINT caminhoes_chegada_apos_contato CHECK (
      chegada_obra_em IS NULL OR primeiro_contato_em IS NULL
      OR chegada_obra_em >= primeiro_contato_em
    );
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS caminhoes_lote_idx ON caminhoes (lote_id);

-- ---------------------------------------------------------------------
-- Prazo de descarga (T08)
-- A descarga tem de terminar dentro de um prazo contado do primeiro
-- contato do cimento com a água (não da chegada à obra). O prazo não é um
-- número escrito no código: vem desta configuração, por construtora, e é
-- maior quando o concreto leva aditivo retardador. Quem decide o valor do
-- prazo com retardador é a equipe, a partir da norma: enquanto ele não for
-- preenchido, vale o prazo normal.
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS configuracoes_prazo (
  construtora_id INTEGER PRIMARY KEY REFERENCES construtoras(id),
  -- Minutos, contados do primeiro contato do cimento com a água.
  prazo_descarga_minutos INTEGER NOT NULL DEFAULT 90
    CHECK (prazo_descarga_minutos > 0 AND prazo_descarga_minutos <= 1440),
  -- Prazo para concreto com aditivo retardador. Nulo = ainda não configurado.
  prazo_retardador_minutos INTEGER
    CHECK (prazo_retardador_minutos IS NULL OR (prazo_retardador_minutos > 0 AND prazo_retardador_minutos <= 1440)),
  -- Quantos minutos antes do fim o app começa a avisar.
  aviso_minutos INTEGER NOT NULL DEFAULT 15
    CHECK (aviso_minutos >= 0 AND aviso_minutos <= 1440),
  atualizado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (prazo_retardador_minutos IS NULL OR prazo_retardador_minutos >= prazo_descarga_minutos),
  CHECK (aviso_minutos <= prazo_descarga_minutos)
);

-- Toda construtora que já existe ganha a configuração padrão (as novas
-- ganham na primeira vez que a API precisa dela).
INSERT INTO configuracoes_prazo (construtora_id)
  SELECT id FROM construtoras ON CONFLICT (construtora_id) DO NOTHING;

-- Cada caminhão guarda o prazo que valia quando ele chegou: mudar a
-- configuração depois não vira um caminhão antigo "fora do prazo".
ALTER TABLE caminhoes ADD COLUMN IF NOT EXISTS prazo_minutos INTEGER CHECK (prazo_minutos > 0);
-- Quando a descarga começou e terminou. O técnico da obra registra as
-- horas de verdade (com fuso). A hora de fim é a que fecha a conta do
-- prazo de descarga (T08) e decide se ficou dentro ou fora.
ALTER TABLE caminhoes ADD COLUMN IF NOT EXISTS descarga_inicio_em TIMESTAMPTZ;
ALTER TABLE caminhoes ADD COLUMN IF NOT EXISTS descarga_fim_em TIMESTAMPTZ;
-- Volume efetivamente descarregado (pode ser menor que o da nota se não
-- saiu tudo). Quando preenchido, passa a ser o que soma no lote e no pedido.
ALTER TABLE caminhoes ADD COLUMN IF NOT EXISTS volume_efetivo NUMERIC(10, 2) CHECK (volume_efetivo > 0);
-- Gravado junto com o fim da descarga: terminou depois do prazo? Nulo
-- enquanto a descarga não terminou.
ALTER TABLE caminhoes ADD COLUMN IF NOT EXISTS fora_do_prazo BOOLEAN;

-- Caminhões com nota registrados antes desta história: recebem o prazo
-- que a configuração da construtora dá hoje para eles.
UPDATE caminhoes c
   SET prazo_minutos = CASE WHEN c.aditivo_retardador
                            THEN COALESCE(cf.prazo_retardador_minutos, cf.prazo_descarga_minutos)
                            ELSE cf.prazo_descarga_minutos END
  FROM lotes l
  JOIN configuracoes_prazo cf ON cf.construtora_id = l.construtora_id
 WHERE c.lote_id = l.id AND c.numero_nota IS NOT NULL AND c.prazo_minutos IS NULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'caminhoes_prazo_com_nota') THEN
    ALTER TABLE caminhoes ADD CONSTRAINT caminhoes_prazo_com_nota
      CHECK (numero_nota IS NULL OR prazo_minutos IS NOT NULL);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'caminhoes_descarga_coerente') THEN
    ALTER TABLE caminhoes ADD CONSTRAINT caminhoes_descarga_coerente
      CHECK ((descarga_fim_em IS NULL) = (fora_do_prazo IS NULL));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'caminhoes_descarga_inicio_fim') THEN
    ALTER TABLE caminhoes ADD CONSTRAINT caminhoes_descarga_inicio_fim
      CHECK (
        descarga_inicio_em IS NULL
        OR descarga_fim_em IS NULL
        OR descarga_fim_em >= descarga_inicio_em
      );
  END IF;
END $$;

-- Dados antigos (só descarga_fim_em preenchido): completa com início = fim e
-- volume_efetivo = volume da nota, para o CHECK de descarga completa passar.
UPDATE caminhoes
   SET descarga_inicio_em = descarga_fim_em,
       volume_efetivo = volume
 WHERE descarga_fim_em IS NOT NULL AND descarga_inicio_em IS NULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'caminhoes_descarga_completa') THEN
    ALTER TABLE caminhoes ADD CONSTRAINT caminhoes_descarga_completa
      CHECK (
        (descarga_fim_em IS NULL AND descarga_inicio_em IS NULL AND volume_efetivo IS NULL)
        OR (descarga_fim_em IS NOT NULL AND descarga_inicio_em IS NOT NULL AND volume_efetivo IS NOT NULL)
      );
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- Amostras e corpos de prova (moldagem na obra)
-- A amostra é retirada de um caminhão ACEITO. Dela se moldam dois corpos
-- de prova para cada idade de rompimento (padrão 7 e 28 dias). Dois por
-- idade formam o exemplar (T15): o maior valor entre os dois. Caminhão
-- recusado não aceita amostra.
-- ---------------------------------------------------------------------

ALTER TABLE caminhoes ADD COLUMN IF NOT EXISTS recusado BOOLEAN NOT NULL DEFAULT false;

-- Idades de rompimento configuráveis por construtora (padrão 7 e 28 dias).
CREATE TABLE IF NOT EXISTS configuracoes_idades (
  construtora_id INTEGER PRIMARY KEY REFERENCES construtoras(id),
  idades INTEGER[] NOT NULL DEFAULT ARRAY[7, 28],
  atualizado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (array_length(idades, 1) >= 1),
  CHECK (idades <@ ARRAY(SELECT generate_series(1, 365)))
);

INSERT INTO configuracoes_idades (construtora_id)
  SELECT id FROM construtoras ON CONFLICT (construtora_id) DO NOTHING;

CREATE TABLE IF NOT EXISTS amostras (
  id SERIAL PRIMARY KEY,
  caminhao_id INTEGER NOT NULL REFERENCES caminhoes(id),
  coletada_em TIMESTAMPTZ NOT NULL,
  registrada_por INTEGER REFERENCES usuarios(id),
  criado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (caminhao_id)  -- no máximo uma amostra por caminhão
);

CREATE INDEX IF NOT EXISTS amostras_caminhao_idx ON amostras (caminhao_id);

CREATE TABLE IF NOT EXISTS corpos_prova (
  id SERIAL PRIMARY KEY,
  amostra_id INTEGER NOT NULL REFERENCES amostras(id) ON DELETE CASCADE,
  idade INTEGER NOT NULL CHECK (idade > 0 AND idade <= 365),
  resultado NUMERIC(7, 2) CHECK (resultado IS NULL OR resultado > 0),
  criado_em TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS corpos_prova_amostra_idx ON corpos_prova (amostra_id);

-- ---------------------------------------------------------------------
-- Identificação única do corpo de prova (cadeia até a peça)
-- Cada CP recebe um código gerado pelo sistema, único na construtora.
-- Por ele se chega a: amostra → caminhão/nota → lote → peça → pavimento → obra.
-- ---------------------------------------------------------------------

ALTER TABLE corpos_prova ADD COLUMN IF NOT EXISTS identificacao TEXT;

-- Sequência por construtora para gerar CP-AAAA-NNNNN
CREATE TABLE IF NOT EXISTS sequencias_corpo_prova (
  construtora_id INTEGER PRIMARY KEY REFERENCES construtoras(id),
  ultimo INTEGER NOT NULL DEFAULT 0 CHECK (ultimo >= 0)
);

INSERT INTO sequencias_corpo_prova (construtora_id)
  SELECT id FROM construtoras ON CONFLICT (construtora_id) DO NOTHING;

-- Preenche identificação em CPs antigos (sem código) de forma determinística.
UPDATE corpos_prova cp
   SET identificacao = 'CP-LEGACY-' || cp.id
 WHERE cp.identificacao IS NULL;

ALTER TABLE corpos_prova ALTER COLUMN identificacao SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS corpos_prova_identificacao_uq
  ON corpos_prova (lower(identificacao));

-- ---------------------------------------------------------------------
-- Ciclo do corpo de prova: cura na obra → remessa → laboratório
-- Máquina de estados:
--   moldado → em_cura → em_remessa → no_laboratorio → rompido
--                  ↘ descartado (de moldado/em_cura; motivo obrigatório)
-- Corpo descartado não some: fica com situação e motivo.
-- Um CP só entra em uma remessa por vez (remessa_itens exclusivos enquanto
-- a remessa não foi cancelada).
-- ---------------------------------------------------------------------

ALTER TABLE corpos_prova ADD COLUMN IF NOT EXISTS situacao TEXT NOT NULL DEFAULT 'moldado'
  CHECK (situacao IN (
    'moldado', 'em_cura', 'em_remessa', 'no_laboratorio', 'rompido', 'descartado'
  ));
ALTER TABLE corpos_prova ADD COLUMN IF NOT EXISTS cura_inicio_em TIMESTAMPTZ;
ALTER TABLE corpos_prova ADD COLUMN IF NOT EXISTS descartado_em TIMESTAMPTZ;
ALTER TABLE corpos_prova ADD COLUMN IF NOT EXISTS motivo_descarte TEXT;

-- Dados antigos: se já tem resultado, trata como rompido; senão moldado.
UPDATE corpos_prova SET situacao = 'rompido' WHERE resultado IS NOT NULL AND situacao = 'moldado';

CREATE TABLE IF NOT EXISTS remessas (
  id SERIAL PRIMARY KEY,
  construtora_id INTEGER NOT NULL REFERENCES construtoras(id),
  laboratorio_id INTEGER NOT NULL REFERENCES laboratorios(id),
  enviada_em TIMESTAMPTZ NOT NULL,
  registrada_por INTEGER REFERENCES usuarios(id),
  status TEXT NOT NULL DEFAULT 'enviada'
    CHECK (status IN ('enviada', 'recebida', 'cancelada')),
  recebida_em TIMESTAMPTZ,
  criado_em TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS remessas_construtora_idx ON remessas (construtora_id);
CREATE INDEX IF NOT EXISTS remessas_laboratorio_idx ON remessas (laboratorio_id);

CREATE TABLE IF NOT EXISTS remessa_itens (
  remessa_id INTEGER NOT NULL REFERENCES remessas(id) ON DELETE CASCADE,
  corpo_prova_id INTEGER NOT NULL REFERENCES corpos_prova(id),
  PRIMARY KEY (remessa_id, corpo_prova_id)
);

CREATE INDEX IF NOT EXISTS remessa_itens_corpo_idx ON remessa_itens (corpo_prova_id);

-- Um corpo de prova só entra em uma remessa ativa por vez (regra na API e no gatilho).
CREATE OR REPLACE FUNCTION remessa_itens_um_ativo() RETURNS trigger AS $$
DECLARE
  outra INTEGER;
BEGIN
  SELECT ri.remessa_id INTO outra
    FROM remessa_itens ri
    JOIN remessas r ON r.id = ri.remessa_id
   WHERE ri.corpo_prova_id = NEW.corpo_prova_id
     AND r.status IN ('enviada', 'recebida')
     AND ri.remessa_id IS DISTINCT FROM NEW.remessa_id
   LIMIT 1;
  IF outra IS NOT NULL THEN
    RAISE EXCEPTION 'Corpo de prova já está em outra remessa ativa (%).', outra
      USING ERRCODE = 'unique_violation';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS remessa_itens_um_ativo_tg ON remessa_itens;
CREATE TRIGGER remessa_itens_um_ativo_tg
  BEFORE INSERT OR UPDATE OF corpo_prova_id, remessa_id ON remessa_itens
  FOR EACH ROW EXECUTE FUNCTION remessa_itens_um_ativo();

-- ---------------------------------------------------------------------
-- Resultados de rompimento (lançamento pelo laboratório)
-- Cada lançamento fica registrado: data do rompimento, idade real em dias
-- (calculada a partir da moldagem/coleta, sem arredondar a idade nominal)
-- e resistência em MPa. Correção = NOVO lançamento com motivo, sem apagar
-- o anterior. O campo corpos_prova.resultado guarda o valor vigente.
-- ---------------------------------------------------------------------

ALTER TABLE corpos_prova ADD COLUMN IF NOT EXISTS moldado_em TIMESTAMPTZ;
-- moldado_em: data de referência da idade real. Preenche com criado_em se nulo.
UPDATE corpos_prova SET moldado_em = criado_em WHERE moldado_em IS NULL;
ALTER TABLE corpos_prova ALTER COLUMN moldado_em SET DEFAULT now();

-- Também permite usar a coleta da amostra como referência quando fizer sentido.
-- A API calcula idade_real = dias entre moldado_em (ou amostra.coletada_em) e rompido_em.

CREATE TABLE IF NOT EXISTS resultados_rompimento (
  id SERIAL PRIMARY KEY,
  corpo_prova_id INTEGER NOT NULL REFERENCES corpos_prova(id),
  rompido_em TIMESTAMPTZ NOT NULL,
  idade_real_dias NUMERIC(8, 2) NOT NULL CHECK (idade_real_dias > 0),
  resistencia_mpa NUMERIC(7, 2) NOT NULL CHECK (resistencia_mpa > 0),
  -- Idade nominal do CP (7, 28...) só para referência; a que vale é a real.
  idade_nominal INTEGER,
  motivo_correcao TEXT,
  -- null no primeiro lançamento; preenchido quando é correção de um anterior
  corrige_resultado_id INTEGER REFERENCES resultados_rompimento(id),
  lancado_por INTEGER REFERENCES usuarios(id),
  criado_em TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS resultados_rompimento_corpo_idx
  ON resultados_rompimento (corpo_prova_id, criado_em DESC);

-- ---------------------------------------------------------------------
-- Aceitação do lote (fck,est — NBR 12655 amostragem parcial)
-- Coeficiente Ψ6 e condição de preparo vêm de cadastro, não do código.
-- Lote reprovado exige registro da decisão do engenheiro.
-- ---------------------------------------------------------------------

-- Ψ6 por condição de preparo e número de exemplares (Tabela 8 NBR 12655).
CREATE TABLE IF NOT EXISTS coeficientes_psi6 (
  condicao_preparo TEXT NOT NULL CHECK (condicao_preparo IN ('A', 'B', 'C')),
  n_exemplares INTEGER NOT NULL CHECK (n_exemplares >= 2 AND n_exemplares <= 16),
  psi6 NUMERIC(4, 2) NOT NULL CHECK (psi6 > 0),
  PRIMARY KEY (condicao_preparo, n_exemplares)
);

-- Valores da Tabela 8 (B e C compartilham a mesma linha na norma).
INSERT INTO coeficientes_psi6 (condicao_preparo, n_exemplares, psi6) VALUES
  ('A', 2, 0.82), ('A', 3, 0.86), ('A', 4, 0.89), ('A', 5, 0.91),
  ('A', 6, 0.92), ('A', 7, 0.94), ('A', 8, 0.95), ('A', 10, 0.97),
  ('A', 12, 0.99), ('A', 14, 1.00), ('A', 16, 1.02),
  ('B', 2, 0.75), ('B', 3, 0.80), ('B', 4, 0.84), ('B', 5, 0.87),
  ('B', 6, 0.89), ('B', 7, 0.91), ('B', 8, 0.93), ('B', 10, 0.96),
  ('B', 12, 0.98), ('B', 14, 1.00), ('B', 16, 1.02),
  ('C', 2, 0.75), ('C', 3, 0.80), ('C', 4, 0.84), ('C', 5, 0.87),
  ('C', 6, 0.89), ('C', 7, 0.91), ('C', 8, 0.93), ('C', 10, 0.96),
  ('C', 12, 0.98), ('C', 14, 1.00), ('C', 16, 1.02)
ON CONFLICT (condicao_preparo, n_exemplares) DO UPDATE SET psi6 = EXCLUDED.psi6;

ALTER TABLE lotes ADD COLUMN IF NOT EXISTS condicao_preparo TEXT
  CHECK (condicao_preparo IS NULL OR condicao_preparo IN ('A', 'B', 'C'));
ALTER TABLE lotes ADD COLUMN IF NOT EXISTS fck_est NUMERIC(8, 2);
ALTER TABLE lotes ADD COLUMN IF NOT EXISTS situacao_aceitacao TEXT
  CHECK (situacao_aceitacao IS NULL OR situacao_aceitacao IN ('aceito', 'reprovado', 'aguardando'));
ALTER TABLE lotes ADD COLUMN IF NOT EXISTS aceitacao_em TIMESTAMPTZ;
ALTER TABLE lotes ADD COLUMN IF NOT EXISTS aceitacao_por INTEGER REFERENCES usuarios(id);

-- Decisão após reprovação (software não condena estrutura).
CREATE TABLE IF NOT EXISTS decisoes_lote (
  id SERIAL PRIMARY KEY,
  lote_id INTEGER NOT NULL REFERENCES lotes(id),
  decisao TEXT NOT NULL CHECK (decisao IN (
    'revisao_projeto', 'extracao_testemunhos', 'prova_de_carga', 'outra'
  )),
  detalhe TEXT,
  registrada_por INTEGER REFERENCES usuarios(id),
  registrada_em TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS decisoes_lote_lote_idx ON decisoes_lote (lote_id);

-- ---------------------------------------------------------------------
-- Idempotência de operações offline (fila do aparelho)
-- Cada lançamento no celular nasce com client_id único. Reenviar o
-- mesmo client_id devolve a mesma resposta e não duplica no servidor.
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS operacoes_cliente (
  client_id TEXT PRIMARY KEY,
  construtora_id INTEGER NOT NULL REFERENCES construtoras(id),
  usuario_id INTEGER REFERENCES usuarios(id),
  tipo TEXT NOT NULL,
  resource_tipo TEXT,
  resource_id INTEGER,
  status_http INTEGER NOT NULL,
  resposta JSONB NOT NULL,
  criado_em TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS operacoes_cliente_construtora_idx
  ON operacoes_cliente (construtora_id, criado_em DESC);

-- Ensaio de abatimento no caminhão (para o relatório de controle).
ALTER TABLE caminhoes ADD COLUMN IF NOT EXISTS abatimento_mm INTEGER CHECK (abatimento_mm IS NULL OR abatimento_mm > 0);
ALTER TABLE caminhoes ADD COLUMN IF NOT EXISTS abatimento_ok BOOLEAN;
