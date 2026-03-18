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

CREATE INDEX IF NOT EXISTS idx_links_start_node ON links(start_node);
CREATE INDEX IF NOT EXISTS idx_links_end_node ON links(end_node);
CREATE INDEX IF NOT EXISTS idx_nodes_node_name ON nodes(node_name);
