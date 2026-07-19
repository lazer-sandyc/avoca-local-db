-- base.sql — synthetic test fixture for the shared local avoca-next DB.
--
-- Our own data, not a prod dump: no PII, fast, shaped for the scenarios we test
-- (agent-to-agent transfer linking: an English agent hands off to a Spanish
-- agent on the same team). Grows over time — add teams/agents/wiring as tests
-- need them.
--
-- Idempotent: re-running deletes and recreates everything in the reserved id
-- ranges, so it's safe to run repeatedly.
--
-- Reserved id space (so we never collide with a real/config seed):
--   enterprises.id              = 990000
--   auth.users.id / profiles.id = b0000000-0000-0000-0000-000000000001 (synthetic owner;
--                                 teams.owner_id -> profiles.id -> auth.users.id is NOT NULL)
--   teams.id                    = 990001..990099
--   phone_numbers.id            = 99xxxx  (990T01 / 990T02 per team T)
--   voice_assistants.id         = a0000000-...-0000000000TA  (uuid)
--   assistant_configs.id        = c0000000-...-0000000000TA  (uuid)
--   transfer_destinations.id    = identity (auto; cleaned by team_id range)
--   where T = team index (1..N), A = agent (1=English, 2=Spanish)
--
-- Run:  PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -f scripts/seed/base.sql
-- (or via scripts/setup-local-db.sh once wired.)

BEGIN;

DO $$
DECLARE
  v_ent_id   bigint := 990000;
  v_owner_id uuid   := 'b0000000-0000-0000-0000-000000000001';  -- synthetic test owner
  v_n_teams  int    := 1;              -- bump to add teams (names gain a numeric suffix)
  t          int;
  v_team_id  bigint;
  v_label    text;                     -- 'Test Team' (single) or 'Test Team N' (many)
  en_va uuid; es_va uuid; en_ac uuid; es_ac uuid;
  en_td bigint; es_td bigint;
  en_phone bigint; es_phone bigint;
  en_num text; es_num text;
  plat text;
