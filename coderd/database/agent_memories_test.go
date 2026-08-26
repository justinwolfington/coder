package database_test

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"testing"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"

	"github.com/coder/coder/v2/coderd/database"
	"github.com/coder/coder/v2/coderd/database/dbgen"
	"github.com/coder/coder/v2/coderd/database/dbtestutil"
	"github.com/coder/coder/v2/coderd/x/memory"
	"github.com/coder/coder/v2/testutil"
)

var invalidMemoryPaths = []string{
	"", "no-extension", "dir/", "/absolute.md", "a//b.md",
	"trailing/.md", "spaces in path.md", "note.txt",
	"./local.md", "../escape.md", "dir/./local.md", "dir/../escape.md",
	// Paths are ASCII-only by design (matching the user_skills name policy);
	// non-Latin names are rejected even though content accepts any UTF-8.
	"notes/café.md",
}

func TestAgentMemorySchemaConstants(t *testing.T) {
	t.Parallel()
	if testing.Short() {
		t.SkipNow()
	}

	ctx := testutil.Context(t, testutil.WaitMedium)
	_, _, sqlDB := dbtestutil.NewDBWithSQLDB(t)

	for trigger, limit := range map[string]int{
		"enforce_user_memories_insert_invariants": memory.MaxUserMemoriesPerUser,
		"enforce_chat_memories_insert_invariants": memory.MaxChatMemoriesPerRootChat,
	} {
		var triggerDef string
		err := sqlDB.QueryRowContext(ctx,
			`SELECT pg_get_functiondef($1::regproc)`, trigger,
		).Scan(&triggerDef)
		require.NoError(t, err)
		require.Contains(t, triggerDef, fmt.Sprintf(
			"memory_limit constant int := %d", limit,
		))
	}

	// The trigger-raised constraint names have no pg_constraint row, so the
	// generated check_constraint.go cannot pin them; the constants in
	// coderd/x/memory are pinned against the function bodies instead.
	for trigger, constraints := range map[string][]database.CheckConstraint{
		"enforce_user_memories_insert_invariants": {
			memory.UserMemoryInsertIsolationConstraint,
			memory.UserMemoryUserRequiredConstraint,
			memory.UserMemoryUserDeletedConstraint,
			memory.UserMemoriesPerUserLimitConstraint,
		},
		"enforce_user_memories_owner_immutable": {
			memory.UserMemoryOwnerImmutableConstraint,
		},
		"enforce_chat_memories_insert_invariants": {
			memory.ChatMemoryInsertIsolationConstraint,
			memory.ChatMemoryRootChatRequiredConstraint,
			memory.ChatMemoriesPerRootChatLimitConstraint,
		},
		"enforce_chat_memories_owner_immutable": {
			memory.ChatMemoryOwnerImmutableConstraint,
		},
	} {
		var triggerDef string
		err := sqlDB.QueryRowContext(ctx,
			`SELECT pg_get_functiondef($1::regproc)`, trigger,
		).Scan(&triggerDef)
		require.NoError(t, err)
		for _, constraint := range constraints {
			require.Contains(t, triggerDef, fmt.Sprintf("CONSTRAINT = '%s'", constraint))
		}
	}

	pathFormat := `^[a-zA-Z0-9_.-]+(/[a-zA-Z0-9_.-]+)*\.md$`
	pathSize := fmt.Sprintf("octet_length(path) <= %d", memory.MaxMemoryPathBytes)
	contentSize := fmt.Sprintf("octet_length(content) <= %d", memory.MaxMemoryContentBytes)
	constraints := map[database.CheckConstraint]string{
		database.CheckUserMemoriesPathSize:    pathSize,
		database.CheckUserMemoriesPathFormat:  pathFormat,
		database.CheckUserMemoriesContentSize: contentSize,
		database.CheckChatMemoriesPathSize:    pathSize,
		database.CheckChatMemoriesPathFormat:  pathFormat,
		database.CheckChatMemoriesContentSize: contentSize,
	}
	for constraint, expected := range constraints {
		t.Run(string(constraint), func(t *testing.T) {
			t.Parallel()

			ctx := testutil.Context(t, testutil.WaitMedium)
			var constraintDef string
			err := sqlDB.QueryRowContext(ctx,
				`SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = $1`,
				constraint,
			).Scan(&constraintDef)
			require.NoError(t, err)
			require.Contains(t, constraintDef, expected)
		})
	}
}

