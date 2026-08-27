#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
lock_script="${script_dir}/lock.sh"
readonly lock_script
patch_file="${script_dir}/patches/github-to-oidc-conversion.patch"
readonly patch_file

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

usage() {
	printf 'usage: %s --source-dir PATH --binary-output PATH\n' "$0" >&2
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
	if command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" | awk '{print $1}'
		return
	fi
	fail "required command not found: sha256sum or shasum"
}

source_dir=""
binary_output=""
while [[ $# -gt 0 ]]; do
	case "$1" in
	--source-dir)
		[[ $# -ge 2 ]] || usage
		source_dir="$2"
		shift 2
		;;
	--binary-output)
		[[ $# -ge 2 ]] || usage
		binary_output="$2"
		shift 2
		;;
	*)
		usage
		;;
	esac
done

[[ -n "${source_dir}" && -n "${binary_output}" ]] || usage
[[ ! -e "${binary_output}" ]] || fail "binary output already exists: ${binary_output}"
if [[ -e "${source_dir}" ]] && [[ -n "$(find "${source_dir}" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
	fail "source directory must be empty: ${source_dir}"
fi

require_command corepack
require_command git
require_command go
require_command make
corepack enable
require_command pnpm
"${lock_script}" --validate
[[ -f "${patch_file}" ]] || fail "patch file not found: ${patch_file}"

upstream_repository="$("${lock_script}" UPSTREAM_REPOSITORY)"
readonly upstream_repository
upstream_commit="$("${lock_script}" UPSTREAM_COMMIT)"
readonly upstream_commit
source_mirror_repository="$("${lock_script}" SOURCE_MIRROR_REPOSITORY)"
readonly source_mirror_repository
source_mirror_commit="$("${lock_script}" SOURCE_MIRROR_COMMIT)"
readonly source_mirror_commit
source_mirror_tree="$("${lock_script}" SOURCE_MIRROR_TREE)"
readonly source_mirror_tree
patch_sha256="$("${lock_script}" PATCH_SHA256)"
readonly patch_sha256
coder_version="$("${lock_script}" CODER_VERSION)"
readonly coder_version
target_platform="$("${lock_script}" TARGET_PLATFORM)"
readonly target_platform

actual_patch_sha256="$(sha256_file "${patch_file}")"
[[ "${actual_patch_sha256}" == "${patch_sha256}" ]] || fail "patch SHA-256 does not match the lock"

mkdir -p "${source_dir}" "$(dirname -- "${binary_output}")"
git init --quiet "${source_dir}"
git -C "${source_dir}" fetch --no-tags --depth=1 "${upstream_repository}" "${upstream_commit}"
git -C "${source_dir}" checkout --detach --quiet "${upstream_commit}"
[[ "$(git -C "${source_dir}" rev-parse HEAD)" == "${upstream_commit}" ]] || fail "upstream checkout does not match the lock"
git -C "${source_dir}" apply --check --whitespace=error "${patch_file}"
git -C "${source_dir}" apply --index --whitespace=error "${patch_file}"
[[ "$(git -C "${source_dir}" write-tree)" == "${source_mirror_tree}" ]] || fail "applied patch does not match the source mirror tree"

readonly pnpm_store_dir="${source_dir}/.pnpm-store"
export PNPM_CONFIG_STORE_DIR="${pnpm_store_dir}"

# Keep upstream lifecycle policy intact. Do not approve or suppress package scripts here.
(
	cd "${source_dir}"
	CI=true ./scripts/pnpm_install.sh
)
(
	cd "${source_dir}/site"
	CI=true "${source_dir}/scripts/pnpm_install.sh"
	pnpm build
)

# The installed tools remain part of the upstream build graph, but pnpm's
# content-addressable store is no longer needed after the frontend build.
# Release that temporary disk space before the Go compilation.
rm -rf -- "${pnpm_store_dir}"

# Generated source is committed and validated by the source PR. A fresh Git
# checkout gives every file the same timestamp, which otherwise causes Make to
# regenerate unrelated protobuf output during the server build.
make -C "${source_dir}" gen/mark-fresh
# Keep the already-built UI newer than its generated TypeScript inputs.
touch "${source_dir}/site/out/index.html"

unset PNPM_CONFIG_STORE_DIR

readonly target_arch="${target_platform#*/}"
readonly build_version="${coder_version#v}+abridge.${source_mirror_commit}"
export CODER_BUILD_EXTERNAL_URL="${source_mirror_repository}/commit/${source_mirror_commit}"
make -C "${source_dir}" "VERSION=${build_version}" "build/coder_linux_${target_arch}"
readonly built_binary="${source_dir}/build/coder_${build_version}_linux_${target_arch}"
[[ -x "${built_binary}" ]] || fail "expected server binary not produced: ${built_binary}"
install -m 0755 "${built_binary}" "${binary_output}"
