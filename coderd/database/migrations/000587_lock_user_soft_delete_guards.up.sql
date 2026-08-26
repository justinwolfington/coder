-- Close the insert-vs-soft-delete race for every table that
-- delete_deleted_user_resources deletes directly: an in-flight insert could
-- observe deleted = false, a concurrent soft-delete UPDATE (and its cleanup)
-- could commit, and the insert could then commit afterwards, resurrecting a
-- row for a soft-deleted user. For api_keys that resurrects a live session
-- token on an account the operator believes they deleted.
--
-- The guard and lock-ordering rationale lives inside fail_if_user_deleted()
-- below so it survives into dump.sql. This migration:
--
--  1. Replaces the four per-table guard functions (api_keys, user_links,
--     user_secrets, user_skills) and adds guards for the directly cleaned
--     tables that had none (user_ai_provider_keys, organization_members)
--     plus user_ai_budget_overrides, all seven triggers pointing at the one
--     shared fail_if_user_deleted() function so the lock and the TG_OP gate
--     exist in exactly one place.
--  2. Moves the per-user cap triggers (user_secrets, user_skills) off the
--     users row onto per-user advisory locks, and renames them with a zz_
--     prefix so they always fire after the guard triggers (BEFORE triggers
--     fire in name order). The caps count committed rows, which is only
--     correct under READ COMMITTED; require_read_committed() below rejects
--     stronger levels whose stale snapshots can overshoot the caps.
--  3. Backfill-deletes child rows of already-soft-deleted users after the
--     triggers are in place, so an old-snapshot insert cannot commit
--     between the backfill and the guard swap and survive uncleaned.
--
-- group_members and user_ai_budget_overrides are wiped transitively by the
-- cleanup (BEFORE DELETE triggers on organization_members), not directly;
-- they get backfills below. user_ai_budget_overrides also gets a guard:
-- GetOverBudgetUsersPerGroup reads it with no users.deleted filter, so a
-- resurrected override row would publish a phantom over-budget metric for a
-- deleted user. group_members keeps no guard: its readers go through
-- group_members_expanded, which filters users.deleted, so a row that slips
-- past the cleanup one level down is inert.

-- The shared soft-delete guard. TG_ARGV[0] is the display name for the
-- error message, TG_ARGV[1] the stable constraint name callers match on.
-- Optional TG_ARGV[2] names the constraint raised when the users row does
-- not exist at all: tables passing it fail closed on a missing parent
-- instead of deferring to the end-of-statement foreign-key check.
CREATE FUNCTION fail_if_user_deleted() RETURNS trigger
	LANGUAGE plpgsql
AS $$
DECLARE
	user_deleted boolean;
BEGIN
	-- Serialize child-table inserts against a concurrent user soft-delete:
	-- an unlocked insert can read deleted = false, lose the race to the
	-- soft-delete UPDATE and its cleanup, then commit a resurrected row.
	-- FOR NO KEY UPDATE conflicts with the soft-delete UPDATE but not with
	-- the FOR KEY SHARE locks that foreign-key validation takes on the
	-- users row for other child tables.
	--
	-- The lock is INSERT-only: this trigger also fires BEFORE UPDATE on
	-- user_links, user_secrets, and user_skills, where taking the users
	-- lock deadlocks against delete_deleted_user_resources (a multi-row
	-- UPDATE or ON CONFLICT path can hold one child tuple and wait on
	-- users while the cleanup holds users and waits on a child tuple), and
	-- would serialize routine child updates on the hot users row. The
	-- UPDATE path keeps the unlocked read: an existing row is cleaned up
	-- by the soft-delete either way.
	--
	-- The INSERT-path lock imposes an ordering contract on writers: a
	-- transaction that writes a guarded child row (INSERT, UPDATE, or
	-- DELETE) and later inserts a guarded row for the same user must call
	-- AcquireUserSoftDeleteGuardLock first, so its lock order (users, then
	-- child rows) matches delete_deleted_user_resources. The same contract
	-- covers the cap triggers' advisory locks: without the users lock
	-- first, an update-then-insert writer can cycle with a concurrent
	-- insert that holds the users lock and waits on the advisory lock.
	-- coderd/database/user_soft_delete_guards_test.go replays each known
	-- such path as a deterministic deadlock regression (hand-written SQL
	-- mirroring the Go transactions, plus the OAuth2 token exchange driven
	-- through its real entry point).
	--
	-- Safe under any isolation level: READ COMMITTED re-reads the committed
	-- users.deleted after the lock wait, and a REPEATABLE READ or
	-- SERIALIZABLE waiter fails with a serialization error (40001) because
	-- the soft-delete updated the locked row.
	IF (TG_OP = 'INSERT') THEN
		SELECT deleted INTO user_deleted
		FROM users
		WHERE id = NEW.user_id
		FOR NO KEY UPDATE;
	ELSE
		SELECT deleted INTO user_deleted
		FROM users
		WHERE id = NEW.user_id;
	END IF;
	IF (NOT FOUND AND TG_NARGS >= 3) THEN
		-- Fail closed for tables that opt in: an uncommitted or missing
		-- parent must not pass the guard on the strength of a foreign-key
		-- check that only runs at end of statement.
		RAISE EXCEPTION 'Cannot create % for missing user', TG_ARGV[0]
			USING ERRCODE = 'check_violation',
				  CONSTRAINT = TG_ARGV[2];
	END IF;
	IF (user_deleted) THEN
		RAISE EXCEPTION 'Cannot create % for deleted user', TG_ARGV[0]
			USING ERRCODE = 'check_violation',
				  CONSTRAINT = TG_ARGV[1];
	END IF;
	RETURN NEW;
