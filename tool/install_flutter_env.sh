#!/usr/bin/env bash
set -euo pipefail

log() {
    printf '[AURA-FLUTTER] %s\n' "$*"
}

fail() {
    printf '[AURA-FLUTTER][ERROR] %s\n' "$*" >&2
    exit 1
}

flutter_machine_info() {
    "$1" --version --machine 2>/dev/null |
        python3 -c '
import json
import sys

text = sys.stdin.read()
decoder = json.JSONDecoder()
matches = []
for offset, character in enumerate(text):
    if character != "{":
        continue
    try:
        value, _ = decoder.raw_decode(text[offset:])
    except json.JSONDecodeError:
        continue
    if isinstance(value, dict) and "frameworkVersion" in value:
        matches.append(value)
if not matches:
    raise SystemExit("Flutter did not report machine-readable version metadata.")
print(json.dumps(matches[-1]))
'
}

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
host_os="$(uname -s)"
host_arch="$(uname -m)"

case "$host_os:$host_arch" in
    Linux:x86_64 | Linux:amd64)
        archive_platform="linux"
        ;;
    Linux:aarch64 | Linux:arm64)
        archive_platform="linux-arm64"
        ;;
    Darwin:x86_64)
        archive_platform="macos"
        ;;
    Darwin:arm64)
        archive_platform="macos_arm64"
        ;;
    *)
        fail "Flutter stable SDK is not published for $host_os/$host_arch."
        ;;
esac

if command -v flutter >/dev/null 2>&1; then
    flutter_bin="$(command -v flutter)"
    if flutter_info="$(flutter_machine_info "$flutter_bin")" &&
        [[ "$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("channel", ""))' <<< "$flutter_info")" == "stable" ]]
    then
        flutter_root="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("flutterRoot", ""))' <<< "$flutter_info")"
        [[ -n "$flutter_root" ]] ||
            flutter_root="$(cd "$(dirname "$flutter_bin")/.." && pwd)"
    else
        flutter_root="${FLUTTER_ROOT:-$HOME/development/flutter}"
    fi
else
    flutter_root="${FLUTTER_ROOT:-$HOME/development/flutter}"
fi

if [[ ! -x "$flutter_root/bin/flutter" ]]; then
        command -v curl >/dev/null 2>&1 || fail "curl is required to download Flutter."
        command -v python3 >/dev/null 2>&1 || fail "python3 is required to select the stable release."
        command -v tar >/dev/null 2>&1 || fail "tar is required to extract Flutter."

        releases_json="$(mktemp "${TMPDIR:-/tmp}/aura-flutter-releases.XXXXXX")"
        archive_file="$(mktemp "${TMPDIR:-/tmp}/aura-flutter-sdk.XXXXXX")"
        extract_dir="$(mktemp -d "${TMPDIR:-/tmp}/aura-flutter-extract.XXXXXX")"
        cleanup() {
            rm -f "$releases_json" "$archive_file"
            rm -rf "$extract_dir"
        }
        trap cleanup EXIT

        log "Consulting the official stable release manifest."
        curl --fail --location --silent --show-error \
            "https://storage.googleapis.com/flutter_infra_release/releases/releases_${archive_platform}.json" \
            --output "$releases_json"
        read -r archive_name expected_sha256 < <(
            python3 - "$releases_json" <<'PY'
import json
import pathlib
import sys

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text())
stable_hash = manifest.get("current_release", {}).get("stable")
release = next(
    (
        item
        for item in manifest.get("releases", [])
        if item.get("hash") == stable_hash
        and item.get("channel") == "stable"
    ),
    None,
)
if not release or not release.get("archive") or not release.get("sha256"):
    raise SystemExit("Official manifest does not contain a verifiable stable archive.")
print(release["archive"], release["sha256"])
PY
        )
        [[ "$expected_sha256" =~ ^[[:xdigit:]]{64}$ ]] ||
            fail "The stable release manifest provided an invalid SHA-256."

        log "Downloading Flutter stable archive $archive_name."
        curl --fail --location --show-error \
            "https://storage.googleapis.com/flutter_infra_release/releases/$archive_name" \
            --output "$archive_file"
        actual_sha256="$(python3 - "$archive_file" <<'PY'
import hashlib
import pathlib
import sys

digest = hashlib.sha256()
with pathlib.Path(sys.argv[1]).open("rb") as archive:
    for chunk in iter(lambda: archive.read(1024 * 1024), b""):
        digest.update(chunk)
print(digest.hexdigest())
PY
        )"
        [[ "$actual_sha256" == "$expected_sha256" ]] ||
            fail "Flutter stable archive SHA-256 verification failed."

        mkdir -p "$(dirname "$flutter_root")"
        tar -xf "$archive_file" -C "$extract_dir"
        [[ -x "$extract_dir/flutter/bin/flutter" ]] ||
            fail "The verified Flutter archive does not contain bin/flutter."
        if [[ -e "$flutter_root" ]]; then
            fail "Refusing to replace an existing incomplete Flutter directory at '$flutter_root'."
        fi
        mv "$extract_dir/flutter" "$flutter_root"
        cleanup
        trap - EXIT
fi

[[ -x "$flutter_root/bin/flutter" ]] ||
    fail "Flutter executable was not found at '$flutter_root/bin/flutter'."
flutter_info="$(flutter_machine_info "$flutter_root/bin/flutter")" ||
    fail "Could not read Flutter SDK version metadata."
[[ "$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("channel", ""))' <<< "$flutter_info")" == "stable" ]] ||
    fail "The selected Flutter SDK is not on the stable channel."
export FLUTTER_ROOT="$flutter_root"
export PATH="$FLUTTER_ROOT/bin:$PATH"

if [[ -n "${CM_ENV:-}" ]]; then
    {
        printf 'FLUTTER_ROOT=%s\n' "$FLUTTER_ROOT"
        printf 'PATH=%s\n' "$PATH"
    } >> "$CM_ENV"
fi
if [[ -n "${GITHUB_ENV:-}" ]]; then
    {
        printf 'FLUTTER_ROOT=%s\n' "$FLUTTER_ROOT"
        printf 'PATH=%s\n' "$PATH"
    } >> "$GITHUB_ENV"
fi
if [[ -f "$HOME/.bashrc" ]] &&
    ! grep -Fq '# Aura Flutter stable SDK' "$HOME/.bashrc"
then
    {
        printf '\n# Aura Flutter stable SDK\n'
        printf 'export FLUTTER_ROOT=%q\n' "$FLUTTER_ROOT"
        printf 'export PATH="$FLUTTER_ROOT/bin:$PATH"\n'
    } >> "$HOME/.bashrc"
fi

local_properties="$project_root/android/local.properties"
mkdir -p "$(dirname "$local_properties")"
properties_tmp="$(mktemp "${local_properties}.XXXXXX")"
if [[ -f "$local_properties" ]]; then
    awk -F= '$1 != "flutter.sdk" {print}' "$local_properties" > "$properties_tmp"
fi
printf 'flutter.sdk=%s\n' "$FLUTTER_ROOT" >> "$properties_tmp"
mv "$properties_tmp" "$local_properties"

log "Flutter stable: $(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["frameworkVersion"], d["channel"])' <<< "$flutter_info")."

cd "$project_root"
"$FLUTTER_ROOT/bin/flutter" pub get
"$FLUTTER_ROOT/bin/flutter" analyze \
    lib/ai_brain.dart \
    lib/infrastructure/security/aura_dynamic_whitelist.dart \
    lib/crypto/aura_crypto_layer.dart