BEGIN
  -- ---- clean prior seed (children first; break the VA<->AC cycle) ----
  UPDATE voice_assistants
     SET default_assistant_config_id = NULL,
         main_inbound_call_phone_id   = NULL,
         test_inbound_call_phone_id    = NULL,
         backup_inbound_call_phone_id  = NULL
   WHERE team_id BETWEEN 990001 AND 990099;
  DELETE FROM transfer_destination_logs
   WHERE transfer_destination_id IN
     (SELECT id FROM transfer_destinations WHERE team_id BETWEEN 990001 AND 990099);
  DELETE FROM transfer_destinations WHERE team_id BETWEEN 990001 AND 990099;
  DELETE FROM assistant_configs     WHERE team_id BETWEEN 990001 AND 990099;
  DELETE FROM phone_numbers         WHERE team_id BETWEEN 990001 AND 990099;
  DELETE FROM voice_assistants      WHERE team_id BETWEEN 990001 AND 990099;
  DELETE FROM teams                 WHERE id      BETWEEN 990001 AND 990099;
  -- NOTE: the synthetic owner (v_owner_id) + enterprise (v_ent_id) are created by
  -- avoca-dev's _ensure_synthetic_owner (run by setup AND seed), NOT here. This keeps
  -- them out of the generic setup's team list, and means re-seeding never deletes an
  -- owner a duplicated real team is attached to. This block assumes they already exist.

  -- ---- teams, each with an English + Spanish agent ----
  FOR t IN 1..v_n_teams LOOP
    v_team_id := 990000 + t;
    v_label   := CASE WHEN v_n_teams > 1 THEN 'Test Team ' || t ELSE 'Test Team' END;
    plat      := CASE WHEN t = 2 THEN 'elevenlabs' ELSE 'vapi' END;

    en_va    := ('a0000000-0000-0000-0000-' || lpad((t*10+1)::text, 12, '0'))::uuid;
    es_va    := ('a0000000-0000-0000-0000-' || lpad((t*10+2)::text, 12, '0'))::uuid;
    en_ac    := ('c0000000-0000-0000-0000-' || lpad((t*10+1)::text, 12, '0'))::uuid;
    es_ac    := ('c0000000-0000-0000-0000-' || lpad((t*10+2)::text, 12, '0'))::uuid;
    en_phone := 990000 + t*10 + 1;
    es_phone := 990000 + t*10 + 2;
    en_num   := '+1999555' || lpad((t*10+1)::text, 4, '0');
    es_num   := '+1999555' || lpad((t*10+2)::text, 4, '0');

    INSERT INTO teams (id, name, enterprise_id, owner_id)
      VALUES (v_team_id, v_label, v_ent_id, v_owner_id);

    -- voice assistants (own their inbound number; point at their agent config)
    INSERT INTO voice_assistants (id, team_id, name)
      VALUES (en_va, v_team_id, v_label || ' — English'),
             (es_va, v_team_id, v_label || ' — Spanish');

    -- inbound phone numbers (routing + transfer-destination match key)
    INSERT INTO phone_numbers (id, team_id, phone_number)
      VALUES (en_phone, v_team_id, en_num),
             (es_phone, v_team_id, es_num);

    -- agent configs
    INSERT INTO assistant_configs (id, team_id, assistant_mode, voice_assistant_id, name, platform)
      VALUES (en_ac, v_team_id, 'blueprint', en_va, v_label || ' — English', plat),
             (es_ac, v_team_id, 'blueprint', es_va, v_label || ' — Spanish', plat);

    -- wire each voice assistant to its inbound number + default agent config
    UPDATE voice_assistants
       SET main_inbound_call_phone_id = en_phone, default_assistant_config_id = en_ac
     WHERE id = en_va;
    UPDATE voice_assistants
       SET main_inbound_call_phone_id = es_phone, default_assistant_config_id = es_ac
     WHERE id = es_va;

    -- agent-to-agent transfer destinations, linked to the target agent via the
    -- transfer_destination_assistants join table (prod dropped the old
    -- transfer_destinations.target_assistant_config_id column). These are the
    -- intra-team agent handoffs the linking feature stitches.
    INSERT INTO transfer_destinations (team_id, name, number, type, active)
      VALUES (v_team_id, 'To Spanish agent', es_num, 'number', true) RETURNING id INTO es_td;
    INSERT INTO transfer_destinations (team_id, name, number, type, active)
      VALUES (v_team_id, 'To English agent', en_num, 'number', true) RETURNING id INTO en_td;
    INSERT INTO transfer_destination_assistants (transfer_destination_id, team_id, voice_assistant_id)
      VALUES (es_td, v_team_id, es_va),
             (en_td, v_team_id, en_va);
  END LOOP;
END $$;

COMMIT;

-- Summary
\echo ''
\echo '=== seeded ==='
SELECT 'enterprise' AS kind, count(*) FROM enterprises WHERE id = 990000
UNION ALL SELECT 'teams',                 count(*) FROM teams                 WHERE id BETWEEN 990001 AND 990099
UNION ALL SELECT 'voice_assistants',      count(*) FROM voice_assistants      WHERE team_id BETWEEN 990001 AND 990099
UNION ALL SELECT 'assistant_configs',     count(*) FROM assistant_configs     WHERE team_id BETWEEN 990001 AND 990099
UNION ALL SELECT 'phone_numbers',         count(*) FROM phone_numbers         WHERE team_id BETWEEN 990001 AND 990099
UNION ALL SELECT 'transfer_destinations',            count(*) FROM transfer_destinations            WHERE team_id BETWEEN 990001 AND 990099
UNION ALL SELECT 'transfer_destination_assistants',  count(*) FROM transfer_destination_assistants  WHERE team_id BETWEEN 990001 AND 990099;
