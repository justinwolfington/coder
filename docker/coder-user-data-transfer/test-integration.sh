#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
readonly expected_schema_sha256="d0a73da2fa97ebcbb95a99353a1a6ec45214f258d64c8eaf7d104ec59b2b3375"
readonly postgres_image="docker.io/library/postgres@sha256:67f41722b7a8cbdb868a44a4995c846eddfdc2973bccb291ce937dce88ad5675"
readonly test_database="coder_transfer_test_v2354"

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

require_command() {
	command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

sha256_file() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
		return
	fi
	shasum -a 256 "$1" | awk '{print $1}'
}

[[ $# -eq 1 ]] || fail "usage: $0 CODER_V2_35_4_SOURCE_DIR"
readonly coder_source_dir="$1"
readonly schema_file="${coder_source_dir}/coderd/database/dump.sql"
[[ -f "${schema_file}" ]] || fail "Coder schema dump not found"

require_command docker
require_command go

actual_schema_sha256="$(sha256_file "${schema_file}")"
[[ "${actual_schema_sha256}" == "${expected_schema_sha256}" ]] || fail "Coder schema dump does not match v2.35.4"

container_name="coder-transfer-test-${PPID}-$$"
readonly container_name
cleanup() {
	[[ "${container_name}" == coder-transfer-test-* ]] || return 1
	docker rm --force "${container_name}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run --detach --name "${container_name}" \
	--publish 127.0.0.1::5432 \
	--env POSTGRES_HOST_AUTH_METHOD=trust \
	--env "POSTGRES_DB=${test_database}" \
	"${postgres_image}" >/dev/null

ready=false
for _ in {1..60}; do
	if docker exec "${container_name}" psql \
		--username postgres --dbname "${test_database}" \
		--tuples-only --command "SELECT 1" >/dev/null 2>&1; then
		ready=true
		break
	fi
	sleep 0.5
done
[[ "${ready}" == true ]] || fail "PostgreSQL did not become ready"

endpoint="$(docker port "${container_name}" 5432/tcp)"
port="${endpoint##*:}"
[[ "${port}" =~ ^[0-9]+$ ]] || fail "could not resolve the PostgreSQL test port"
database_url="postgres://postgres@127.0.0.1:${port}/${test_database}?sslmode=disable"

docker exec --interactive "${container_name}" psql \
	--username postgres --dbname "${test_database}" \
	--set ON_ERROR_STOP=on --quiet <"${schema_file}" >/dev/null
docker exec "${container_name}" psql \
	--username postgres --dbname "${test_database}" \
	--set ON_ERROR_STOP=on --quiet --command \
	"CREATE TABLE schema_migrations (version bigint NOT NULL, dirty boolean NOT NULL); INSERT INTO schema_migrations VALUES (535, false);" \
	>/dev/null

(
	cd "${script_dir}"
	CODER_TRANSFER_TEST_DATABASE_URL="${database_url}" \
		go test -count=1 -run '^Test(Transfer|LoginMigration)Integration$' ./...
)
