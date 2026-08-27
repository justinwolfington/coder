#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
lock_file="${script_dir}/locked-source.env"
readonly lock_file

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

lock_value() {
	local key="$1"
	local matches

	matches="$(grep -E "^${key}=[^[:space:]=]+$" "${lock_file}" || true)"
	if [[ "$(printf '%s\n' "${matches}" | grep -c . || true)" != "1" ]]; then
		fail "expected exactly one ${key} entry in ${lock_file}"
	fi
	printf '%s\n' "${matches#*=}"
}

validate_sha1() {
	local name="$1"
	local value="$2"

	[[ "${value}" =~ ^[a-f0-9]{40}$ ]] || fail "${name} must be a lowercase Git SHA"
}

validate_lock() {
	local upstream_repository source_mirror_repository upstream_commit source_mirror_commit
	local source_mirror_tree patch_sha256 upstream_image coder_version target_platform

	[[ -f "${lock_file}" ]] || fail "lock file not found: ${lock_file}"
	upstream_repository="$(lock_value UPSTREAM_REPOSITORY)"
	source_mirror_repository="$(lock_value SOURCE_MIRROR_REPOSITORY)"
	upstream_commit="$(lock_value UPSTREAM_COMMIT)"
	source_mirror_commit="$(lock_value SOURCE_MIRROR_COMMIT)"
	source_mirror_tree="$(lock_value SOURCE_MIRROR_TREE)"
	patch_sha256="$(lock_value PATCH_SHA256)"
	upstream_image="$(lock_value UPSTREAM_IMAGE)"
	coder_version="$(lock_value CODER_VERSION)"
	target_platform="$(lock_value TARGET_PLATFORM)"

	[[ "${upstream_repository}" == "https://github.com/coder/coder.git" ]] || fail "unexpected upstream repository"
	[[ "${source_mirror_repository}" == "https://github.com/abridgeai/coder-upstream" ]] || fail "unexpected source mirror repository"
	validate_sha1 UPSTREAM_COMMIT "${upstream_commit}"
	validate_sha1 SOURCE_MIRROR_COMMIT "${source_mirror_commit}"
	validate_sha1 SOURCE_MIRROR_TREE "${source_mirror_tree}"
	[[ "${patch_sha256}" =~ ^[a-f0-9]{64}$ ]] || fail "PATCH_SHA256 must be a lowercase SHA-256"
	[[ "${upstream_image}" =~ ^ghcr\.io/coder/coder@sha256:[a-f0-9]{64}$ ]] || fail "UPSTREAM_IMAGE must be a digest-pinned Coder image"
	[[ "${coder_version}" == "v2.35.4" ]] || fail "unexpected Coder version"
	[[ "${target_platform}" == "linux/amd64" ]] || fail "unexpected build platform"
}

case "${1:-}" in
--validate)
	validate_lock
	;;
UPSTREAM_REPOSITORY|UPSTREAM_COMMIT|SOURCE_MIRROR_REPOSITORY|SOURCE_MIRROR_COMMIT|SOURCE_MIRROR_TREE|PATCH_SHA256|UPSTREAM_IMAGE|CODER_VERSION|TARGET_PLATFORM)
	validate_lock
	lock_value "$1"
	;;
*)
	fail "usage: $0 --validate|LOCK_KEY"
	;;
esac
