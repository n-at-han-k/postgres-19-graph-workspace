-- ============================================================
-- ONTOLOGY ON THINGS — SQL/PGQ experiment (PostgreSQL 19 beta)
--
-- Model: one polymorphic `things` table, discriminated by mimetype.
--        one `links` edge table.
--        SQL/PGQ property graph layered on top as a read-only view.
--
-- The point of cells 6–8 is to FIND OUT whether views are legal
-- element tables. If they are, Option B is the design. If not,
-- fall back to Option A (cell 5).
--
-- Run cells top to bottom. Cells are separated by blank lines.
-- ============================================================


-- ── CELL 1 ─────────────────────────────────────────────────
-- Confirm you're actually on 19. If this says 18, stop.
SELECT version(), current_setting('server_version_num')::int AS num;


-- ── CELL 2 ─────────────────────────────────────────────────
-- Clean slate. Safe to re-run.
DROP PROPERTY GRAPH IF EXISTS ontology;
DROP VIEW IF EXISTS t_event, t_address, t_person, t_photo,
                    l_located_at, l_depicts, t_attendance CASCADE;
DROP TABLE IF EXISTS links, things CASCADE;


-- ── CELL 3 ─────────────────────────────────────────────────
-- The object store. mimetype IS the discriminator.
-- Custom vendor types for domain models; real IANA types for files.
CREATE TABLE things (
  id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  title     text,
  summary   text,
  locator   text,                          -- uri
  mimetype  text  NOT NULL,
  hash      text  UNIQUE,                  -- sha256, content identity
  tags      text[] NOT NULL DEFAULT '{}',
  metadata  jsonb  NOT NULL DEFAULT '{}'
);

CREATE INDEX things_mimetype_idx ON things (mimetype);
CREATE INDEX things_tags_idx     ON things USING gin (tags);
CREATE INDEX things_meta_idx     ON things USING gin (metadata jsonb_path_ops);

-- Edges. NOT in jsonb: we need reverse traversal and real FKs,
-- and SQL/PGQ needs key COLUMNS to build SOURCE/DESTINATION from.
CREATE TABLE links (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  link_type  text   NOT NULL,
  source_id  bigint NOT NULL REFERENCES things(id) ON DELETE CASCADE,
  target_id  bigint NOT NULL REFERENCES things(id) ON DELETE CASCADE,
  properties jsonb  NOT NULL DEFAULT '{}',
  UNIQUE (source_id, link_type, target_id)
);

CREATE INDEX links_fwd_idx ON links (source_id, link_type);
CREATE INDEX links_rev_idx ON links (target_id, link_type);   -- the jsonb-killer


-- ── CELL 4 ─────────────────────────────────────────────────
-- Seed. One event, one address, one person, one photo, one attendance.
WITH ins AS (
  INSERT INTO things (title, mimetype, locator, hash, tags, metadata) VALUES
    ('Kingsland Road W1',    'application/vnd.acme.address+json',    NULL, 'sha-addr-1',  '{london}',
       '{"line1":"221 Kingsland Rd","postcode":"E2 8AS","location":{"lat":51.5312,"lon":-0.0759}}'),
    ('Ontology Meetup',      'application/vnd.acme.event+json',      NULL, 'sha-evt-1',   '{meetup,pgq}',
       '{"starts_at":"2026-08-01T18:30:00Z","capacity":40}'),
    ('Ada L.',               'application/vnd.acme.person+json',     NULL, 'sha-per-1',   '{speaker}',
       '{"email":"ada@example.org"}'),
    ('Room shot',            'image/jpeg', 'file:///photos/room.jpg', 'sha-img-1',        '{venue}',
       '{"width":4032,"height":3024}'),
    ('Ada attends Meetup',   'application/vnd.acme.attendance+json', NULL, 'sha-att-1',   '{}',
       '{"rsvp":"yes","role":"speaker"}')
  RETURNING id, hash
)
SELECT * FROM ins;

-- Wire the edges by hash so this cell is idempotent-ish.
INSERT INTO links (link_type, source_id, target_id)
SELECT 'located_at', e.id, a.id
FROM things e, things a
WHERE e.hash = 'sha-evt-1' AND a.hash = 'sha-addr-1'
ON CONFLICT DO NOTHING;

INSERT INTO links (link_type, source_id, target_id)
SELECT 'depicts', p.id, e.id
FROM things p, things e
WHERE p.hash = 'sha-img-1' AND e.hash = 'sha-evt-1'
ON CONFLICT DO NOTHING;

-- The attendance Thing points at both ends via its metadata.
-- (Cell 9 lifts those into columns so PGQ can key on them.)
UPDATE things SET metadata = metadata || jsonb_build_object(
  'person_id', (SELECT id FROM things WHERE hash = 'sha-per-1'),
  'event_id',  (SELECT id FROM things WHERE hash = 'sha-evt-1')
) WHERE hash = 'sha-att-1';

SELECT id, mimetype, title FROM things ORDER BY id;


