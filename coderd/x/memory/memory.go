// Package memory owns the Go-side constants for the agent memory database
// schema. TestAgentMemorySchemaConstants walks the trigger caps and check
// constraints from migration 000588_agent_memories.up.sql against these
// values via pg_get_functiondef and pg_get_constraintdef; the content prefix
// width in the list queries is pinned behaviorally by the ContentPrefixWidth
// subtests of TestUserMemories and TestChatMemories.
package memory

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
