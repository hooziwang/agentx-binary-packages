#!/usr/bin/env bash
set -euo pipefail

PRIMARY_BASE="${AGENTX_BINARY_RELEASE_PRIMARY_BASE_URL:-https://raw.githubusercontent.com/hooziwang/agentx-binary-packages/main}"
FALLBACK_BASE="${AGENTX_BINARY_RELEASE_FALLBACK_BASE_URL:-https://agentx.aelus.tech/cli}"
INSTALL_DIR="${HOME}/.local/bin"

usage() {
  cat <<'USAGE'
Install AgentX CLI.

Usage:
  install.sh [--dir <path>]

Options:
  --dir <path>  AgentX CLI install directory. Defaults to $HOME/.local/bin.
  -h, --help    Show this help.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir)
      if [ "${2:-}" = "" ]; then
        echo "install.sh: --dir requires a path" >&2
        exit 1
      fi
      INSTALL_DIR="$2"
      shift 2
      ;;
    --dir=*)
      INSTALL_DIR="${1#--dir=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "install.sh: unknown argument $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

os_name="$(uname -s)"
arch_name="$(uname -m)"
if [ "$os_name" != "Darwin" ] || [ "$arch_name" != "arm64" ]; then
  echo "AgentX CLI installer supports macOS Apple Silicon only. Current platform: ${os_name}/${arch_name}" >&2
  exit 1
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "AgentX CLI installer requires $1." >&2
    exit 1
  fi
}

require_command curl
require_command tar
require_command shasum

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/agentx-install.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

trim_trailing_slash() {
  printf '%s' "$1" | sed 's#/*$##'
}

join_url() {
  local base path
  base="$(trim_trailing_slash "$1")"
  path="${2#/}"
  printf '%s/%s' "$base" "$path"
}

fetch_from_sources() {
  local path out url
  path="$1"
  out="$2"
  for base in "$PRIMARY_BASE" "$FALLBACK_BASE"; do
    url="$(join_url "$base" "$path")"
    if curl -fsSL --connect-timeout 5 --max-time 15 "$url" -o "$out"; then
      return 0
    fi
  done
  return 1
}

json_string() {
  local json key
  json="$1"
  key="$2"
  printf '%s' "$json" \
    | tr -d '\n\r' \
    | sed -nE 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p'
}

json_urls() {
  printf '%s' "$1" \
    | tr -d '\n\r' \
    | grep -oE '"url"[[:space:]]*:[[:space:]]*"[^"]+"' \
    | sed -E 's/.*"url"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/'
}

ensure_ax_alias() {
  local alias_path
  alias_path="$INSTALL_DIR/ax"
  if [ -L "$alias_path" ] && [ "$(readlink "$alias_path")" = "agentx" ]; then
    return 0
  fi
  if ! rm -f "$alias_path"; then
    echo "Warning: failed to remove existing ax command alias at $alias_path." >&2
    return 0
  fi
  if ! ln -s agentx "$alias_path"; then
    if ! cp "$target" "$alias_path"; then
      echo "Warning: failed to create ax command alias at $alias_path." >&2
      return 0
    fi
    chmod +x "$alias_path" || true
  fi
  xattr -d com.apple.quarantine "$alias_path" >/dev/null 2>&1 || true
}

latest_path="$tmp_dir/latest.json"
if ! fetch_from_sources "agentx/latest.json" "$latest_path"; then
  echo "Failed to download AgentX latest manifest." >&2
  exit 1
fi

latest_json="$(cat "$latest_path")"
latest_version="$(json_string "$latest_json" "latestVersion")"
manifest_path="$(json_string "$latest_json" "darwin_arm64")"
if [ "$latest_version" = "" ] || [ "$manifest_path" = "" ]; then
  echo "AgentX latest manifest is missing required fields." >&2
  exit 1
fi

platform_manifest_path="$tmp_dir/darwin_arm64.json"
if ! fetch_from_sources "$manifest_path" "$platform_manifest_path"; then
  echo "Failed to download AgentX platform manifest." >&2
  exit 1
fi

platform_manifest="$(cat "$platform_manifest_path")"
expected_sha512="$(json_string "$platform_manifest" "sha512" | tr 'A-F' 'a-f')"
if [ "$expected_sha512" = "" ]; then
  echo "AgentX platform manifest is missing sha512." >&2
  exit 1
fi

archive_path="$tmp_dir/agentx.tar.gz"
downloaded=0
while IFS= read -r url; do
  if [ "$url" = "" ]; then
    continue
  fi
  if curl -fsSL --connect-timeout 5 --max-time 600 --speed-time 30 --speed-limit 20480 "$url" -o "$archive_path"; then
    downloaded=1
    break
  fi
done <<EOF
$(json_urls "$platform_manifest")
EOF

if [ "$downloaded" != "1" ]; then
  echo "Failed to download AgentX binary archive." >&2
  exit 1
fi

actual_sha512="$(shasum -a 512 "$archive_path" | awk '{print $1}' | tr 'A-F' 'a-f')"
if [ "$actual_sha512" != "$expected_sha512" ]; then
  rm -f "$archive_path"
  echo "AgentX binary archive SHA512 mismatch." >&2
  exit 1
fi

extract_dir="$tmp_dir/extract"
mkdir -p "$extract_dir"
tar -xzf "$archive_path" -C "$extract_dir"
if [ ! -f "$extract_dir/agentx" ]; then
  echo "AgentX archive does not contain agentx." >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
target="$INSTALL_DIR/agentx"
tmp_target="${target}.tmp.$$"
cp "$extract_dir/agentx" "$tmp_target"
chmod +x "$tmp_target"
mv "$tmp_target" "$target"
xattr -d com.apple.quarantine "$target" >/dev/null 2>&1 || true
ensure_ax_alias

"$target" install --dir "$INSTALL_DIR"
echo "AgentX ${latest_version} installed at ${target}."
