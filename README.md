# Concreto Aqui — projeto completo

Duas pastas:

- **`api/`** — API em Node + Express + PostgreSQL. Resolve a T01 de
  verdade: login com senha cifrada (bcrypt), erro genérico, token de
  sessão (JWT) e a recusa de dados de outra construtora.
- **`concreto_aqui/`** — app Flutter. Fala com a API para login e para a
  busca de lote por código; o restante das telas (obras, pedidos,
  moldagem, laboratório etc.) ainda roda sobre dados mock em memória —
  isso é trabalho de E2/E3, documentado no README de dentro da pasta.

## Ordem para rodar

1. Suba a API primeiro — siga `api/README.md` (criar o banco, rodar o
   schema, rodar o seed, `npm start`).
2. Depois rode o app Flutter — siga `concreto_aqui/README.md`.

## Perfis de teste (após o seed da API)

| Perfil       | Usuário       | Senha |
|--------------|---------------|-------|
| Construtora  | `construtora` | 1234  |
| Obra         | `tecnico`     | 1234  |
| Laboratório  | `lab`         | 1234  |

Para testar a recusa entre construtoras: logado como `construtora`, na
tela "Pedidos e lotes", busque o código `19/07` (lote de outra
construtora, criado só para esse teste) — a API responde `403 Acesso
negado`.

Um protótipo navegável em HTML das mesmas telas (usado para validar o
fluxo na E1, antes da API existir) está em
`concreto_aqui/concreto-aqui-prototipo.html`.
