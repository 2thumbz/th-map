require('dotenv').config();
const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');

async function main() {
  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  try {
    const schemaSql = fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8');
    const seedSql = fs.readFileSync(path.join(__dirname, 'seed.sql'), 'utf8');

    await pool.query(schemaSql);
    await pool.query(seedSql);

    console.log('db_init_success');
  } catch (e) {
    console.error('db_init_error', e.message);
    process.exitCode = 1;
  } finally {
    await pool.end();
  }
}

main();
