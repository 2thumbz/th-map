INSERT INTO nodes (id, node_name, latitude, longitude) VALUES
  (1, 'Indeogwon', 37.4017, 126.9767),
  (2, 'Node 2', 37.4050, 126.9800),
  (3, 'Node 3', 37.4100, 126.9850),
  (4, 'Destination', 37.4150, 126.9900)
ON CONFLICT (id) DO UPDATE SET
  node_name = EXCLUDED.node_name,
  latitude = EXCLUDED.latitude,
  longitude = EXCLUDED.longitude;

INSERT INTO links (id, start_node, end_node, weight, road_name) VALUES
  (101, 1, 2, 500, 'Road A'),
  (102, 2, 3, 600, 'Road B'),
  (103, 3, 4, 700, 'Road C')
ON CONFLICT (id) DO UPDATE SET
  start_node = EXCLUDED.start_node,
  end_node = EXCLUDED.end_node,
  weight = EXCLUDED.weight,
  road_name = EXCLUDED.road_name;
