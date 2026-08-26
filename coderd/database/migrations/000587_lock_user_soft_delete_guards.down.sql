-- Restore the original unlocked per-table guard functions and the
-- users-row-locking cap triggers, and drop the newly added guards. The
-- backfill deletes are not restorable.
DROP TRIGGER IF EXISTS trigger_insert_user_ai_provider_keys ON user_ai_provider_keys;
DROP TRIGGER IF EXISTS trigger_insert_organization_members ON organization_members;
DROP TRIGGER IF EXISTS trigger_insert_user_ai_budget_overrides ON user_ai_budget_overrides;
DROP TRIGGER IF EXISTS trigger_insert_apikeys ON api_keys;
DROP TRIGGER IF EXISTS trigger_upsert_user_links ON user_links;
DROP TRIGGER IF EXISTS trigger_upsert_user_secrets ON user_secrets;
DROP TRIGGER IF EXISTS trigger_upsert_user_skills ON user_skills;
DROP FUNCTION IF EXISTS fail_if_user_deleted();

CREATE FUNCTION insert_apikey_fail_if_user_deleted() RETURNS trigger
	LANGUAGE plpgsql
AS $$

DECLARE
BEGIN
	IF (NEW.user_id IS NOT NULL) THEN
		IF (SELECT deleted FROM users WHERE id = NEW.user_id LIMIT 1) THEN
			RAISE EXCEPTION 'Cannot create API key for deleted user';
		END IF;
	END IF;
	RETURN NEW;
END;
$$;

CREATE FUNCTION insert_user_links_fail_if_user_deleted() RETURNS trigger
	LANGUAGE plpgsql
AS $$

DECLARE
BEGIN
	IF (NEW.user_id IS NOT NULL) THEN
		IF (SELECT deleted FROM users WHERE id = NEW.user_id LIMIT 1) THEN
			RAISE EXCEPTION 'Cannot create user_link for deleted user';
		END IF;
	END IF;
	RETURN NEW;
END;
$$;

CREATE FUNCTION insert_user_secret_fail_if_user_deleted() RETURNS trigger
	LANGUAGE plpgsql
AS $$

DECLARE
BEGIN
	IF (NEW.user_id IS NOT NULL) THEN
		IF (SELECT deleted FROM users WHERE id = NEW.user_id LIMIT 1) THEN
			RAISE EXCEPTION 'Cannot create user_secret for deleted user';
		END IF;
	END IF;
	RETURN NEW;
END;
$$;

CREATE FUNCTION insert_user_skill_fail_if_user_deleted() RETURNS trigger
    LANGUAGE plpgsql
AS $$

BEGIN
    PERFORM 1
    FROM users
    WHERE id = NEW.user_id
      AND deleted = true
    LIMIT 1;
    IF FOUND THEN
        RAISE EXCEPTION 'Cannot create user_skill for deleted user'
            USING ERRCODE = 'check_violation',
                  CONSTRAINT = 'user_skill_user_deleted';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_insert_apikeys
	BEFORE INSERT ON api_keys
	FOR EACH ROW
EXECUTE FUNCTION insert_apikey_fail_if_user_deleted();

CREATE TRIGGER trigger_upsert_user_links
	BEFORE INSERT OR UPDATE ON user_links
	FOR EACH ROW
EXECUTE FUNCTION insert_user_links_fail_if_user_deleted();

CREATE TRIGGER trigger_upsert_user_secrets
	BEFORE INSERT OR UPDATE ON user_secrets
	FOR EACH ROW
EXECUTE FUNCTION insert_user_secret_fail_if_user_deleted();

CREATE TRIGGER trigger_upsert_user_skills
	BEFORE INSERT OR UPDATE ON user_skills
	FOR EACH ROW
EXECUTE FUNCTION insert_user_skill_fail_if_user_deleted();

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
    -- observe the same pre-insert aggregates and exceed the cap.
    PERFORM 1 FROM users WHERE id = NEW.user_id FOR UPDATE;

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
    -- Serialize skill-cap checks per user so concurrent inserts cannot all
    -- observe the same pre-insert count and exceed the hard limit.
    PERFORM 1
    FROM users
    WHERE id = NEW.user_id
    FOR UPDATE;

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

DROP TRIGGER IF EXISTS trigger_zz_user_secrets_per_user_limits ON user_secrets;
CREATE TRIGGER trigger_user_secrets_per_user_limits
    BEFORE INSERT OR UPDATE ON user_secrets
    FOR EACH ROW
EXECUTE FUNCTION enforce_user_secrets_per_user_limits();

DROP TRIGGER IF EXISTS trigger_zz_user_skills_per_user_limit ON user_skills;
CREATE TRIGGER trigger_user_skills_per_user_limit
    BEFORE INSERT ON user_skills
    FOR EACH ROW
EXECUTE FUNCTION enforce_user_skills_per_user_limit();

DROP FUNCTION IF EXISTS require_read_committed(text, text);
