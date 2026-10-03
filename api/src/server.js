require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { PORT } = require('./config');
const authRoutes = require('./routes/auth');
const lotesRoutes = require('./routes/lotes');
const obrasRoutes = require('./routes/obras');
const centraisRoutes = require('./routes/centrais');
const laboratoriosRoutes = require('./routes/laboratorios');

const app = express();
app.use(cors());
app.use(express.json());

app.use('/auth', authRoutes);
app.use('/lotes', lotesRoutes);
app.use('/obras', obrasRoutes);
app.use('/centrais', centraisRoutes);
app.use('/laboratorios', laboratoriosRoutes);

app.get('/', (req, res) => res.json({ ok: true, servico: 'Concreto Aqui API' }));

// Rota que não existe: resposta em JSON, como todas as outras.
app.use((req, res) => {
  res.status(404).json({ erro: 'Rota não encontrada.' });
});

// Último recurso para erros que o Express captura sozinho (por exemplo,
// JSON malformado no corpo). Sem isto, o Express devolve uma página HTML
// com o stack trace e os caminhos de pasta do servidor.
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  if (err.type === 'entity.parse.failed') {
    return res.status(400).json({ erro: 'Corpo da requisição inválido (JSON malformado).' });
  }
  console.error(err);
  res.status(500).json({ erro: 'Erro interno.' });
});

app.listen(PORT, () => console.log(`API do Concreto Aqui rodando na porta ${PORT}`));
