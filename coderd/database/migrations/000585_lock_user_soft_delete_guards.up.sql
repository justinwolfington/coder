-- Close the insert-vs-soft-delete race in the four guard triggers that read
-- users.deleted: insert_apikey_fail_if_user_deleted,
-- insert_user_links_fail_if_user_deleted,
-- insert_user_secret_fail_if_user_deleted, and
-- insert_user_skill_fail_if_user_deleted. All four previously read
-- users.deleted without a lock, so an in-flight insert could observe
-- deleted = false, a concurrent soft-delete UPDATE (and its
-- delete_deleted_user_resources cleanup) could commit, and the insert could
-- then commit afterwards, resurrecting a row for a soft-deleted user. For
-- api_keys that resurrects a live session token on an account the operator
-- believes they deleted.
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