func TestUserMemories(t *testing.T) {
	t.Parallel()
	if testing.Short() {
		t.SkipNow()
	}

	db, _, sqlDB := dbtestutil.NewDBWithSQLDB(t)

	insertMemory := func(ctx context.Context, userID uuid.UUID, path string) (database.UserMemory, error) {
		return db.InsertUserMemory(ctx, database.InsertUserMemoryParams{
			ID:      uuid.New(),
			UserID:  userID,
			Path:    path,
			Content: "content of " + path,
		})
	}

	t.Run("PathFormatRejected", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		user := dbgen.User(t, db, database.User{})
		for _, invalid := range invalidMemoryPaths {
			_, err := insertMemory(ctx, user.ID, invalid)
			require.Error(t, err, "path %q should be rejected", invalid)
			require.True(t, database.IsCheckViolation(err, database.CheckUserMemoriesPathFormat), "path %q: %v", invalid, err)
		}
	})

	t.Run("DuplicatePathRejected", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		user := dbgen.User(t, db, database.User{})
		_, err := insertMemory(ctx, user.ID, "preferences/go-style.md")
		require.NoError(t, err)
		_, err = insertMemory(ctx, user.ID, "preferences/go-style.md")
		require.Error(t, err)
		require.True(t, database.IsUniqueViolation(err, database.UniqueUserMemoriesUserIDPathIndex))
	})

	t.Run("ContentSizeRejected", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		user := dbgen.User(t, db, database.User{})
		_, err := db.InsertUserMemory(ctx, database.InsertUserMemoryParams{
			ID:      uuid.New(),
			UserID:  user.ID,
			Path:    "big.md",
			Content: strings.Repeat("a", memory.MaxMemoryContentBytes+1),
		})
		require.Error(t, err)
		require.True(t, database.IsCheckViolation(err, database.CheckUserMemoriesContentSize), "got: %v", err)
	})

	t.Run("PathSizeRejected", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		user := dbgen.User(t, db, database.User{})
		// One byte past the cap while still matching the format regex.
		_, err := insertMemory(ctx, user.ID, strings.Repeat("a", memory.MaxMemoryPathBytes-len(".md")+1)+".md")
		require.Error(t, err)
		require.True(t, database.IsCheckViolation(err, database.CheckUserMemoriesPathSize), "got: %v", err)
	})

	t.Run("CaseSensitivePaths", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		user := dbgen.User(t, db, database.User{})
		// Paths are case-sensitive by design (matching mux memory semantics):
		// a case-only pair addresses two distinct documents.
		_, err := insertMemory(ctx, user.ID, "Notes.md")
		require.NoError(t, err)
		_, err = insertMemory(ctx, user.ID, "notes.md")
		require.NoError(t, err)
		list, err := db.ListUserMemoriesByUserID(ctx, user.ID)
		require.NoError(t, err)
		require.Len(t, list, 2)
		// COLLATE "C" byte order puts uppercase first; a linguistic collation
		// such as en_US.utf8 would flip this pair, so the assertion keeps the
		// explicit collation on the list queries load-bearing.
		require.Equal(t, "Notes.md", list[0].Path)
		require.Equal(t, "notes.md", list[1].Path)
	})

	t.Run("ContentPrefixWidth", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		user := dbgen.User(t, db, database.User{})
		// Multi-byte content proves the prefix is sliced by characters, not
		// bytes, so a frontmatter block is never split mid-rune.
		content := strings.Repeat("é", memory.ContentPrefixChars) + "tail"
		_, err := db.InsertUserMemory(ctx, database.InsertUserMemoryParams{
			ID:      uuid.New(),
			UserID:  user.ID,
			Path:    "big-prefix.md",
			Content: content,
		})
		require.NoError(t, err)

		prefixed, err := db.ListUserMemoriesByUserIDAndPathPrefix(ctx, database.ListUserMemoriesByUserIDAndPathPrefixParams{
			UserID:     user.ID,
			PathPrefix: "big-prefix",
		})
		require.NoError(t, err)
		require.Len(t, prefixed, 1)
		require.Equal(t, memory.ContentPrefixChars, utf8.RuneCountInString(prefixed[0].ContentPrefix))
		require.True(t, strings.HasPrefix(content, prefixed[0].ContentPrefix))
	})

	t.Run("NonReadCommittedRejected", func(t *testing.T) {
		t.Parallel()

		// The count cap is race-free only under READ COMMITTED, which
		// re-reads committed state after the parent-row lock wait. Every
		// other level keeps its snapshot across the wait, and SSI does not
		// track a READ COMMITTED writer against a SERIALIZABLE reader, so
		// both non-default levels can silently overshoot the cap in mixed
		// pairings; the trigger rejects them loudly instead.
		for name, level := range map[string]sql.IsolationLevel{
			"RepeatableRead": sql.LevelRepeatableRead,
			"Serializable":   sql.LevelSerializable,
		} {
			t.Run(name, func(t *testing.T) {
				t.Parallel()
				ctx := testutil.Context(t, testutil.WaitLong)
				user := dbgen.User(t, db, database.User{})

				tx, err := sqlDB.BeginTx(ctx, &sql.TxOptions{Isolation: level})
				require.NoError(t, err)
				defer func() { _ = tx.Rollback() }()
				_, err = tx.ExecContext(ctx, `
					INSERT INTO user_memories (id, user_id, path, content)
					VALUES ($1, $2, 'isolation.md', 'content')
				`, uuid.New(), user.ID)
				require.Error(t, err)
				require.True(t, database.IsCheckViolation(err, memory.UserMemoryInsertIsolationConstraint), "got: %v", err)
			})
		}
	})

	t.Run("OwnerImmutable", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		owner := dbgen.User(t, db, database.User{})
		other := dbgen.User(t, db, database.User{})
		_, err := insertMemory(ctx, owner.ID, "owned.md")
		require.NoError(t, err)

		// The insert invariants fire BEFORE INSERT only, so a reassignable
		// owner column would bypass the soft-delete and cap checks; the
		// owner is immutable instead.
		_, err = sqlDB.ExecContext(ctx,
			`UPDATE user_memories SET user_id = $1 WHERE user_id = $2`, other.ID, owner.ID)
		require.Error(t, err)
		require.True(t, database.IsCheckViolation(err, memory.UserMemoryOwnerImmutableConstraint), "got: %v", err)
	})

	t.Run("UpdateTakesNoUserLock", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		user := dbgen.User(t, db, database.User{})
		_, err := insertMemory(ctx, user.ID, "gate.md")
		require.NoError(t, err)

		lockTx, err := sqlDB.BeginTx(ctx, nil)
		require.NoError(t, err)
		defer func() { _ = lockTx.Rollback() }()
		var lockedUserID uuid.UUID
		err = lockTx.QueryRowContext(ctx,
			`SELECT id FROM users WHERE id = $1 FOR NO KEY UPDATE`, user.ID,
		).Scan(&lockedUserID)
		require.NoError(t, err)
		require.Equal(t, user.ID, lockedUserID)

		// The trigger fires BEFORE INSERT only; widening it to UPDATE would
		// block this edit on the locked users row. The lock_timeout bounds
		// the wait so blocking fails the test instead of passing after the
		// context deadline rolls back lockTx and releases the lock.
		updateConn, err := sqlDB.Conn(ctx)
		require.NoError(t, err)
		t.Cleanup(func() { _ = updateConn.Close() })
		_, err = updateConn.ExecContext(ctx, `SET lock_timeout = '2s'`)
		require.NoError(t, err)
		// Reset before the connection returns to the pool; database/sql
		// does not reset session state, so the timeout would leak into
		// whichever parallel sibling draws this connection next. Cleanups
		// run LIFO, so this runs before Close.
		t.Cleanup(func() { _, _ = updateConn.ExecContext(context.Background(), `RESET lock_timeout`) })
		_, err = updateConn.ExecContext(ctx,
			`UPDATE user_memories SET content = 'edited' WHERE user_id = $1`, user.ID)
		require.NoError(t, err, "memory updates must not wait on the users row")
	})

	t.Run("GetAndList", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		user := dbgen.User(t, db, database.User{})
		mem, err := insertMemory(ctx, user.ID, "preferences/go-style.md")
		require.NoError(t, err)
		_, err = insertMemory(ctx, user.ID, "notes/debugging.md")
		require.NoError(t, err)
		_, err = insertMemory(ctx, user.ID, "root.md")
		require.NoError(t, err)

		got, err := db.GetUserMemoryByUserIDAndPath(ctx, database.GetUserMemoryByUserIDAndPathParams{
			UserID: user.ID,
			Path:   "preferences/go-style.md",
		})
		require.NoError(t, err)
		require.Equal(t, mem.ID, got.ID)

		byID, err := db.GetUserMemoryByID(ctx, mem.ID)
		require.NoError(t, err)
		require.Equal(t, mem.Path, byID.Path)

		list, err := db.ListUserMemoriesByUserID(ctx, user.ID)
		require.NoError(t, err)
		require.Len(t, list, 3)
		require.Equal(t, "notes/debugging.md", list[0].Path)
		require.Equal(t, "preferences/go-style.md", list[1].Path)
		require.Equal(t, "root.md", list[2].Path)

		prefixed, err := db.ListUserMemoriesByUserIDAndPathPrefix(ctx, database.ListUserMemoriesByUserIDAndPathPrefixParams{
			UserID:     user.ID,
			PathPrefix: "preferences/",
		})
		require.NoError(t, err)
		require.Len(t, prefixed, 1)
		require.Equal(t, "content of preferences/go-style.md", prefixed[0].ContentPrefix)

		// Unlike the prefix delete, an empty prefix previews every memory.
		all, err := db.ListUserMemoriesByUserIDAndPathPrefix(ctx, database.ListUserMemoriesByUserIDAndPathPrefixParams{
			UserID:     user.ID,
			PathPrefix: "",
		})
		require.NoError(t, err)
		require.Len(t, all, 3, "an empty prefix must preview every memory")
	})

	t.Run("UpdateRenameDelete", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		user := dbgen.User(t, db, database.User{})
		inserted, err := insertMemory(ctx, user.ID, "root.md")
		require.NoError(t, err)
		_, err = insertMemory(ctx, user.ID, "notes/debugging.md")
		require.NoError(t, err)
		_, err = insertMemory(ctx, user.ID, "keep.md")
		require.NoError(t, err)

		_, err = db.UpdateUserMemoryByUserIDAndPath(ctx, database.UpdateUserMemoryByUserIDAndPathParams{
			UserID:  user.ID,
			Path:    "root.md",
			Content: strings.Repeat("a", memory.MaxMemoryContentBytes+1),
		})
		require.Error(t, err)
		require.True(t, database.IsCheckViolation(err, database.CheckUserMemoriesContentSize), "got: %v", err)

		_, err = db.RenameUserMemoryByUserIDAndPath(ctx, database.RenameUserMemoryByUserIDAndPathParams{
			UserID:  user.ID,
			OldPath: "root.md",
			NewPath: "../escape.md",
		})
		require.Error(t, err)
		require.True(t, database.IsCheckViolation(err, database.CheckUserMemoriesPathFormat), "got: %v", err)

		_, err = db.RenameUserMemoryByUserIDAndPath(ctx, database.RenameUserMemoryByUserIDAndPathParams{
			UserID:  user.ID,
			OldPath: "root.md",
			NewPath: "keep.md",
		})
		require.Error(t, err)
		require.True(t, database.IsUniqueViolation(err, database.UniqueUserMemoriesUserIDPathIndex))

		_, err = db.UpdateUserMemoryByUserIDAndPath(ctx, database.UpdateUserMemoryByUserIDAndPathParams{
			UserID:  user.ID,
			Path:    "missing.md",
			Content: "updated",
		})
		require.ErrorIs(t, err, sql.ErrNoRows)

		_, err = db.RenameUserMemoryByUserIDAndPath(ctx, database.RenameUserMemoryByUserIDAndPathParams{
			UserID:  user.ID,
			OldPath: "missing.md",
			NewPath: "new.md",
		})
		require.ErrorIs(t, err, sql.ErrNoRows)

		// pg_sleep guarantees now() advances past the insert timestamp before
		// the mutations, so the updated_at assertions below are deterministic.
		_, err = sqlDB.ExecContext(ctx, `SELECT pg_sleep(0.001)`)
		require.NoError(t, err)

		updated, err := db.UpdateUserMemoryByUserIDAndPath(ctx, database.UpdateUserMemoryByUserIDAndPathParams{
			UserID:  user.ID,
			Path:    "root.md",
			Content: "updated",
		})
		require.NoError(t, err)
		require.Equal(t, "updated", updated.Content)
		require.True(t, updated.UpdatedAt.After(inserted.UpdatedAt), "update must advance updated_at")

		_, err = sqlDB.ExecContext(ctx, `SELECT pg_sleep(0.001)`)
		require.NoError(t, err)

		renamed, err := db.RenameUserMemoryByUserIDAndPath(ctx, database.RenameUserMemoryByUserIDAndPathParams{
			UserID:  user.ID,
			OldPath: "root.md",
			NewPath: "renamed.md",
		})
		require.NoError(t, err)
		require.Equal(t, "renamed.md", renamed.Path)
		require.True(t, renamed.UpdatedAt.After(updated.UpdatedAt), "rename must advance updated_at")

		deleted, err := db.DeleteUserMemoryByUserIDAndPath(ctx, database.DeleteUserMemoryByUserIDAndPathParams{
			UserID: user.ID,
			Path:   "renamed.md",
		})
		require.NoError(t, err)
		require.Equal(t, renamed.ID, deleted.ID)

		deletedByEmptyPrefix, err := db.DeleteUserMemoriesByUserIDAndPathPrefix(ctx, database.DeleteUserMemoriesByUserIDAndPathPrefixParams{
			UserID:     user.ID,
			PathPrefix: "",
		})
		require.NoError(t, err)
		require.Empty(t, deletedByEmptyPrefix)

		deletedMany, err := db.DeleteUserMemoriesByUserIDAndPathPrefix(ctx, database.DeleteUserMemoriesByUserIDAndPathPrefixParams{
			UserID:     user.ID,
			PathPrefix: "notes/",
		})
		require.NoError(t, err)
		require.Len(t, deletedMany, 1)

		list, err := db.ListUserMemoriesByUserID(ctx, user.ID)
		require.NoError(t, err)
		require.Len(t, list, 1)
		require.Equal(t, "keep.md", list[0].Path)
	})

	t.Run("MissingUserRejected", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		// The trigger fails closed on a missing parent row instead of
		// deferring to the FK check: an uncommitted user would be invisible
		// to the trigger's locked read but visible to the FK, which would
		// let the insert skip the soft-delete and cap checks entirely.
		_, err := insertMemory(ctx, uuid.New(), "orphan.md")
		require.Error(t, err)
		require.True(t, database.IsCheckViolation(err, memory.UserMemoryUserRequiredConstraint), "got: %v", err)
	})

	t.Run("SoftDeletedUserRejected", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		deletedUser := dbgen.User(t, db, database.User{Deleted: true})
		_, err := insertMemory(ctx, deletedUser.ID, "rejected.md")
		require.Error(t, err)
		require.True(t, database.IsCheckViolation(err, memory.UserMemoryUserDeletedConstraint), "got: %v", err)
	})

	t.Run("SoftDeleteWinsConcurrentInsert", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		user := dbgen.User(t, db, database.User{})

		// Hold the lock the trigger takes, soft-delete while the insert is
		// blocked, and expect the insert to observe the deletion.
		err := runLockRace(ctx, t, sqlDB, sql.LevelDefault,
			[]stmt{{`SELECT id FROM users WHERE id = $1 FOR NO KEY UPDATE`, []any{user.ID}}},
			stmt{`
				INSERT INTO user_memories (id, user_id, path, content)
				VALUES ($1, $2, 'concurrent.md', 'content')
			`, []any{uuid.New(), user.ID}},
			[]stmt{{`UPDATE users SET deleted = true WHERE id = $1`, []any{user.ID}}},
		)
		require.Error(t, err)
		require.True(t, database.IsCheckViolation(err, memory.UserMemoryUserDeletedConstraint), "got: %v", err)

		list, err := db.ListUserMemoriesByUserID(ctx, user.ID)
		require.NoError(t, err)
		require.Empty(t, list)
	})

	t.Run("SoftDeleteCleansMemories", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		doomed := dbgen.User(t, db, database.User{})
		_, err := insertMemory(ctx, doomed.ID, "cleanup.md")
		require.NoError(t, err)

		err = db.UpdateUserDeletedByID(ctx, doomed.ID)
		require.NoError(t, err)

		list, err := db.ListUserMemoriesByUserID(ctx, doomed.ID)
		require.NoError(t, err)
		require.Empty(t, list)
	})

	t.Run("PerUserLimit", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		limited := dbgen.User(t, db, database.User{})
		for i := range memory.MaxUserMemoriesPerUser {
			_, err := insertMemory(ctx, limited.ID, fmt.Sprintf("memory-%03d.md", i))
			require.NoError(t, err)
		}
		_, err := insertMemory(ctx, limited.ID, "one-too-many.md")
		require.Error(t, err)
		require.True(t, database.IsCheckViolation(err, memory.UserMemoriesPerUserLimitConstraint), "got: %v", err)
	})

	t.Run("ConcurrentInsertPerUserLimit", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		limited := dbgen.User(t, db, database.User{})
		for i := range memory.MaxUserMemoriesPerUser - 1 {
			_, err := insertMemory(ctx, limited.ID, fmt.Sprintf("memory-%03d.md", i))
			require.NoError(t, err)
		}

		// The insert filling the cap holds the parent-row lock; the racing
		// insert must re-count after the commit and hit the cap.
		err := runLockRace(ctx, t, sqlDB, sql.LevelDefault,
			[]stmt{{`
				INSERT INTO user_memories (id, user_id, path, content)
				VALUES ($1, $2, 'memory-099.md', 'content')
			`, []any{uuid.New(), limited.ID}}},
			stmt{`
				INSERT INTO user_memories (id, user_id, path, content)
				VALUES ($1, $2, 'one-too-many.md', 'content')
			`, []any{uuid.New(), limited.ID}},
			nil,
		)
		require.Error(t, err)
		require.True(t, database.IsCheckViolation(err, memory.UserMemoriesPerUserLimitConstraint), "got: %v", err)

		list, err := db.ListUserMemoriesByUserID(ctx, limited.ID)
		require.NoError(t, err)
		require.Len(t, list, memory.MaxUserMemoriesPerUser)
	})
}

