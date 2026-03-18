require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { pool } = require('./db');

const app = express();
const port = Number(process.env.PORT || 3000);

app.use(cors());
app.use(express.json());

app.get('/health', async (_req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ ok: true });
  } catch (error) {
    res.status(500).json({ ok: false, error: 'database_unreachable' });
  }
});

app.get('/api/nodes', async (_req, res) => {
  try {
    const result = await pool.query(
      `
      SELECT
        n.id,
        COALESCE(NULLIF(n."NODE_NAME", ''), n."NODE_ID") AS name,
        ST_Y(ST_Transform(n.geom::geometry, 4326)) AS latitude,
        ST_X(ST_Transform(n.geom::geometry, 4326)) AS longitude
      FROM public."TB_AY_MOCT_NODE" n
      WHERE n.geom IS NOT NULL
      ORDER BY n.id ASC
      `
    );
    res.json(result.rows);
  } catch (error) {
    res.status(500).json({ error: 'failed_to_fetch_nodes' });
  }
});

app.get('/api/links', async (_req, res) => {
  try {
    const result = await pool.query(
      `
      SELECT
        l.id,
        sn.id AS start_node,
        tn.id AS end_node,
        COALESCE(l."LENGTH", 1) AS weight,
        COALESCE(NULLIF(l."ROAD_NAME", ''), l."LINK_ID") AS road_name
      FROM public."TB_AY_MOCT_LINK" l
      JOIN public."TB_AY_MOCT_NODE" sn
        ON sn."NODE_ID" = l."F_NODE"
      JOIN public."TB_AY_MOCT_NODE" tn
        ON tn."NODE_ID" = l."T_NODE"
      ORDER BY l.id ASC
      `
    );
    res.json(result.rows);
  } catch (error) {
    res.status(500).json({ error: 'failed_to_fetch_links' });
  }
});

app.get('/api/nodes/search', async (req, res) => {
  const q = String(req.query.q || '').trim();
  if (!q) {
    return res.json([]);
  }

  const idCandidate = Number.parseInt(q, 10);
  const hasIdCandidate = Number.isFinite(idCandidate);

  try {
    const result = await pool.query(
      `
      SELECT
        n.id,
        COALESCE(NULLIF(n."NODE_NAME", ''), n."NODE_ID") AS name,
        ST_Y(ST_Transform(n.geom::geometry, 4326)) AS latitude,
        ST_X(ST_Transform(n.geom::geometry, 4326)) AS longitude
      FROM public."TB_AY_MOCT_NODE" n
      WHERE ($1::int IS NOT NULL AND id = $1)
         OR (n."NODE_NAME" IS NOT NULL AND n."NODE_NAME" ILIKE $2)
         OR (n."NODE_ID" IS NOT NULL AND n."NODE_ID" ILIKE $2)
      ORDER BY id ASC
      LIMIT 30
      `,
      [hasIdCandidate ? idCandidate : null, `%${q}%`]
    );
    return res.json(result.rows);
  } catch (error) {
    return res.status(500).json({ error: 'failed_to_search_nodes' });
  }
});

app.get('/api/nodes/nearest', async (req, res) => {
  const lat = Number(req.query.lat);
  const lng = Number(req.query.lng);

  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    return res.status(400).json({ error: 'invalid_lat_lng' });
  }

  try {
    const result = await pool.query(
      `
      SELECT
        n.id,
        COALESCE(NULLIF(n."NODE_NAME", ''), n."NODE_ID") AS name,
        ST_Y(ST_Transform(n.geom::geometry, 4326)) AS latitude,
        ST_X(ST_Transform(n.geom::geometry, 4326)) AS longitude
      FROM public."TB_AY_MOCT_NODE" n
      WHERE n.geom IS NOT NULL
      ORDER BY
        POWER(ST_Y(ST_Transform(n.geom::geometry, 4326)) - $1, 2) +
        POWER(ST_X(ST_Transform(n.geom::geometry, 4326)) - $2, 2)
      LIMIT 1
      `,
      [lat, lng]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'node_not_found' });
    }

    return res.json(result.rows[0]);
  } catch (error) {
    return res.status(500).json({ error: 'failed_to_find_nearest_node' });
  }
});

app.post('/api/nodes', async (req, res) => {
  const { id, node_id = null, name = null, latitude, longitude } = req.body || {};

  if (!Number.isInteger(id) || !Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    return res.status(400).json({ error: 'invalid_node_payload' });
  }

  try {
    await pool.query(
      `
      INSERT INTO public."TB_AY_MOCT_NODE" (id, "NODE_ID", "NODE_NAME", geom)
      VALUES ($1, COALESCE($2, $1::text), $3, ST_SetSRID(ST_MakePoint($4, $5), 4326))
      ON CONFLICT (id)
      DO UPDATE SET
        "NODE_ID" = EXCLUDED."NODE_ID",
        "NODE_NAME" = EXCLUDED."NODE_NAME",
        geom = EXCLUDED.geom
      `,
      [id, node_id, name, longitude, latitude]
    );

    return res.status(201).json({ ok: true });
  } catch (error) {
    return res.status(500).json({ error: 'failed_to_upsert_node' });
  }
});

app.post('/api/links', async (req, res) => {
  const { id, start_node, end_node, weight, road_name, link_id = null } = req.body || {};

  if (
    !Number.isInteger(id) ||
    !Number.isInteger(start_node) ||
    !Number.isInteger(end_node) ||
    !Number.isFinite(weight) ||
    typeof road_name !== 'string' ||
    !road_name.trim()
  ) {
    return res.status(400).json({ error: 'invalid_link_payload' });
  }

  try {
    const result = await pool.query(
      `
      WITH src AS (
        SELECT "NODE_ID" AS node_id
        FROM public."TB_AY_MOCT_NODE"
        WHERE id = $2
      ),
      dst AS (
        SELECT "NODE_ID" AS node_id
        FROM public."TB_AY_MOCT_NODE"
        WHERE id = $3
      )
      INSERT INTO public."TB_AY_MOCT_LINK" (id, "LINK_ID", "F_NODE", "T_NODE", "LENGTH", "ROAD_NAME")
      SELECT
        $1,
        COALESCE($6, $1::text),
        src.node_id,
        dst.node_id,
        $4,
        $5
      FROM src, dst
      ON CONFLICT (id)
      DO UPDATE SET
        "LINK_ID" = EXCLUDED."LINK_ID",
        "F_NODE" = EXCLUDED."F_NODE",
        "T_NODE" = EXCLUDED."T_NODE",
        "LENGTH" = EXCLUDED."LENGTH",
        "ROAD_NAME" = EXCLUDED."ROAD_NAME"
      `,
      [id, start_node, end_node, weight, road_name.trim(), link_id]
    );

    if (result.rowCount === 0) {
      return res.status(400).json({ error: 'start_or_end_node_not_found' });
    }

    return res.status(201).json({ ok: true });
  } catch (error) {
    return res.status(500).json({ error: 'failed_to_upsert_link' });
  }
});

app.listen(port, () => {
  console.log(`Nav backend listening on http://localhost:${port}`);
});
