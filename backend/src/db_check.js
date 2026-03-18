require('dotenv').config();
const { Pool } = require('pg');

async function main() {
  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  try {
    const ping = await pool.query('select 1 as ok');
    console.log('db_ping', ping.rows);

    const tables = await pool.query(
      "select table_name from information_schema.tables where table_schema='public' and table_name in ('nodes','links') order by table_name"
    );
    console.log('tables', tables.rows);
  } catch (e) {
    console.error('db_error', e.message);
    process.exitCode = 1;
  } finally {
    await pool.end();
  }
}

main();