func TestChatMemories(t *testing.T) {
	t.Parallel()
	if testing.Short() {
		t.SkipNow()
	}

	db, _, sqlDB := dbtestutil.NewDBWithSQLDB(t)

	insertMemory := func(ctx context.Context, rootChatID uuid.UUID, path string) (database.ChatMemory, error) {
		return db.InsertChatMemory(ctx, database.InsertChatMemoryParams{
			ID:         uuid.New(),
			RootChatID: rootChatID,
			Path:       path,
			Content:    "content of " + path,
		})
	}

	t.Run("PathFormatRejected", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		chat := insertTestChat(t, db)
		for _, invalid := range invalidMemoryPaths {
			_, err := insertMemory(ctx, chat.ID, invalid)
			require.Error(t, err, "path %q should be rejected", invalid)
			require.True(t, database.IsCheckViolation(err, database.CheckChatMemoriesPathFormat), "path %q: %v", invalid, err)
		}
	})

	t.Run("ContentSizeRejected", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		chat := insertTestChat(t, db)
		_, err := db.InsertChatMemory(ctx, database.InsertChatMemoryParams{
			ID:         uuid.New(),
			RootChatID: chat.ID,
			Path:       "big.md",
			Content:    strings.Repeat("a", memory.MaxMemoryContentBytes+1),
		})
		require.Error(t, err)
		require.True(t, database.IsCheckViolation(err, database.CheckChatMemoriesContentSize), "got: %v", err)
	})

	t.Run("PathSizeRejected", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		chat := insertTestChat(t, db)
		// One byte past the cap while still matching the format regex.
		_, err := insertMemory(ctx, chat.ID, strings.Repeat("a", memory.MaxMemoryPathBytes-len(".md")+1)+".md")
		require.Error(t, err)
		require.True(t, database.IsCheckViolation(err, database.CheckChatMemoriesPathSize), "got: %v", err)
	})

	t.Run("CaseSensitivePaths", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		chat := insertTestChat(t, db)
		// Paths are case-sensitive by design (matching mux memory semantics):
		// a case-only pair addresses two distinct documents.
		_, err := insertMemory(ctx, chat.ID, "Notes.md")
		require.NoError(t, err)
		_, err = insertMemory(ctx, chat.ID, "notes.md")
		require.NoError(t, err)
		list, err := db.ListChatMemoriesByRootChatID(ctx, chat.ID)
		require.NoError(t, err)
		require.Len(t, list, 2)
		// COLLATE "C" byte order puts uppercase first; a linguistic collation
		// such as en_US.utf8 would flip this pair, so the assertion keeps the
		// explicit collation on the list queries load-bearing.
		require.Equal(t, "Notes.md", list[0].Path)
		require.Equal(t, "notes.md", list[1].Path)
	})

	t.Run("ContentPrefixWidth", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		chat := insertTestChat(t, db)
		// Multi-byte content proves the prefix is sliced by characters, not
		// bytes, so a frontmatter block is never split mid-rune.
		content := strings.Repeat("é", memory.ContentPrefixChars) + "tail"
		_, err := db.InsertChatMemory(ctx, database.InsertChatMemoryParams{
			ID:         uuid.New(),
			RootChatID: chat.ID,
			Path:       "big-prefix.md",
			Content:    content,
		})
		require.NoError(t, err)

		prefixed, err := db.ListChatMemoriesByRootChatIDAndPathPrefix(ctx, database.ListChatMemoriesByRootChatIDAndPathPrefixParams{
			RootChatID: chat.ID,
			PathPrefix: "big-prefix",
		})
		require.NoError(t, err)
		require.Len(t, prefixed, 1)
		require.Equal(t, memory.ContentPrefixChars, utf8.RuneCountInString(prefixed[0].ContentPrefix))
		require.True(t, strings.HasPrefix(content, prefixed[0].ContentPrefix))
	})

	t.Run("MissingChatRejected", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		// The trigger fails closed on a missing parent row instead of
		// deferring to the FK check: an uncommitted chat would be invisible
		// to the trigger's locked read but visible to the FK, which would
		// let a memory land under an unvalidated, possibly subagent, chat.
		_, err := insertMemory(ctx, uuid.New(), "orphan.md")
		require.Error(t, err)
		require.True(t, database.IsCheckViolation(err, memory.ChatMemoryRootChatRequiredConstraint), "got: %v", err)
	})

	t.Run("SubagentChatRejected", func(t *testing.T) {
		t.Parallel()

		// The guard checks parent_chat_id and root_chat_id independently
		// because the ON DELETE SET NULL hierarchy FKs can null either one
		// on its own: hard-deleting an intermediate subagent chat nulls a
		// grandchild's parent_chat_id (RootOnly), and purging a root chat
		// nulls a grandchild's root_chat_id while parent_chat_id still
		// points at the surviving intermediate (ParentOnly). Every shape
		// with either column set must be rejected.
		for _, tc := range []struct {
			name               string
			parentSet, rootSet bool
		}{
			{name: "ParentAndRoot", parentSet: true, rootSet: true},
			{name: "RootOnly", parentSet: false, rootSet: true},
			{name: "ParentOnly", parentSet: true, rootSet: false},
		} {
			t.Run(tc.name, func(t *testing.T) {
				t.Parallel()
				ctx := testutil.Context(t, testutil.WaitLong)
				root := insertTestChat(t, db)
				seed := database.Chat{
					OrganizationID:    root.OrganizationID,
					OwnerID:           root.OwnerID,
					LastModelConfigID: root.LastModelConfigID,
				}
				if tc.parentSet {
					seed.ParentChatID = uuid.NullUUID{UUID: root.ID, Valid: true}
				}
				if tc.rootSet {
					seed.RootChatID = uuid.NullUUID{UUID: root.ID, Valid: true}
				}
				child := dbgen.Chat(t, db, seed)

				_, err := insertMemory(ctx, child.ID, "rejected.md")
				require.Error(t, err)
				require.True(t, database.IsCheckViolation(err, memory.ChatMemoryRootChatRequiredConstraint), "got: %v", err)
			})
		}
	})

	t.Run("DuplicatePathRejected", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		chat := insertTestChat(t, db)
		_, err := insertMemory(ctx, chat.ID, "notes/decisions.md")
		require.NoError(t, err)
		_, err = insertMemory(ctx, chat.ID, "notes/decisions.md")
		require.Error(t, err)
		require.True(t, database.IsUniqueViolation(err, database.UniqueChatMemoriesRootChatIDPathIndex))
	})

	t.Run("GetAndList", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		chat := insertTestChat(t, db)
		mem, err := insertMemory(ctx, chat.ID, "notes/decisions.md")
		require.NoError(t, err)
		_, err = insertMemory(ctx, chat.ID, "scratch.md")
		require.NoError(t, err)

		got, err := db.GetChatMemoryByRootChatIDAndPath(ctx, database.GetChatMemoryByRootChatIDAndPathParams{
			RootChatID: chat.ID,
			Path:       "notes/decisions.md",
		})
		require.NoError(t, err)
		require.Equal(t, mem.ID, got.ID)

		byID, err := db.GetChatMemoryByID(ctx, mem.ID)
		require.NoError(t, err)
		require.Equal(t, mem.Path, byID.Path)

		list, err := db.ListChatMemoriesByRootChatID(ctx, chat.ID)
		require.NoError(t, err)
		require.Len(t, list, 2)

		prefixed, err := db.ListChatMemoriesByRootChatIDAndPathPrefix(ctx, database.ListChatMemoriesByRootChatIDAndPathPrefixParams{
			RootChatID: chat.ID,
			PathPrefix: "notes/",
		})
		require.NoError(t, err)
		require.Len(t, prefixed, 1)
		require.Equal(t, "content of notes/decisions.md", prefixed[0].ContentPrefix)

		// Unlike the prefix delete, an empty prefix previews every memory.
		all, err := db.ListChatMemoriesByRootChatIDAndPathPrefix(ctx, database.ListChatMemoriesByRootChatIDAndPathPrefixParams{
			RootChatID: chat.ID,
			PathPrefix: "",
		})
		require.NoError(t, err)
		require.Len(t, all, 2, "an empty prefix must preview every memory")
	})

	t.Run("UpdateRenameDelete", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		chat := insertTestChat(t, db)
		_, err := insertMemory(ctx, chat.ID, "notes/decisions.md")
		require.NoError(t, err)
		inserted, err := insertMemory(ctx, chat.ID, "scratch.md")
		require.NoError(t, err)

		_, err = db.UpdateChatMemoryByRootChatIDAndPath(ctx, database.UpdateChatMemoryByRootChatIDAndPathParams{
			RootChatID: chat.ID,
			Path:       "scratch.md",
			Content:    strings.Repeat("a", memory.MaxMemoryContentBytes+1),
		})
		require.Error(t, err)
		require.True(t, database.IsCheckViolation(err, database.CheckChatMemoriesContentSize), "got: %v", err)

		_, err = db.RenameChatMemoryByRootChatIDAndPath(ctx, database.RenameChatMemoryByRootChatIDAndPathParams{
			RootChatID: chat.ID,
			OldPath:    "scratch.md",
			NewPath:    "../escape.md",
		})
		require.Error(t, err)
		require.True(t, database.IsCheckViolation(err, database.CheckChatMemoriesPathFormat), "got: %v", err)

		_, err = db.RenameChatMemoryByRootChatIDAndPath(ctx, database.RenameChatMemoryByRootChatIDAndPathParams{
			RootChatID: chat.ID,
			OldPath:    "scratch.md",
			NewPath:    "notes/decisions.md",
		})
		require.Error(t, err)
		require.True(t, database.IsUniqueViolation(err, database.UniqueChatMemoriesRootChatIDPathIndex))

		_, err = db.UpdateChatMemoryByRootChatIDAndPath(ctx, database.UpdateChatMemoryByRootChatIDAndPathParams{
			RootChatID: chat.ID,
			Path:       "missing.md",
			Content:    "updated",
		})
		require.ErrorIs(t, err, sql.ErrNoRows)

		_, err = db.RenameChatMemoryByRootChatIDAndPath(ctx, database.RenameChatMemoryByRootChatIDAndPathParams{
			RootChatID: chat.ID,
			OldPath:    "missing.md",
			NewPath:    "new.md",
		})
		require.ErrorIs(t, err, sql.ErrNoRows)

		// pg_sleep guarantees now() advances past the insert timestamp before
		// the mutations, so the updated_at assertions below are deterministic.
		_, err = sqlDB.ExecContext(ctx, `SELECT pg_sleep(0.001)`)
		require.NoError(t, err)

		updated, err := db.UpdateChatMemoryByRootChatIDAndPath(ctx, database.UpdateChatMemoryByRootChatIDAndPathParams{
			RootChatID: chat.ID,
			Path:       "scratch.md",
			Content:    "updated",
		})
		require.NoError(t, err)
		require.Equal(t, "updated", updated.Content)
		require.True(t, updated.UpdatedAt.After(inserted.UpdatedAt), "update must advance updated_at")

		_, err = sqlDB.ExecContext(ctx, `SELECT pg_sleep(0.001)`)
		require.NoError(t, err)

		renamed, err := db.RenameChatMemoryByRootChatIDAndPath(ctx, database.RenameChatMemoryByRootChatIDAndPathParams{
			RootChatID: chat.ID,
			OldPath:    "scratch.md",
			NewPath:    "archive/scratch.md",
		})
		require.NoError(t, err)
		require.Equal(t, "archive/scratch.md", renamed.Path)
		require.True(t, renamed.UpdatedAt.After(updated.UpdatedAt), "rename must advance updated_at")

		deleted, err := db.DeleteChatMemoryByRootChatIDAndPath(ctx, database.DeleteChatMemoryByRootChatIDAndPathParams{
			RootChatID: chat.ID,
			Path:       "archive/scratch.md",
		})
		require.NoError(t, err)
		require.Equal(t, renamed.ID, deleted.ID)

		deletedByEmptyPrefix, err := db.DeleteChatMemoriesByRootChatIDAndPathPrefix(ctx, database.DeleteChatMemoriesByRootChatIDAndPathPrefixParams{
			RootChatID: chat.ID,
			PathPrefix: "",
		})
		require.NoError(t, err)
		require.Empty(t, deletedByEmptyPrefix)

		deletedMany, err := db.DeleteChatMemoriesByRootChatIDAndPathPrefix(ctx, database.DeleteChatMemoriesByRootChatIDAndPathPrefixParams{
			RootChatID: chat.ID,
			PathPrefix: "notes/",
		})
		require.NoError(t, err)
		require.Len(t, deletedMany, 1)

		list, err := db.ListChatMemoriesByRootChatID(ctx, chat.ID)
		require.NoError(t, err)
		require.Empty(t, list)
	})

	t.Run("HardDeleteCascades", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		doomed := insertTestChat(t, db)
		_, err := insertMemory(ctx, doomed.ID, "cascade.md")
		require.NoError(t, err)

		// No Store method deletes a chat by ID; DeleteOldChats requires the
		// chat to be archived past a threshold, so use raw SQL to exercise
		// the ON DELETE CASCADE foreign key directly.
		_, err = sqlDB.ExecContext(ctx, `DELETE FROM chats WHERE id = $1`, doomed.ID)
		require.NoError(t, err)

		list, err := db.ListChatMemoriesByRootChatID(ctx, doomed.ID)
		require.NoError(t, err)
		require.Empty(t, list)
	})

	t.Run("NonReadCommittedRejected", func(t *testing.T) {
		t.Parallel()

		// See the user-side twin: the cap is race-free only under READ
		// COMMITTED, so every other isolation level is rejected loudly.
		for name, level := range map[string]sql.IsolationLevel{
			"RepeatableRead": sql.LevelRepeatableRead,
			"Serializable":   sql.LevelSerializable,
		} {
			t.Run(name, func(t *testing.T) {
				t.Parallel()
				ctx := testutil.Context(t, testutil.WaitLong)
				chat := insertTestChat(t, db)

				tx, err := sqlDB.BeginTx(ctx, &sql.TxOptions{Isolation: level})
				require.NoError(t, err)
				defer func() { _ = tx.Rollback() }()
				_, err = tx.ExecContext(ctx, `
					INSERT INTO chat_memories (id, root_chat_id, path, content)
					VALUES ($1, $2, 'isolation.md', 'content')
				`, uuid.New(), chat.ID)
				require.Error(t, err)
				require.True(t, database.IsCheckViolation(err, memory.ChatMemoryInsertIsolationConstraint), "got: %v", err)
			})
		}
	})

	t.Run("OwnerImmutable", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		owner := insertTestChat(t, db)
		other := insertTestChat(t, db)
		_, err := insertMemory(ctx, owner.ID, "owned.md")
		require.NoError(t, err)

		// The insert invariants fire BEFORE INSERT only, so a reassignable
		// owner column would bypass the root-chat and cap checks; the owner
		// is immutable instead.
		_, err = sqlDB.ExecContext(ctx,
			`UPDATE chat_memories SET root_chat_id = $1 WHERE root_chat_id = $2`, other.ID, owner.ID)
		require.Error(t, err)
		require.True(t, database.IsCheckViolation(err, memory.ChatMemoryOwnerImmutableConstraint), "got: %v", err)
	})

	t.Run("UpdateTakesNoChatLock", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		chat := insertTestChat(t, db)
		_, err := insertMemory(ctx, chat.ID, "gate.md")
		require.NoError(t, err)

		lockTx, err := sqlDB.BeginTx(ctx, nil)
		require.NoError(t, err)
		defer func() { _ = lockTx.Rollback() }()
		var lockedChatID uuid.UUID
		err = lockTx.QueryRowContext(ctx,
			`SELECT id FROM chats WHERE id = $1 FOR NO KEY UPDATE`, chat.ID,
		).Scan(&lockedChatID)
		require.NoError(t, err)
		require.Equal(t, chat.ID, lockedChatID)

		// The trigger fires BEFORE INSERT only; widening it to UPDATE would
		// block this edit on the locked chats row. The lock_timeout bounds
		// the wait so blocking fails the test instead of passing after the
		// context deadline rolls back lockTx and releases the lock.
		updateConn, err := sqlDB.Conn(ctx)
		require.NoError(t, err)
		t.Cleanup(func() { _ = updateConn.Close() })
		_, err = updateConn.ExecContext(ctx, `SET lock_timeout = '2s'`)
		require.NoError(t, err)
		// Reset before the connection returns to the pool; database/sql
		// does not reset session state, so the timeout would leak into
		// whichever parallel sibling draws this connection next. Cleanups
		// run LIFO, so this runs before Close.
		t.Cleanup(func() { _, _ = updateConn.ExecContext(context.Background(), `RESET lock_timeout`) })
		_, err = updateConn.ExecContext(ctx,
			`UPDATE chat_memories SET content = 'edited' WHERE root_chat_id = $1`, chat.ID)
		require.NoError(t, err, "memory updates must not wait on the chats row")
	})

	t.Run("PerRootChatLimit", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		limited := insertTestChat(t, db)
		for i := range memory.MaxChatMemoriesPerRootChat {
			_, err := insertMemory(ctx, limited.ID, fmt.Sprintf("memory-%03d.md", i))
			require.NoError(t, err)
		}
		_, err := insertMemory(ctx, limited.ID, "one-too-many.md")
		require.Error(t, err)
		require.True(t, database.IsCheckViolation(err, memory.ChatMemoriesPerRootChatLimitConstraint), "got: %v", err)
	})

	t.Run("ConcurrentInsertPerRootChatLimit", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		limited := insertTestChat(t, db)
		for i := range memory.MaxChatMemoriesPerRootChat - 1 {
			_, err := insertMemory(ctx, limited.ID, fmt.Sprintf("memory-%03d.md", i))
			require.NoError(t, err)
		}

		// The insert filling the cap holds the parent-row lock; the racing
		// insert must re-count after the commit and hit the cap.
		err := runLockRace(ctx, t, sqlDB, sql.LevelDefault,
			[]stmt{{`
				INSERT INTO chat_memories (id, root_chat_id, path, content)
				VALUES ($1, $2, 'memory-099.md', 'content')
			`, []any{uuid.New(), limited.ID}}},
			stmt{`
				INSERT INTO chat_memories (id, root_chat_id, path, content)
				VALUES ($1, $2, 'one-too-many.md', 'content')
			`, []any{uuid.New(), limited.ID}},
			nil,
		)
		require.Error(t, err)
		require.True(t, database.IsCheckViolation(err, memory.ChatMemoriesPerRootChatLimitConstraint), "got: %v", err)

		list, err := db.ListChatMemoriesByRootChatID(ctx, limited.ID)
		require.NoError(t, err)
		require.Len(t, list, memory.MaxChatMemoriesPerRootChat)
	})
}

func insertTestChat(t *testing.T, db database.Store) database.Chat {
	t.Helper()
	org := dbgen.Organization(t, db, database.Organization{})
	owner := dbgen.User(t, db, database.User{})
	modelCfg := dbgen.ChatModelConfig(t, db, database.ChatModelConfig{
		Model:     "test-model",
		CreatedBy: uuid.NullUUID{UUID: owner.ID, Valid: true},
		UpdatedBy: uuid.NullUUID{UUID: owner.ID, Valid: true},
	})
	return dbgen.Chat(t, db, database.Chat{
		OrganizationID:    org.ID,
		OwnerID:           owner.ID,
		LastModelConfigID: modelCfg.ID,
	})
}