-- ── CELL 5 ── OPTION A: one label, filter on mimetype ──────
-- Guaranteed to work. Zero schema change. Also: barely better than a join.
CREATE PROPERTY GRAPH ontology
  VERTEX TABLES (
    things KEY (id)
      LABEL thing
      -- NOTE: a KEY column is NOT automatically a property.
      -- Omit `id` here and `WHERE t.id = 1` fails at parse time.
      PROPERTIES (id, title, summary, locator, mimetype, hash, tags, metadata)
  )
  EDGE TABLES (
    links KEY (id)
      SOURCE      KEY (source_id) REFERENCES things (id)
      DESTINATION KEY (target_id) REFERENCES things (id)
      LABEL link
      PROPERTIES (id, link_type, properties)
  );


-- ── CELL 6 ─────────────────────────────────────────────────
-- The derived property: Event.location := located_at -> Address.location
SELECT title, addr->'location' AS location
FROM GRAPH_TABLE (ontology
  MATCH (e IS thing WHERE e.mimetype = 'application/vnd.acme.event+json')
        -[l IS link WHERE l.link_type = 'located_at']->
        (a IS thing WHERE a.mimetype = 'application/vnd.acme.address+json')
  COLUMNS (e.title AS title, a.metadata AS addr));


-- ── CELL 7 ─────────────────────────────────────────────────
-- Does the graph layer actually vanish into joins + index scans?
-- Expect: no new executor nodes, just Nested Loop / Index Scan.
EXPLAIN (ANALYZE, COSTS OFF)
SELECT title
FROM GRAPH_TABLE (ontology
  MATCH (e IS thing WHERE e.mimetype = 'application/vnd.acme.event+json')
        -[l IS link WHERE l.link_type = 'located_at']->
        (a IS thing)
  COLUMNS (e.title AS title));


-- ── CELL 8 ── THE EXPERIMENT ───────────────────────────────
-- Are VIEWS legal element tables? PG docs say graphs are defined over
-- "tables or table-like objects"; Oracle's SQL/PGQ explicitly allows
-- views and matviews. Postgres: unverified. This cell decides the design.
--
-- If this errors: Option A is your ceiling (or partition `things`).
-- If it succeeds: labels per mimetype, for free, forever.
DROP PROPERTY GRAPH ontology;

CREATE VIEW t_event   AS SELECT * FROM things WHERE mimetype = 'application/vnd.acme.event+json';
CREATE VIEW t_address AS SELECT * FROM things WHERE mimetype = 'application/vnd.acme.address+json';
CREATE VIEW t_person  AS SELECT * FROM things WHERE mimetype = 'application/vnd.acme.person+json';
CREATE VIEW t_photo   AS SELECT * FROM things WHERE mimetype LIKE 'image/%';

CREATE VIEW l_located_at AS SELECT * FROM links WHERE link_type = 'located_at';
CREATE VIEW l_depicts    AS SELECT * FROM links WHERE link_type = 'depicts';

CREATE PROPERTY GRAPH ontology
  VERTEX TABLES (
    -- Double-labelled: `thing` is the interface, `event`/`address` the type.
    -- Shared labels REQUIRE matching property lists (number, name, type).
    t_event   KEY (id) LABEL event   LABEL thing PROPERTIES (id, title, locator, metadata),
    t_address KEY (id) LABEL address LABEL thing PROPERTIES (id, title, locator, metadata),
    t_person  KEY (id) LABEL person  LABEL thing PROPERTIES (id, title, locator, metadata),
    t_photo   KEY (id) LABEL photo   LABEL thing PROPERTIES (id, title, locator, metadata)
  )
  EDGE TABLES (
    l_located_at KEY (id)
      SOURCE      KEY (source_id) REFERENCES t_event   (id)
      DESTINATION KEY (target_id) REFERENCES t_address (id)
      LABEL located_at,
    l_depicts KEY (id)
      SOURCE      KEY (source_id) REFERENCES t_photo (id)
      DESTINATION KEY (target_id) REFERENCES t_event (id)
      LABEL depicts
  );


-- ── CELL 9 ── Object-backed link: a Thing that IS an edge ──
-- Foundry calls this an object-backed link type. Here it falls out for free:
-- the view lifts the jsonb ids into real columns PGQ can key on.
CREATE VIEW t_attendance AS
SELECT id, title, metadata,
       (metadata->>'person_id')::bigint AS person_id,
       (metadata->>'event_id')::bigint  AS event_id
FROM things
WHERE mimetype = 'application/vnd.acme.attendance+json';

ALTER PROPERTY GRAPH ontology ADD EDGE TABLE t_attendance
  KEY (id)
  SOURCE      KEY (person_id) REFERENCES t_person (id)
  DESTINATION KEY (event_id)  REFERENCES t_event  (id)
  LABEL attended
  PROPERTIES (id, title, metadata);


