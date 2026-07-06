-- login-user.sql — a local dashboard login for the local DB.
--
-- Creates an @avoca.ai user. That email domain alone grants system-level admin
-- (avoca-next's isAvocaEmployee = email ends with '@avoca.ai'), so this user can
-- join/access any team via the admin UI. Password login works locally because
-- there's no SSO config row to force SSO on the seed DB.
--
-- Parameterized: pass -v email=... -v pass=... -v fullname=... (avoca-dev seed does this).
-- Idempotent: re-run replaces the user (matched by uid or email).

\set ON_ERROR_STOP on
BEGIN;

-- psql does NOT interpolate :vars inside a $$ block, so stash them in
-- transaction-local settings and read them with current_setting() below.
SELECT set_config('avoca.seed_email', :'email',    true),
       set_config('avoca.seed_pass',  :'pass',     true),
       set_config('avoca.seed_name',  :'fullname', true);

DO $$
DECLARE
  v_uid   uuid := 'b0000000-0000-0000-0000-000000000002';
  v_email text := current_setting('avoca.seed_email');
  v_pass  text := current_setting('avoca.seed_pass');
  v_name  text := current_setting('avoca.seed_name');
BEGIN
  DELETE FROM auth.identities    WHERE user_id = v_uid OR user_id IN (SELECT id FROM auth.users WHERE email = v_email);
  DELETE FROM members            WHERE user_id = v_uid OR user_id IN (SELECT id FROM auth.users WHERE email = v_email);
  DELETE FROM enterprise_members WHERE user_id = v_uid OR user_id IN (SELECT id FROM auth.users WHERE email = v_email);
  DELETE FROM profiles           WHERE id = v_uid OR id IN (SELECT id FROM auth.users WHERE email = v_email);
  DELETE FROM auth.users         WHERE id = v_uid OR email = v_email;

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data,
    confirmation_token, recovery_token, email_change, email_change_token_new
  ) VALUES (
    v_uid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    v_email, crypt(v_pass, gen_salt('bf')),
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    '', '', '', ''
  );

  INSERT INTO auth.identities (
    provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
  ) VALUES (
    v_uid::text, v_uid,
    jsonb_build_object('sub', v_uid::text, 'email', v_email, 'email_verified', true),
    'email', now(), now(), now()
  );

  INSERT INTO profiles (id, email, full_name, has_onboarded)
    VALUES (v_uid, v_email, v_name, true);
END $$;

COMMIT;

SELECT u.email,
       (u.email_confirmed_at IS NOT NULL) AS confirmed,
       (u.encrypted_password LIKE '$2%')  AS bcrypt_hash,
       (i.provider IS NOT NULL)           AS has_identity,
       (p.id IS NOT NULL)                 AS has_profile
FROM auth.users u
LEFT JOIN auth.identities i ON i.user_id = u.id
LEFT JOIN profiles p ON p.id = u.id
WHERE u.email = :'email';