END;
$$;

DROP TRIGGER trigger_insert_apikeys ON api_keys;
DROP TRIGGER trigger_upsert_user_links ON user_links;
DROP TRIGGER trigger_upsert_user_secrets ON user_secrets;
DROP TRIGGER trigger_upsert_user_skills ON user_skills;
DROP FUNCTION insert_apikey_fail_if_user_deleted();
DROP FUNCTION insert_user_links_fail_if_user_deleted();
DROP FUNCTION insert_user_secret_fail_if_user_deleted();
DROP FUNCTION insert_user_skill_fail_if_user_deleted();

CREATE TRIGGER trigger_insert_apikeys
	BEFORE INSERT ON api_keys
	FOR EACH ROW
EXECUTE FUNCTION fail_if_user_deleted('API key', 'api_key_user_deleted');

CREATE TRIGGER trigger_upsert_user_links
	BEFORE INSERT OR UPDATE ON user_links
	FOR EACH ROW
EXECUTE FUNCTION fail_if_user_deleted('user_link', 'user_link_user_deleted');

CREATE TRIGGER trigger_upsert_user_secrets
	BEFORE INSERT OR UPDATE ON user_secrets
	FOR EACH ROW
EXECUTE FUNCTION fail_if_user_deleted('user_secret', 'user_secret_user_deleted');

CREATE TRIGGER trigger_upsert_user_skills
	BEFORE INSERT OR UPDATE ON user_skills
	FOR EACH ROW
EXECUTE FUNCTION fail_if_user_deleted('user_skill', 'user_skill_user_deleted');

CREATE TRIGGER trigger_insert_user_ai_provider_keys
	BEFORE INSERT ON user_ai_provider_keys
	FOR EACH ROW
EXECUTE FUNCTION fail_if_user_deleted('user_ai_provider_key', 'user_ai_provider_key_user_deleted');

CREATE TRIGGER trigger_insert_organization_members
	BEFORE INSERT ON organization_members
	FOR EACH ROW
EXECUTE FUNCTION fail_if_user_deleted('organization_member', 'organization_member_user_deleted');

CREATE TRIGGER trigger_insert_user_ai_budget_overrides
	BEFORE INSERT ON user_ai_budget_overrides
	FOR EACH ROW
EXECUTE FUNCTION fail_if_user_deleted('user_ai_budget_override', 'user_ai_budget_override_user_deleted');

-- Per-owner caps count committed sibling rows, which is only correct under
-- READ COMMITTED: a REPEATABLE READ or SERIALIZABLE snapshot taken before a
-- lock wait can miss rows committed during the wait and overshoot the cap
-- (SERIALIZABLE only tracks conflicts among SERIALIZABLE transactions, so a
-- mixed pairing overshoots too). READ UNCOMMITTED is accepted because
-- PostgreSQL executes it with READ COMMITTED semantics.
-- Cap trigger functions call this before counting; the argument is the
-- stable constraint name callers match on.
CREATE FUNCTION require_read_committed(guard_name text, constraint_name text) RETURNS void
	LANGUAGE plpgsql
