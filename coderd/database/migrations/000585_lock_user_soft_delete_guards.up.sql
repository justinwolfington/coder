-- Close the insert-vs-soft-delete race for every table that
-- delete_deleted_user_resources wipes: an in-flight insert could observe
-- deleted = false, a concurrent soft-delete UPDATE (and its cleanup) could
-- commit, and the insert could then commit afterwards, resurrecting a row
-- for a soft-deleted user. For api_keys that resurrects a live session token
-- on an account the operator believes they deleted.
--
-- The four existing guard triggers (insert_apikey_fail_if_user_deleted,
-- insert_user_links_fail_if_user_deleted,
-- insert_user_secret_fail_if_user_deleted,
-- insert_user_skill_fail_if_user_deleted) read users.deleted without a
-- lock; user_ai_provider_keys and organization_members had no guard at all,
-- so those two gain new guards here.
--
-- SELECT ... FOR NO KEY UPDATE on the parent users row serializes the guard
-- against the soft-delete UPDATE without conflicting with the FOR KEY SHARE
-- locks taken by foreign key validation on other child tables. The lock is
-- taken only on the INSERT path: the user_links/user_secrets/user_skills
-- triggers also fire BEFORE UPDATE, where taking the lock can deadlock
-- against delete_deleted_user_resources (the update holds the child tuple
-- and waits on users while the cleanup holds users and waits on the child
-- tuple) and would serialize routine child updates against the hot users
-- row. The UPDATE path keeps the unlocked read: an existing row is cleaned
-- up by the soft-delete either way.
--
-- Safe under any isolation level: READ COMMITTED re-reads the committed
-- users.deleted after the lock wait, and a REPEATABLE READ or SERIALIZABLE
-- waiter fails with a serialization error (40001) because the soft-delete
-- updated the locked row.
--
-- The guards now raise check_violation with stable per-table constraint
-- names so callers can match the error without parsing prose. The message
-- texts stay unchanged.

-- Clean up rows already resurrected by the race for soft-deleted users.
-- delete_deleted_user_resources removed rows present at soft-delete time,
-- so anything matching here is a product of the race.
DELETE FROM api_keys WHERE user_id IN (SELECT id FROM users WHERE deleted);
DELETE FROM user_links WHERE user_id IN (SELECT id FROM users WHERE deleted);
DELETE FROM user_secrets WHERE user_id IN (SELECT id FROM users WHERE deleted);
DELETE FROM user_skills WHERE user_id IN (SELECT id FROM users WHERE deleted);
DELETE FROM user_ai_provider_keys WHERE user_id IN (SELECT id FROM users WHERE deleted);
DELETE FROM organization_members WHERE user_id IN (SELECT id FROM users WHERE deleted);

-- trigger_insert_apikeys fires BEFORE INSERT only, so the lock is taken
-- unconditionally.
CREATE OR REPLACE FUNCTION insert_apikey_fail_if_user_deleted() RETURNS trigger
	LANGUAGE plpgsql
AS $$
DECLARE
	user_deleted boolean;
BEGIN
	IF (NEW.user_id IS NOT NULL) THEN
		SELECT deleted INTO user_deleted
		FROM users
		WHERE id = NEW.user_id
		FOR NO KEY UPDATE;
		IF (user_deleted) THEN
			RAISE EXCEPTION 'Cannot create API key for deleted user'
				USING ERRCODE = 'check_violation',
					  CONSTRAINT = 'api_key_user_deleted';
		END IF;
	END IF;
	RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION insert_user_links_fail_if_user_deleted() RETURNS trigger
	LANGUAGE plpgsql
AS $$
DECLARE
	user_deleted boolean;
BEGIN
	IF (NEW.user_id IS NOT NULL) THEN
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
		IF (user_deleted) THEN
			RAISE EXCEPTION 'Cannot create user_link for deleted user'
				USING ERRCODE = 'check_violation',
					  CONSTRAINT = 'user_link_user_deleted';
		END IF;
	END IF;
	RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION insert_user_secret_fail_if_user_deleted() RETURNS trigger
	LANGUAGE plpgsql
AS $$
DECLARE
	user_deleted boolean;
BEGIN
	IF (NEW.user_id IS NOT NULL) THEN
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
		IF (user_deleted) THEN
			RAISE EXCEPTION 'Cannot create user_secret for deleted user'
				USING ERRCODE = 'check_violation',
					  CONSTRAINT = 'user_secret_user_deleted';
		END IF;
	END IF;
	RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION insert_user_skill_fail_if_user_deleted() RETURNS trigger
    LANGUAGE plpgsql
AS $$
DECLARE
    user_deleted boolean;
BEGIN
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
    IF (user_deleted) THEN
        RAISE EXCEPTION 'Cannot create user_skill for deleted user'
            USING ERRCODE = 'check_violation',
                  CONSTRAINT = 'user_skill_user_deleted';
    END IF;
    RETURN NEW;
END;
$$;

-- New guards for the two delete_deleted_user_resources tables that had none.
-- Both triggers fire BEFORE INSERT only, so the lock is unconditional.
CREATE FUNCTION insert_user_ai_provider_key_fail_if_user_deleted() RETURNS trigger
	LANGUAGE plpgsql
AS $$
DECLARE
	user_deleted boolean;
BEGIN
	SELECT deleted INTO user_deleted
	FROM users
	WHERE id = NEW.user_id
	FOR NO KEY UPDATE;
	IF (user_deleted) THEN
		RAISE EXCEPTION 'Cannot create user_ai_provider_key for deleted user'
			USING ERRCODE = 'check_violation',
				  CONSTRAINT = 'user_ai_provider_key_user_deleted';
	END IF;
	RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_insert_user_ai_provider_keys
	BEFORE INSERT ON user_ai_provider_keys
	FOR EACH ROW
EXECUTE PROCEDURE insert_user_ai_provider_key_fail_if_user_deleted();

CREATE FUNCTION insert_organization_member_fail_if_user_deleted() RETURNS trigger
	LANGUAGE plpgsql
AS $$
DECLARE
	user_deleted boolean;
BEGIN
	SELECT deleted INTO user_deleted
	FROM users
	WHERE id = NEW.user_id
	FOR NO KEY UPDATE;
	IF (user_deleted) THEN
		RAISE EXCEPTION 'Cannot create organization_member for deleted user'
			USING ERRCODE = 'check_violation',
				  CONSTRAINT = 'organization_member_user_deleted';
	END IF;
	RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_insert_organization_members
	BEFORE INSERT ON organization_members
	FOR EACH ROW
EXECUTE PROCEDURE insert_organization_member_fail_if_user_deleted();

-- The pre-existing user_secrets cap trigger fires BEFORE INSERT OR UPDATE
-- and took FOR UPDATE on the users row unconditionally, which reintroduces
-- the same lock-order-inversion deadlock with delete_deleted_user_resources
-- on the UPDATE path (child tuple held while waiting on users; cleanup holds
-- users while waiting on the child tuple). Gate the lock to INSERT: the aggregate
-- checks still run on UPDATE, unserialized, accepting a bounded overshoot
-- when the same user updates secrets concurrently instead of a deadlock.
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
    -- Serialize cap checks per user so concurrent inserts cannot all
    -- observe the same pre-insert aggregates and exceed the cap. INSERT
    -- only: locking on UPDATE deadlocks against the soft-delete cleanup.
    IF (TG_OP = 'INSERT') THEN
        PERFORM 1 FROM users WHERE id = NEW.user_id FOR UPDATE;
    END IF;

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
