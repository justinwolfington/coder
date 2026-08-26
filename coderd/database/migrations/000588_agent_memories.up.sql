-- Creates the user_memories and chat_memories tables for agent memory.
-- User memories are private per-user documents; chat memories belong to a
-- root chat, and access to them is gated on the root chat permissions.
-- Size, count, and path limits must stay in sync with the constants in
-- coderd/x/memory.
--
-- Paths are ASCII-only and case-sensitive by design (matching mux memory
-- semantics): Notes.md and notes.md are distinct documents, and non-ASCII
-- names such as notes/café.md are rejected by the format check.
CREATE TABLE user_memories (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    path text NOT NULL,
    content text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT user_memories_path_size CHECK (octet_length(path) <= 256),
    CONSTRAINT user_memories_path_format CHECK (
        path ~ '^[a-zA-Z0-9_.-]+(/[a-zA-Z0-9_.-]+)*\.md$'
        AND path !~ '(^|/)[.]{1,2}(/|$)'
    ),
    CONSTRAINT user_memories_content_size CHECK (octet_length(content) <= 65536)
);

COMMENT ON TABLE user_memories IS 'Private per-user agent memory documents addressed by scope-relative paths. The owner role retains administrative read and delete access; audit logging treats content as a secret.';

CREATE UNIQUE INDEX user_memories_user_id_path_idx ON user_memories (user_id, path);

CREATE TABLE chat_memories (
    id uuid PRIMARY KEY,
    root_chat_id uuid NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    path text NOT NULL,
    content text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chat_memories_path_size CHECK (octet_length(path) <= 256),
    CONSTRAINT chat_memories_path_format CHECK (
        path ~ '^[a-zA-Z0-9_.-]+(/[a-zA-Z0-9_.-]+)*\.md$'
        AND path !~ '(^|/)[.]{1,2}(/|$)'
    ),
    CONSTRAINT chat_memories_content_size CHECK (octet_length(content) <= 65536)
);

COMMENT ON TABLE chat_memories IS 'Agent memory documents owned by a root chat; access is gated on the root chat permissions. Rows follow the parent chat lifecycle: retention purges of old chats cascade-delete them without per-memory audit events.';

CREATE UNIQUE INDEX chat_memories_root_chat_id_path_idx ON chat_memories (root_chat_id, path);

-- Locking the user row serializes the count check and user soft deletion
-- without conflicting with foreign key validation on other child tables.
--
-- The count cap is only race-free under READ COMMITTED: REPEATABLE READ
-- keeps the transaction snapshot across the lock wait, so a concurrent
-- committed insert stays invisible to count(*) and the cap can be silently
-- exceeded. The trigger therefore rejects REPEATABLE READ outright.
-- SERIALIZABLE stays allowed because SSI detects the read/write dependency
-- between two concurrent cap counts and aborts one transaction. The
-- soft-delete check needs no isolation guard at all: a concurrent
-- soft-delete updates the locked users row, so a waiting SERIALIZABLE
-- transaction fails with a serialization error (40001) instead of reading
-- stale state.
--
-- The lock also imposes an ordering contract on callers (see the query file
-- headers): a transaction that updates or deletes an existing memory row
-- and then inserts another for the same user inverts the lock order against
-- delete_deleted_user_resources (child tuple first, users second) and
-- deadlocks with a concurrent soft-delete (40P01, which coderd does not
-- retry). Take the parent lock first, or do not mix an insert with prior
-- memory-row writes in one transaction.
CREATE FUNCTION enforce_user_memories_insert_invariants() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    user_deleted boolean;
    memory_count int;
    memory_limit constant int := 100;
