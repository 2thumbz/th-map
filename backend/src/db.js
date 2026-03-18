const { Pool } = require('pg');

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) {
  throw new Error('DATABASE_URL is required. Set it in backend/.env');
}

const pool = new Pool({
  connectionString: databaseUrl,
});

module.exports = { pool };