AS $$
BEGIN
	IF current_setting('transaction_isolation') NOT IN ('read committed', 'read uncommitted') THEN
		RAISE EXCEPTION '% requires READ COMMITTED isolation, ran under %',
			guard_name, current_setting('transaction_isolation')
			USING ERRCODE = 'check_violation',
				  CONSTRAINT = constraint_name,
				  DETAIL = 'A stronger level''s snapshot can survive a lock wait and miss concurrently committed rows, overshooting the cap. If no caller set this level, check default_transaction_isolation on the server, database, role, or pooler.';
	END IF;
END;
$$;

-- The per-user cap triggers previously serialized on the users row with
-- FOR UPDATE, which deadlocked with delete_deleted_user_resources on the
-- user_secrets UPDATE path, upgraded the guard's FOR NO KEY UPDATE, and
-- conflicted with the FOR KEY SHARE taken by foreign-key validation on
-- every table referencing users. They serialize on a transaction-scoped
-- per-user advisory lock instead, on every path they fire on, so
-- concurrent updates cannot bypass the byte caps either.
CREATE OR REPLACE FUNCTION enforce_user_secrets_per_user_limits() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    existing_count       int;
    existing_total_bytes bigint;
    existing_env_bytes   bigint;

    new_count       int;
    new_total_bytes bigint;
    new_env_bytes   bigint;

    count_limit       constant int    := 50;
    total_bytes_limit constant bigint := 204800;   -- 200 KiB
    env_bytes_limit   constant bigint := 24576;    -- 24 KiB
