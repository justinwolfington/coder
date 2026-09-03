package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"strings"
	"time"

	"github.com/google/uuid"
	_ "github.com/lib/pq"
)

const (
	databaseURLEnv = "CODER_PG_CONNECTION_URL"
	sourceIDEnv    = "CODER_TRANSFER_SOURCE_USER_ID"
	targetIDEnv    = "CODER_TRANSFER_TARGET_USER_ID"
	targetEmailEnv = "CODER_LOGIN_TARGET_EMAIL"
	planSHAEnv     = "CODER_TRANSFER_PLAN_SHA256"

	operationTransfer = "transfer"
	operationLogin    = "login"
)

type commandOptions struct {
	operation   string
	mode        string
	sourceID    uuid.UUID
	targetID    uuid.UUID
	targetEmail string
	planSHA256  string
}

func main() {
	os.Exit(run(context.Background(), os.Args[1:], os.Getenv, os.Stdout, os.Stderr))
}

func run(
	ctx context.Context,
	args []string,
	getenv func(string) string,
	stdout io.Writer,
	stderr io.Writer,
) int {
	opts, err := parseCommand(args, getenv, stderr)
	if err != nil {
		_, _ = fmt.Fprintf(stderr, "error: %v\n", err)
		return 2
	}

	databaseURL := strings.TrimSpace(getenv(databaseURLEnv))
	if databaseURL == "" {
		_, _ = fmt.Fprintf(stderr, "error: %s is required\n", databaseURLEnv)
		return 2
	}

	db, err := sql.Open("postgres", databaseURL)
	if err != nil {
		_, _ = fmt.Fprintln(stderr, "error: open database connection")
		return 1
	}
	defer db.Close()

	db.SetMaxOpenConns(2)
	db.SetMaxIdleConns(2)
	db.SetConnMaxLifetime(5 * time.Minute)

	operationCtx, cancel := context.WithTimeout(ctx, 2*time.Minute)
	defer cancel()
	if err := db.PingContext(operationCtx); err != nil {
		_, _ = fmt.Fprintln(stderr, "error: connect to database")
		return 1
	}

	var result any
	switch {
	case opts.operation == operationTransfer && opts.mode == "plan":
		result, err = CreatePlan(operationCtx, db, opts.sourceID, opts.targetID)
	case opts.operation == operationTransfer && opts.mode == "apply":
		result, err = ApplyTransfer(
			operationCtx,
			db,
			opts.sourceID,
			opts.targetID,
			opts.planSHA256,
		)
	case opts.operation == operationLogin && opts.mode == "plan":
		result, err = CreateLoginMigrationPlan(
			operationCtx,
			db,
			opts.sourceID,
			opts.targetEmail,
		)
	case opts.operation == operationLogin && opts.mode == "apply":
		result, err = ApplyLoginMigration(
			operationCtx,
			db,
			opts.sourceID,
			opts.targetEmail,
			opts.planSHA256,
		)
	default:
		err = errors.New("unsupported command")
	}
	if err != nil {
		_, _ = fmt.Fprintf(stderr, "error: %v\n", err)
		return 1
	}

	encoder := json.NewEncoder(stdout)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(result); err != nil {
		_, _ = fmt.Fprintln(stderr, "error: encode result")
		return 1
	}
	return 0
}

func parseCommand(
	args []string,
	getenv func(string) string,
	stderr io.Writer,
) (commandOptions, error) {
	if len(args) == 0 {
		return commandOptions{}, errors.New("command must be plan, apply, login-plan, or login-apply")
	}

	var operation, mode string
	switch args[0] {
	case "plan", "apply":
		operation = operationTransfer
		mode = args[0]
	case "login-plan":
		operation = operationLogin
		mode = "plan"
	case "login-apply":
		operation = operationLogin
		mode = "apply"
	default:
		return commandOptions{}, errors.New("command must be plan, apply, login-plan, or login-apply")
	}

	flags := flag.NewFlagSet(mode, flag.ContinueOnError)
	flags.SetOutput(stderr)
	sourceRaw := flags.String(
		"source-user-id",
		strings.TrimSpace(getenv(sourceIDEnv)),
		"GitHub Coder user UUID",
	)
	targetRaw := flags.String(
		"target-user-id",
		strings.TrimSpace(getenv(targetIDEnv)),
		"OIDC Coder user UUID",
	)
	targetEmailRaw := flags.String(
		"target-email",
		strings.TrimSpace(getenv(targetEmailEnv)),
		"corporate email for the existing Coder user",
	)
	planSHA256 := flags.String(
		"plan-sha256",
		strings.TrimSpace(getenv(planSHAEnv)),
		"SHA-256 from a current plan",
	)
	if err := flags.Parse(args[1:]); err != nil {
		return commandOptions{}, err
	}
	if flags.NArg() != 0 {
		return commandOptions{}, errors.New("unexpected positional arguments")
	}

	sourceID, err := uuid.Parse(strings.TrimSpace(*sourceRaw))
	if err != nil || sourceID == uuid.Nil {
		return commandOptions{}, errors.New("source-user-id must be a non-zero UUID")
	}
	var targetID uuid.UUID
	var targetEmail string
	if operation == operationTransfer {
		targetID, err = uuid.Parse(strings.TrimSpace(*targetRaw))
		if err != nil || targetID == uuid.Nil {
			return commandOptions{}, errors.New("target-user-id must be a non-zero UUID")
		}
		if sourceID == targetID {
			return commandOptions{}, errors.New("source and target users must differ")
		}
		if strings.TrimSpace(*targetEmailRaw) != "" {
			return commandOptions{}, errors.New("target-email is only valid for login migration")
		}
	} else {
		if strings.TrimSpace(*targetRaw) != "" {
			return commandOptions{}, errors.New("target-user-id is only valid for data transfer")
		}
		targetEmail, err = normalizeTargetEmail(*targetEmailRaw)
		if err != nil {
			return commandOptions{}, err
		}
	}

	sha := strings.TrimSpace(*planSHA256)
	if mode == "apply" {
		if len(sha) != 64 {
			return commandOptions{}, errors.New("apply requires a 64-character plan-sha256")
		}
		if sha != strings.ToLower(sha) {
			return commandOptions{}, errors.New("plan-sha256 must be lowercase hexadecimal")
		}
		for _, char := range sha {
			if (char < '0' || char > '9') && (char < 'a' || char > 'f') {
				return commandOptions{}, errors.New("plan-sha256 must be lowercase hexadecimal")
			}
		}
	} else if sha != "" {
		return commandOptions{}, errors.New("plan-sha256 is only valid with apply")
	}

	return commandOptions{
		operation:   operation,
		mode:        mode,
		sourceID:    sourceID,
		targetID:    targetID,
		targetEmail: targetEmail,
		planSHA256:  sha,
	}, nil
}
