require('dotenv').config();

module.exports = {
  JWT_SECRET: process.env.JWT_SECRET || 'troque-este-segredo-em-producao',
  PORT: process.env.PORT || 3000,
};
