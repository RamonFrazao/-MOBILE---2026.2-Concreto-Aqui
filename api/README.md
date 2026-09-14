# Concreto Aqui — API

API mínima que resolve a T01 de verdade: login com senha cifrada no
servidor, erro genérico, e recusa de dados de outra construtora.
O restante do domínio (caminhão, amostra, corpo de prova) ainda mora no
mock do app Flutter — entra aqui na E2.

## Setup

1. Tenha um PostgreSQL rodando localmente (ou em algum serviço).
2. Crie o banco:
   ```
   createdb concreto_aqui
   ```
3. Copie `.env.example` para `.env` e ajuste `DATABASE_URL` com seu usuário/senha.
4. Rode o schema:
   ```
   psql -d concreto_aqui -f sql/schema.sql
   ```
5. Instale as dependências e rode o seed (cria as duas construtoras e os três usuários de teste, com senha já cifrada):
   ```
   npm install
   npm run seed
   ```
6. Suba a API:
   ```
   npm start
   ```
   Ela sobe em `http://localhost:3000` por padrão.

## Rotas

- `POST /auth/login` — body `{ "username": "...", "senha": "..." }`.
  Sucesso: `{ token, usuario: { username, perfil, nome, construtora } }`.
  Falha: sempre `401 { erro: "Usuário ou senha inválidos." }`, usuário
  exista ou não.
- `GET /lotes/:codigo` — precisa de `Authorization: Bearer <token>`.
  - Lote da própria construtora → `200` com os dados do lote.
  - Lote de outra construtora → `403 { erro: "Acesso negado: este lote
    pertence a outra construtora." }`.
  - Lote inexistente → `404`.

## Perfis de teste (após o seed)

| Perfil       | Usuário       | Senha | Construtora              |
|--------------|---------------|-------|---------------------------|
| Construtora  | `construtora` | 1234  | Construtora Bom Conselho |
| Obra         | `tecnico`     | 1234  | Construtora Bom Conselho |
| Laboratório  | `lab`         | 1234  | Construtora Bom Conselho |

O lote `19/07` pertence à "Construtora Nordeste" (não tem usuário próprio,
existe só para o teste de recusa) — buscar `19/07` logado como
`construtora` deve dar 403.

## Rodando o app Flutter contra esta API

- **Emulador Android**: use `http://10.0.2.2:3000` (o app já vem
  configurado assim por padrão).
- **Chrome / Windows desktop / iOS simulator**: use
  `flutter run --dart-define=API_BASE_URL=http://localhost:3000`.
- **Celular físico**: descubra o IP da sua máquina na rede local (ex.:
  `192.168.0.10`) e rode
  `flutter run --dart-define=API_BASE_URL=http://192.168.0.10:3000` — o
  celular precisa estar na mesma rede Wi-Fi.