BEGIN
    IF current_setting('transaction_isolation') = 'repeatable read' THEN
        RAISE EXCEPTION 'user_memories inserts require READ COMMITTED isolation'
            USING ERRCODE = 'check_violation',
                  CONSTRAINT = 'user_memory_insert_isolation';
    END IF;

    SELECT deleted INTO user_deleted
    FROM users
    WHERE id = NEW.user_id
    FOR NO KEY UPDATE;

    -- Fail closed: this trigger reads at its own snapshot while the RI
    -- check re-reads with a fresh snapshot at end of statement, so a parent
    -- committing between the two reads is visible only to the FK check.
    -- Returning NEW here would let that row land without the soft-delete
    -- and cap checks ever running.
    IF NOT FOUND THEN
        RAISE EXCEPTION 'user % does not exist', NEW.user_id
            USING ERRCODE = 'check_violation',
                  CONSTRAINT = 'user_memory_user_required';
    END IF;

    IF user_deleted THEN
        RAISE EXCEPTION 'cannot create user_memory for deleted user %', NEW.user_id
            USING ERRCODE = 'check_violation',
                  CONSTRAINT = 'user_memory_user_deleted';
    END IF;

    SELECT count(*) INTO memory_count
    FROM user_memories
    WHERE user_id = NEW.user_id;
    IF memory_count >= memory_limit THEN
        RAISE EXCEPTION 'user % has reached the user_memories limit of % (current count %)',
            NEW.user_id, memory_limit, memory_count
            USING ERRCODE = 'check_violation',
                  CONSTRAINT = 'user_memories_per_user_limit';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_user_memories_insert_invariants
BEFORE INSERT ON user_memories
FOR EACH ROW
EXECUTE PROCEDURE enforce_user_memories_insert_invariants();

-- Locking the chat row serializes the count check without conflicting with
-- foreign key validation on other child tables. The lock does contend with
-- ordinary UPDATE statements on the same chats row (title changes, archived flips,
-- heartbeat writes); that cost is accepted because memory inserts are
-- low-frequency and capped.
--
-- The count cap is only race-free under READ COMMITTED (see the isolation
-- note on enforce_user_memories_insert_invariants, including why
-- SERIALIZABLE stays allowed); REPEATABLE READ is rejected.
--
-- The lock also imposes an ordering contract on callers (see the query file
-- headers): a transaction that updates or deletes an existing memory row
-- and then inserts another for the same root chat inverts the lock order
-- against hard chat deletion (child tuple first, chats second; the
-- retention purge cascade takes chats first) and deadlocks (40P01, which
-- coderd does not retry). Take the parent lock first, or do not mix an
-- insert with prior memory-row writes in one transaction.
CREATE FUNCTION enforce_chat_memories_insert_invariants() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    referenced_parent_chat_id uuid;
    referenced_root_chat_id uuid;
    memory_count int;
    memory_limit constant int := 100;
BEGIN
    IF current_setting('transaction_isolation') = 'repeatable read' THEN
        RAISE EXCEPTION 'chat_memories inserts require READ COMMITTED isolation'
            USING ERRCODE = 'check_violation',
                  CONSTRAINT = 'chat_memory_insert_isolation';
    END IF;

    SELECT parent_chat_id, root_chat_id
    INTO referenced_parent_chat_id, referenced_root_chat_id
    FROM chats
    WHERE id = NEW.root_chat_id
    FOR NO KEY UPDATE;

    -- Fail closed: this trigger reads at its own snapshot while the RI
    -- check re-reads with a fresh snapshot at end of statement, so a chat
    -- committing between the two reads is visible only to the FK check.
    -- Returning NEW here would let a memory land under an unvalidated,
    -- possibly subagent, chat.
    IF NOT FOUND THEN
        RAISE EXCEPTION 'chat % does not exist', NEW.root_chat_id
            USING ERRCODE = 'check_violation',
                  CONSTRAINT = 'chat_memory_root_chat_required';
    END IF;

    -- chats.parent_chat_id / chats.root_chat_id are immutable through the
    -- Store, but their ON DELETE SET NULL FKs can flip them to NULL when an
    -- ancestor chat is hard-deleted by retention purges. Chat memories under
    -- a purged root are cascade-deleted with it, so no memory row survives
    -- into a promoted subagent namespace; a subagent chat that outlives its
    -- purged root does get both columns nulled and passes this check from
    -- then on, becoming a root chat with a fresh, initially empty namespace.
    -- Both columns are checked because they can be nulled independently:
    -- purging an intermediate subagent chat leaves its children with
    -- parent_chat_id NULL while root_chat_id still points at the real root.
    IF referenced_parent_chat_id IS NOT NULL OR referenced_root_chat_id IS NOT NULL THEN
        RAISE EXCEPTION 'chat % is not a root chat', NEW.root_chat_id
            USING ERRCODE = 'check_violation',
                  CONSTRAINT = 'chat_memory_root_chat_required';
    END IF;

    SELECT count(*) INTO memory_count
    FROM chat_memories
    WHERE root_chat_id = NEW.root_chat_id;
    IF memory_count >= memory_limit THEN
        RAISE EXCEPTION 'chat % has reached the chat_memories limit of % (current count %)',
            NEW.root_chat_id, memory_limit, memory_count
            USING ERRCODE = 'check_violation',
                  CONSTRAINT = 'chat_memories_per_root_chat_limit';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_chat_memories_insert_invariants
