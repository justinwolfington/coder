// Package memory owns the Go-side constants for the agent memory database
// schema (the user_memories and chat_memories tables and their
// enforce_*_insert_invariants triggers). TestAgentMemorySchemaConstants
// walks the trigger caps, trigger-raised constraint names, and check
// constraints against these values via pg_get_functiondef and
// pg_get_constraintdef; the content prefix width in the list queries is
// pinned behaviorally by the ContentPrefixWidth subtests of TestUserMemories
// and TestChatMemories.
package memory

import "github.com/coder/coder/v2/coderd/database"

// Constraint names raised by the agent memory triggers. RAISE ... USING
// CONSTRAINT names never appear in pg_constraint, so the generated
// check_constraint.go cannot own them; they are declared here and pinned
// against pg_get_functiondef by TestAgentMemorySchemaConstants.
const (
	// UserMemoryInsertIsolationConstraint rejects inserts at any isolation
	// level other than READ COMMITTED, where the cap count is race-free.
	UserMemoryInsertIsolationConstraint database.CheckConstraint = "user_memory_insert_isolation"
	// UserMemoryUserRequiredConstraint rejects inserts whose user row is
	// invisible to the trigger snapshot (fail closed).
	UserMemoryUserRequiredConstraint database.CheckConstraint = "user_memory_user_required"
	// UserMemoryUserDeletedConstraint rejects inserts for soft-deleted users.
	UserMemoryUserDeletedConstraint database.CheckConstraint = "user_memory_user_deleted"
	// UserMemoriesPerUserLimitConstraint rejects inserts beyond
	// MaxUserMemoriesPerUser.
	UserMemoriesPerUserLimitConstraint database.CheckConstraint = "user_memories_per_user_limit"
	// UserMemoryOwnerImmutableConstraint rejects updates that reassign
	// user_memories.user_id.
	UserMemoryOwnerImmutableConstraint database.CheckConstraint = "user_memory_owner_immutable"
	// ChatMemoryInsertIsolationConstraint is the chat-side twin of
	// UserMemoryInsertIsolationConstraint.
	ChatMemoryInsertIsolationConstraint database.CheckConstraint = "chat_memory_insert_isolation"
	// ChatMemoryRootChatRequiredConstraint rejects inserts whose chat is
	// missing, invisible, or not a root chat.
	ChatMemoryRootChatRequiredConstraint database.CheckConstraint = "chat_memory_root_chat_required"
	// ChatMemoriesPerRootChatLimitConstraint rejects inserts beyond
	// MaxChatMemoriesPerRootChat.
	ChatMemoriesPerRootChatLimitConstraint database.CheckConstraint = "chat_memories_per_root_chat_limit"
	// ChatMemoryOwnerImmutableConstraint rejects updates that reassign
	// chat_memories.root_chat_id.
	ChatMemoryOwnerImmutableConstraint database.CheckConstraint = "chat_memory_owner_immutable"
)

// MaxUserMemoriesPerUser is the maximum number of memory documents a user may
// own, enforced by the enforce_user_memories_insert_invariants trigger.
const MaxUserMemoriesPerUser = 100

// MaxChatMemoriesPerRootChat is the maximum number of memory documents a root
// chat may own, enforced by the enforce_chat_memories_insert_invariants
// trigger.
const MaxChatMemoriesPerRootChat = 100

// MaxMemoryPathBytes is the maximum memory path size in bytes, enforced by
// the user_memories_path_size and chat_memories_path_size check constraints.
const MaxMemoryPathBytes = 256

// MaxMemoryContentBytes is the maximum memory content size in bytes, enforced
// by the user_memories_content_size and chat_memories_content_size check
// constraints.
const MaxMemoryContentBytes = 65536

// ContentPrefixChars is the number of characters (not bytes; character
// slicing preserves UTF-8) of memory content returned by the path-prefix list
// queries, sized to cover YAML frontmatter without shipping full documents.
const ContentPrefixChars = 4096
