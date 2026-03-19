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

INSERT INTO TB_TURNINFO (prev_link_id, next_link_id, turn_type, turn_desc)
SELECT NULL, NULL, '001', '비보호회전'
WHERE NOT EXISTS (
  SELECT 1 FROM TB_TURNINFO
  WHERE prev_link_id IS NULL AND next_link_id IS NULL AND turn_type = '001'
);

INSERT INTO TB_TURNINFO (prev_link_id, next_link_id, turn_type, turn_desc)
SELECT NULL, NULL, '002', '버스만회전'
WHERE NOT EXISTS (
  SELECT 1 FROM TB_TURNINFO
  WHERE prev_link_id IS NULL AND next_link_id IS NULL AND turn_type = '002'
);

INSERT INTO TB_TURNINFO (prev_link_id, next_link_id, turn_type, turn_desc)
SELECT NULL, NULL, '003', '회전금지'
WHERE NOT EXISTS (
  SELECT 1 FROM TB_TURNINFO
  WHERE prev_link_id IS NULL AND next_link_id IS NULL AND turn_type = '003'
);

INSERT INTO TB_TURNINFO (prev_link_id, next_link_id, turn_type, turn_desc)
SELECT NULL, NULL, '011', 'U-TURN'
WHERE NOT EXISTS (
  SELECT 1 FROM TB_TURNINFO
  WHERE prev_link_id IS NULL AND next_link_id IS NULL AND turn_type = '011'
);

INSERT INTO TB_TURNINFO (prev_link_id, next_link_id, turn_type, turn_desc)
SELECT NULL, NULL, '012', 'P-TURN'
WHERE NOT EXISTS (
  SELECT 1 FROM TB_TURNINFO
  WHERE prev_link_id IS NULL AND next_link_id IS NULL AND turn_type = '012'
);

INSERT INTO TB_TURNINFO (prev_link_id, next_link_id, turn_type, turn_desc)
SELECT NULL, NULL, '101', '좌회전금지'
WHERE NOT EXISTS (
  SELECT 1 FROM TB_TURNINFO
  WHERE prev_link_id IS NULL AND next_link_id IS NULL AND turn_type = '101'
);

INSERT INTO TB_TURNINFO (prev_link_id, next_link_id, turn_type, turn_desc)
SELECT NULL, NULL, '102', '직진금지'
WHERE NOT EXISTS (
  SELECT 1 FROM TB_TURNINFO
  WHERE prev_link_id IS NULL AND next_link_id IS NULL AND turn_type = '102'
);

INSERT INTO TB_TURNINFO (prev_link_id, next_link_id, turn_type, turn_desc)
SELECT NULL, NULL, '103', '우회전금지'
WHERE NOT EXISTS (
  SELECT 1 FROM TB_TURNINFO
  WHERE prev_link_id IS NULL AND next_link_id IS NULL AND turn_type = '103'
);