BEFORE INSERT ON chat_memories
FOR EACH ROW
EXECUTE PROCEDURE enforce_chat_memories_insert_invariants();

-- Extend the soft-delete cleanup trigger to also wipe user_memories.
-- user_memories.user_id has ON DELETE CASCADE, but Coder soft-deletes
-- users by flipping users.deleted instead of removing the row, so the
-- FK cascade never fires and memories would otherwise survive deletion.
CREATE OR REPLACE FUNCTION delete_deleted_user_resources() RETURNS trigger
    LANGUAGE plpgsql
AS $$
DECLARE
BEGIN
    IF (NEW.deleted) THEN
        -- Remove their api_keys.
        DELETE FROM api_keys
        WHERE user_id = OLD.id;

        -- Remove their user_links.
        -- Their login_type is preserved in the users table.
        -- Matching this user back to the link can still be done by their
        -- email if the account is undeleted. Although that is not a guarantee.
        DELETE FROM user_links
        WHERE user_id = OLD.id;

        -- Remove their user_secrets.
        -- user_secrets.user_id has ON DELETE CASCADE, but soft-delete
        -- does not remove the users row so the FK cascade never fires.
        DELETE FROM user_secrets
        WHERE user_id = OLD.id;

        -- Remove their user AI provider keys.
        -- user_ai_provider_keys.user_id has ON DELETE CASCADE, but soft-delete
        -- does not remove the users row so the FK cascade never fires.
        DELETE FROM user_ai_provider_keys
        WHERE user_id = OLD.id;

        -- Remove their organization memberships.
        -- This also triggers group membership cleanup via
        -- trigger_delete_group_members_on_org_member_delete.
        DELETE FROM organization_members
        WHERE user_id = OLD.id;

        -- Remove their user_skills.
        -- user_skills.user_id has ON DELETE CASCADE, but soft-delete
        -- does not remove the users row so the FK cascade never fires.
        DELETE FROM user_skills
        WHERE user_id = OLD.id;

        -- Remove their user_memories.
        -- user_memories.user_id has ON DELETE CASCADE, but soft-delete
        -- does not remove the users row so the FK cascade never fires.
        DELETE FROM user_memories
        WHERE user_id = OLD.id;
    END IF;
    RETURN NEW;
END;
$$;

ALTER TYPE resource_type ADD VALUE IF NOT EXISTS 'user_memory';
ALTER TYPE resource_type ADD VALUE IF NOT EXISTS 'chat_memory';

-- No chat_memory API key scopes are added; chat memories are authorized
-- through the root chat's existing chat scopes.
ALTER TYPE api_key_scope ADD VALUE IF NOT EXISTS 'user_memory:create';
ALTER TYPE api_key_scope ADD VALUE IF NOT EXISTS 'user_memory:read';
ALTER TYPE api_key_scope ADD VALUE IF NOT EXISTS 'user_memory:update';
ALTER TYPE api_key_scope ADD VALUE IF NOT EXISTS 'user_memory:delete';
ALTER TYPE api_key_scope ADD VALUE IF NOT EXISTS 'user_memory:*';
