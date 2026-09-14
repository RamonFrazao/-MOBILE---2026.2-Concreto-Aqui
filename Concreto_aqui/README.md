# Concreto Aqui

Controle tecnológico do concreto — do caminhão que chega à aceitação do lote.
Projeto integrador · Flutter + PostgreSQL · UAST · Semestre 2026.2

## Como abrir no VS Code

1. Tenha o Flutter SDK instalado (`flutter doctor` sem erros).
2. Suba a API primeiro — ver `../api/README.md` (precisa estar no ar para o login funcionar).
3. Abra esta pasta (`concreto_aqui/`) no VS Code com a extensão **Flutter** instalada.
4. No terminal:
   ```
   flutter pub get
   flutter run
   ```
   Em emulador Android o endereço padrão da API (`http://10.0.2.2:3000`) já funciona sem configurar nada.
   Em Chrome, Windows/desktop ou celular físico, veja `../api/README.md` para o `--dart-define` certo.
5. Faça login com um dos perfis de teste (veja abaixo).

## O que já está implementado

- **Login (tarefa T01) — resolvida de ponta a ponta**, ver `../api/` +
  `lib/services/`:
  - Login validado por um serviço abstrato (`AuthService`). A implementação
    real (`ApiAuthService`) chama a API (`POST /auth/login`), que confere a
    senha cifrada com bcrypt no servidor. Existe também um `MockAuthService`
    só para navegar pelas telas sem a API no ar — trocar de um para o outro é
    uma linha em `login_screen.dart`.
  - Erro de login sempre genérico (`Usuário ou senha inválidos.`), tanto na
    API quanto no mock, sem revelar se o usuário existe ou se foi a senha.
  - Cada perfil abre em telas diferentes: construtora, obra, laboratório
    (ver `lib/screens/`).
  - O perfil de laboratório só enxerga a tela de lançamento de resultado —
    não existem rotas para pedido, lote ou aceitação nesse perfil.
  - `lib/services/lote_repository.dart` busca o lote na API de verdade
    (`GET /lotes/:codigo`); é o servidor (`api/src/routes/lotes.js`) quem
    recusa com `403` um lote de outra construtora, comparando o dono do
    dado com a construtora do token — não é mais uma simulação local.
  - Sessão persistida no armazenamento seguro do aparelho
    (`flutter_secure_storage`, ver `lib/services/session.dart`): fecha e
    abre o app de novo e continua logado, até apertar "Sair".

- **Perfis e telas** (mock de dados em `lib/data/mock_db.dart`, tudo em memória):
  - Construtora: obras/peças, centrais/laboratórios, classes, pedidos/lotes
    (com busca por código demonstrando a recusa entre construtoras),
    aceitação de lote com cálculo do `fck,est`.
  - Obra: recebimento do caminhão com a nota, janela de 90 minutos com
    contador regressivo, ensaio de abatimento (slump) com aceite/recusa,
    moldagem dos corpos de prova, envio ao laboratório.
  - Laboratório: lista de corpos de prova pendentes, lançamento do resultado
    do rompimento.
  - Regras de domínio (`lib/models/domain_models.dart`): exemplar = maior
    valor entre os dois corpos da mesma idade; `fck,est` calculado pela regra
    de amostragem parcial (versão simplificada, documentar a regra completa
    da NBR 12655 na apresentação).

## O que falta (E2 / E3)

- Levar o restante do domínio para a API/Postgres (obras, peças, classes,
  pedidos, caminhão, amostra, corpo de prova) — hoje só usuários, construtoras,
  classes e lotes moram no banco; o resto ainda é `MockDb` local.
- Unificar a tela de detalhe do lote (`LoteDetalheScreen`) com os dados que
  vêm da API, hoje ela só lê do mock.
- Fila de sincronização local para funcionar sem rede (concretagem em
  subsolo), sincronizando ao reconectar.
- Relatórios finais.

## Perfis de teste

| Perfil       | Usuário      | Senha |
|--------------|--------------|-------|
| Construtora  | `construtora`| 1234  |
| Obra         | `tecnico`    | 1234  |
| Laboratório  | `lab`        | 1234  |

## Estrutura

```
lib/
  main.dart
  theme/app_theme.dart
  models/domain_models.dart
  data/mock_db.dart
  services/auth_service.dart
  services/session.dart
  widgets/shared_widgets.dart
  screens/login_screen.dart
  screens/construtora/construtora_screens.dart
  screens/obra/obra_screens.dart
  screens/laboratorio/laboratorio_screens.dart
```

Um protótipo navegável em HTML das mesmas telas (usado para validar o fluxo
na E1) está no arquivo `concreto-aqui-prototipo.html`, na mesma pasta deste
projeto.
