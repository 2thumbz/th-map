CREATE TABLE IF NOT EXISTS nodes (
  id INTEGER PRIMARY KEY,
  node_name TEXT,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL
);

CREATE TABLE IF NOT EXISTS links (
  id INTEGER PRIMARY KEY,
  start_node INTEGER NOT NULL REFERENCES nodes(id),
  end_node INTEGER NOT NULL REFERENCES nodes(id),
  weight DOUBLE PRECISION NOT NULL,
  road_name TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS TB_TURNINFO (
  id BIGSERIAL PRIMARY KEY,
  prev_link_id INTEGER REFERENCES links(id) ON DELETE RESTRICT,
  next_link_id INTEGER REFERENCES links(id) ON DELETE RESTRICT,
  turn_type TEXT NOT NULL,
  turn_desc TEXT
);

CREATE INDEX IF NOT EXISTS idx_links_start_node ON links(start_node);
CREATE INDEX IF NOT EXISTS idx_links_end_node ON links(end_node);
CREATE INDEX IF NOT EXISTS idx_nodes_node_name ON nodes(node_name);
CREATE INDEX IF NOT EXISTS idx_turninfo_prev_next ON TB_TURNINFO(prev_link_id, next_link_id);
CREATE INDEX IF NOT EXISTS idx_turninfo_type ON TB_TURNINFO(turn_type);
CREATE UNIQUE INDEX IF NOT EXISTS uq_turninfo_transition
ON TB_TURNINFO(prev_link_id, next_link_id)
WHERE prev_link_id IS NOT NULL AND next_link_id IS NOT NULL;
