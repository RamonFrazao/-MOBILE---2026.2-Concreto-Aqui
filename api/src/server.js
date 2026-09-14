require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { PORT } = require('./config');
const authRoutes = require('./routes/auth');
const lotesRoutes = require('./routes/lotes');

const app = express();
app.use(cors());
app.use(express.json());

app.use('/auth', authRoutes);
app.use('/lotes', lotesRoutes);

app.get('/', (req, res) => res.json({ ok: true, servico: 'Concreto Aqui API' }));

app.listen(PORT, () => console.log(`API do Concreto Aqui rodando na porta ${PORT}`));