-- ── CELL 10 ────────────────────────────────────────────────
-- Now it reads like the domain instead of like a schema.
-- 3 hops: photo -> event -> address, plus who attended.
SELECT photo_url, event, addr->'location' AS location
FROM GRAPH_TABLE (ontology
  MATCH (p IS photo)-[IS depicts]->(e IS event)-[IS located_at]->(a IS address)
  COLUMNS (p.locator AS photo_url, e.title AS event, a.metadata AS addr));

SELECT who, rsvp->>'role' AS role, event
FROM GRAPH_TABLE (ontology
  MATCH (p IS person)-[att IS attended]->(e IS event)
  COLUMNS (p.title AS who, att.metadata AS rsvp, e.title AS event));


-- ── CELL 11 ── Interface polymorphism ──────────────────────
-- `thing` spans every mimetype. This is Foundry's "interfaces",
-- in three words of DDL. Anything can link to anything.
SELECT kind, title
FROM GRAPH_TABLE (ontology
  MATCH (x IS thing)
  COLUMNS (x.title AS title, x.metadata AS meta))
CROSS JOIN LATERAL (SELECT 'thing'::text AS kind) k;

-- LABELS() reports which labels an element actually carries.
SELECT title, labels
FROM GRAPH_TABLE (ontology
  MATCH (x IS thing)
  COLUMNS (x.title AS title, LABELS(x) AS labels));


-- ── CELL 12 ── Introspect the ontology metadata ────────────
-- psql's \dG / \d+ ontology won't run in DBCode. Query the catalogs.
SELECT * FROM pg_propgraph_element;         -- vertex + edge tables
SELECT * FROM pg_propgraph_label;           -- labels
SELECT * FROM pg_propgraph_label_property;  -- label -> property
SELECT * FROM pg_propgraph_property;        -- property expressions


-- ── CELL 13 ── The wall you WILL hit ───────────────────────
-- PG19 SQL/PGQ is FIXED-DEPTH ONLY. No -[IS link]->+ , no {2,5}.
-- Uncomment to watch it fail; that's the expected result, not a bug.
--
-- SELECT * FROM GRAPH_TABLE (ontology
--   MATCH (a IS thing)-[IS located_at]->+(b IS thing)
--   COLUMNS (a.title, b.title));
--
-- Transitive closure still needs a recursive CTE. Note this runs on the
-- BASE TABLES, not the graph — the two coexist happily.
WITH RECURSIVE reachable AS (
  SELECT l.source_id AS root, l.target_id AS node, l.link_type, 1 AS depth
  FROM links l
  UNION ALL
  SELECT r.root, l.target_id, l.link_type, r.depth + 1
  FROM reachable r
  JOIN links l ON l.source_id = r.node
  WHERE r.depth < 5
)
SELECT src.title AS from_thing, dst.title AS to_thing, r.link_type, r.depth
FROM reachable r
JOIN things src ON src.id = r.root
JOIN things dst ON dst.id = r.node
ORDER BY r.root, r.depth;


-- ── CELL 14 ── Does the mimetype filter reach the index? ────
-- The rewriter flattens graph -> relational BEFORE the planner runs,
-- so a partial index on the view's predicate should be usable.
CREATE INDEX IF NOT EXISTS things_event_idx ON things (id)
  WHERE mimetype = 'application/vnd.acme.event+json';

ANALYZE things;
ANALYZE links;

EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT event FROM GRAPH_TABLE (ontology
  MATCH (e IS event)-[IS located_at]->(a IS address)
  COLUMNS (e.title AS event));


-- ── CELL 15 ── Ontology metadata as data (optional) ─────────
-- If you want derived properties defined declaratively rather than
-- hand-written per query, this is the catalog Foundry keeps.
-- Cardinality forces the aggregation: any MANY hop in the chain
-- means you must pick count/avg/sum/min/max/collect_list/collect_set.
CREATE TABLE IF NOT EXISTS link_types (
  api_name     text PRIMARY KEY,
  source_mime  text NOT NULL,
  target_mime  text NOT NULL,
  cardinality  text NOT NULL CHECK (cardinality IN ('ONE','MANY')),
  inverse_name text
);

CREATE TABLE IF NOT EXISTS derived_properties (
  source_mime text   NOT NULL,
  name        text   NOT NULL,
  link_path   text[] NOT NULL,   -- {'located_at'} — max 3 hops, per Foundry
  source_prop text   NOT NULL,   -- 'location'
  aggregation text,              -- NULL only if every hop is ONE
  PRIMARY KEY (source_mime, name)
);

INSERT INTO link_types VALUES
  ('located_at', 'application/vnd.acme.event+json',
                 'application/vnd.acme.address+json', 'ONE', 'events_here'),
  ('depicts',    'image/jpeg',
                 'application/vnd.acme.event+json',   'MANY', 'photos')
ON CONFLICT DO NOTHING;

INSERT INTO derived_properties VALUES
  ('application/vnd.acme.event+json', 'location', ARRAY['located_at'], 'location', NULL)
ON CONFLICT DO NOTHING;

SELECT * FROM derived_properties;