BEGIN
    -- Inserts and owner reassignments cross the per-user cap boundary, so
    -- they require READ COMMITTED (a stale stronger-isolation snapshot can
    -- miss concurrently committed rows and overshoot). Same-owner updates
    -- are exempt: dbcrypt rotation legitimately rewrites values under
    -- REPEATABLE READ (its 40001 on concurrent modification is
    -- load-bearing), and their stale-snapshot byte-count risk predates this
    -- migration (the old users-row lock counted under the same snapshot).
    IF (TG_OP = 'INSERT' OR NEW.user_id IS DISTINCT FROM OLD.user_id) THEN
        PERFORM require_read_committed('user_secrets caps', 'user_secrets_cap_isolation');
    END IF;

    -- Serialize cap checks per user so concurrent inserts or updates cannot
    -- all observe the same pre-statement aggregates and exceed the caps.
    -- The advisory lock avoids the users row entirely:
    -- delete_deleted_user_resources takes no advisory locks, so no lock
    -- cycle involving only single-statement writers and a concurrent
    -- soft-delete is possible, and inserts into other tables referencing
    -- users are unaffected. Two ordering rules keep it cycle-free:
    -- within one statement, the soft-delete guard must take the users lock
    -- before this advisory lock (hence the zz_ trigger name; BEFORE
    -- triggers fire in name order); across statements, a transaction that
    -- writes a guarded child row and later inserts one must take the users
    -- lock first via AcquireUserSoftDeleteGuardLock, because an
    -- update-then-insert writer holds this advisory lock with no users
    -- lock and can cycle with a concurrent insert that holds the users
    -- lock and waits here. The Go registry for these advisory keys is
    -- coderd/database/lock.go.
    PERFORM pg_advisory_xact_lock(hashtextextended('user_secrets_cap:' || NEW.user_id::text, 0));

    -- Sum existing rows excluding the row being updated (so UPDATE statements
    -- don't double-count NEW). On INSERT, no row matches NEW.id, so
    -- the FILTER is a no-op.
    SELECT
        count(*) FILTER (WHERE id IS DISTINCT FROM NEW.id),
        coalesce(sum(octet_length(value)) FILTER (WHERE id IS DISTINCT FROM NEW.id), 0),
        coalesce(sum(octet_length(value)) FILTER (WHERE id IS DISTINCT FROM NEW.id AND env_name <> ''), 0)
    INTO existing_count, existing_total_bytes, existing_env_bytes
    FROM user_secrets
    WHERE user_id = NEW.user_id;

    new_count       := existing_count + 1;
    new_total_bytes := existing_total_bytes + octet_length(NEW.value);
    new_env_bytes   := existing_env_bytes
                       + CASE WHEN NEW.env_name <> '' THEN octet_length(NEW.value) ELSE 0 END;

    IF new_count > count_limit THEN
        RAISE EXCEPTION 'user has reached the user secrets count limit (% > %)',
            new_count, count_limit
            USING ERRCODE = 'check_violation',
                  CONSTRAINT = 'user_secrets_per_user_count_limit';
    END IF;

    IF new_total_bytes > total_bytes_limit THEN
        RAISE EXCEPTION 'user has reached the user secrets total value bytes limit (% > %)',
            new_total_bytes, total_bytes_limit
            USING ERRCODE = 'check_violation',
                  CONSTRAINT = 'user_secrets_per_user_total_bytes_limit';
    END IF;

    IF new_env_bytes > env_bytes_limit THEN
        RAISE EXCEPTION 'user has reached the env-injected user secrets bytes limit (% > %)',
            new_env_bytes, env_bytes_limit
            USING ERRCODE = 'check_violation',
                  CONSTRAINT = 'user_secrets_per_user_env_bytes_limit';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION enforce_user_skills_per_user_limit() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    skill_count int;
    skill_limit constant int := 100;
BEGIN
    -- A same-owner update cannot change the per-user count; only inserts
    -- and owner reassignments (UPDATE ... SET user_id) are counted, so an
    -- update cannot move a row onto an owner already at the cap.
    IF (TG_OP = 'UPDATE' AND NEW.user_id IS NOT DISTINCT FROM OLD.user_id) THEN
        RETURN NEW;
    END IF;

    PERFORM require_read_committed('user_skills cap', 'user_skills_cap_isolation');

    -- Serialize skill-cap checks per user so concurrent inserts cannot all
    -- observe the same pre-insert count and exceed the hard limit. See
    -- enforce_user_secrets_per_user_limits for why this is an advisory
    -- lock and why the trigger name carries the zz_ prefix.
    PERFORM pg_advisory_xact_lock(hashtextextended('user_skills_cap:' || NEW.user_id::text, 0));

    -- On an owner reassignment the moving row still belongs to
    -- OLD.user_id, so counting NEW.user_id's rows excludes it naturally.
    SELECT count(*) INTO skill_count
    FROM user_skills
    WHERE user_id = NEW.user_id;
    IF skill_count >= skill_limit THEN
        RAISE EXCEPTION 'user has reached the personal skill limit'
            USING ERRCODE = 'check_violation',
                  CONSTRAINT = 'user_skills_per_user_limit';
    END IF;
    RETURN NEW;
END;
$$;

-- zz_ prefix: BEFORE triggers fire in name order, and the soft-delete
-- guards must take the users lock before the cap triggers take the
-- advisory lock (see the cap function bodies).
DROP TRIGGER trigger_user_secrets_per_user_limits ON user_secrets;
CREATE TRIGGER trigger_zz_user_secrets_per_user_limits
    BEFORE INSERT OR UPDATE ON user_secrets
    FOR EACH ROW
EXECUTE FUNCTION enforce_user_secrets_per_user_limits();

-- INSERT OR UPDATE: the update leg exists solely to catch owner
-- reassignments (the function returns early for same-owner updates), which
-- would otherwise move rows onto an owner already at the cap.
DROP TRIGGER trigger_user_skills_per_user_limit ON user_skills;
CREATE TRIGGER trigger_zz_user_skills_per_user_limit
    BEFORE INSERT OR UPDATE ON user_skills
    FOR EACH ROW
EXECUTE FUNCTION enforce_user_skills_per_user_limit();

-- Backfill: remove every child row belonging to an already-soft-deleted
-- user, race products and pre-cleanup orphans alike (organization_members
-- and user_ai_provider_keys only joined delete_deleted_user_resources in
-- migrations 000492 and 000503, so their orphans can predate cleanup
-- coverage and are legitimate leftovers, not race products).
DELETE FROM api_keys WHERE user_id IN (SELECT id FROM users WHERE deleted);
DELETE FROM user_links WHERE user_id IN (SELECT id FROM users WHERE deleted);
DELETE FROM user_secrets WHERE user_id IN (SELECT id FROM users WHERE deleted);
DELETE FROM user_skills WHERE user_id IN (SELECT id FROM users WHERE deleted);
DELETE FROM user_ai_provider_keys WHERE user_id IN (SELECT id FROM users WHERE deleted);
DELETE FROM organization_members WHERE user_id IN (SELECT id FROM users WHERE deleted);
-- group_members and user_ai_budget_overrides rows for these users are
-- deleted transitively by the organization_members BEFORE DELETE triggers
-- above; the direct deletes catch rows resurrected after the user's
-- organization_members rows were already cleaned up.
DELETE FROM group_members WHERE user_id IN (SELECT id FROM users WHERE deleted);
DELETE FROM user_ai_budget_overrides WHERE user_id IN (SELECT id FROM users WHERE deleted);
