#!/usr/bin/env bash
set -euo pipefail

log() {
    printf '[AURA] %s\n' "$*"
}

fail() {
    printf '[AURA][ERROR] %s\n' "$*" >&2
    exit 1
}

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
android_dir="$project_root/android"
local_properties="$android_dir/local.properties"

java_major_version() {
    local java_binary="$1"
    local version
    version="$("$java_binary" -version 2>&1 | awk -F '"' '/version/ {print $2; exit}')"
    [[ -n "$version" ]] || return 1
    if [[ "$version" == 1.* ]]; then
        printf '%s\n' "${version#1.}" | cut -d. -f1
    else
        printf '%s\n' "$version" | cut -d. -f1
    fi
}

java_home_is_17() {
    [[ -x "$1/bin/java" ]] &&
        [[ "$(java_major_version "$1/bin/java")" == "17" ]]
}

find_java_17_home() {
    local candidate

    if [[ -n "${JAVA_HOME:-}" ]] && java_home_is_17 "$JAVA_HOME"; then
        printf '%s\n' "$JAVA_HOME"
        return 0
    fi

    if command -v /usr/libexec/java_home >/dev/null 2>&1; then
        candidate="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"
        if [[ -n "$candidate" ]] && java_home_is_17 "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    fi

    for candidate in \
        "$HOME"/.sdkman/candidates/java/17* \
        /usr/lib/jvm/*17* \
        /Library/Java/JavaVirtualMachines/*17*.jdk/Contents/Home \
        /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
        /usr/local/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
    do
        if [[ -d "$candidate" ]] && java_home_is_17 "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

install_java_17() {
    case "$(uname -s)" in
        Linux)
            if [[ "$(id -u)" == "0" ]]; then
                apt-get update
                apt-get install -y openjdk-17-jdk
            elif command -v sudo >/dev/null 2>&1; then
                sudo apt-get update
                sudo apt-get install -y openjdk-17-jdk
            else
                fail "Java 17 is unavailable and this runner cannot install packages."
            fi
            ;;
        Darwin)
            command -v brew >/dev/null 2>&1 ||
                fail "Java 17 is unavailable and Homebrew is not installed."
            brew install openjdk@17
            ;;
        *)
            fail "Unsupported operating system; configure a JDK 17 toolchain."
            ;;
    esac
}

log "Selecting a JDK 17 runtime."
java_17_home="$(find_java_17_home || true)"
if [[ -z "$java_17_home" ]]; then
    install_java_17
    java_17_home="$(find_java_17_home || true)"
fi
[[ -n "$java_17_home" ]] ||
    fail "JDK 17 installation did not provide a usable JAVA_HOME."

export JAVA_HOME="$java_17_home"
export PATH="$JAVA_HOME/bin:$PATH"
[[ "$(java_major_version "$JAVA_HOME/bin/java")" == "17" ]] ||
    fail "JAVA_HOME does not point to Java 17."
log "Using $(java -version 2>&1 | head -n 1) from $JAVA_HOME."

property_value() {
    local key="$1"
    local file="$2"
    if [[ -f "$file" ]]; then
        awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); value = $0} END {print value}' "$file"
    fi
}

flutter_root="${FLUTTER_ROOT:-$(property_value flutter.sdk "$local_properties")}"
[[ -n "$flutter_root" ]] || fail "Set FLUTTER_ROOT or flutter.sdk in android/local.properties."
[[ -d "$flutter_root" ]] || fail "Flutter SDK was not found at '$flutter_root'."

sdk_candidates=(
    "${ANDROID_SDK_ROOT:-}"
    "${ANDROID_HOME:-}"
    "$(property_value sdk.dir "$local_properties")"
    "$HOME/Android/Sdk"
    "$HOME/Library/Android/sdk"
    /usr/local/lib/android/sdk
    /usr/local/share/android-sdk
)
android_sdk=""
for candidate in "${sdk_candidates[@]}"; do
    if [[ -n "$candidate" && -d "$candidate" ]]; then
        android_sdk="$candidate"
        break
    fi
done

if [[ -z "$android_sdk" ]] && command -v flutter >/dev/null 2>&1; then
    doctor_output="$(flutter doctor -v 2>&1 || true)"
    android_sdk="$(printf '%s\n' "$doctor_output" |
        sed -n 's/.*Android SDK at \([^[:space:]]*\).*/\1/p' | head -n 1)"
fi
[[ -n "$android_sdk" && -d "$android_sdk" ]] ||
    fail "Android SDK was not found. Install it and set ANDROID_SDK_ROOT."

flutter_gradle_dir="$flutter_root/packages/flutter_tools/gradle"
flutter_ndk_version="$(
    python3 - "$flutter_gradle_dir" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
pattern = re.compile(
    r"\b(?:ndkVersion|NDK_VERSION)\b\s*(?::[^=\n]+)?=\s*"
    r"['\"]([0-9]+\.[0-9]+\.[0-9]+)['\"]"
)
if root.is_dir():
    for source in sorted(root.rglob("*")):
        if source.suffix not in {".kt", ".groovy"}:
            continue
        if "main" not in source.parts:
            continue
        try:
            match = pattern.search(source.read_text(errors="replace"))
        except OSError:
            continue
        if match:
            print(match.group(1))
            break
PY
)"

ndk_candidates=()
if [[ -n "${ANDROID_NDK_HOME:-}" ]]; then
    ndk_candidates+=("$ANDROID_NDK_HOME")
fi
if [[ -n "${ANDROID_NDK_ROOT:-}" ]]; then
    ndk_candidates+=("$ANDROID_NDK_ROOT")
fi
if [[ -n "$flutter_ndk_version" ]]; then
    ndk_candidates+=("$android_sdk/ndk/$flutter_ndk_version")
fi
ndk_candidates+=("$android_sdk/ndk-bundle")

android_ndk=""
for candidate in "${ndk_candidates[@]}"; do
    if [[ -x "$candidate/ndk-build" ]]; then
        if [[ -z "$flutter_ndk_version" ||
              "$candidate" == "$android_sdk/ndk/$flutter_ndk_version" ]]; then
            android_ndk="$candidate"
            break
        fi
    fi
done

if [[ -z "$android_ndk" && -d "$android_sdk/ndk" ]]; then
    android_ndk="$(
        python3 - "$android_sdk/ndk" "$flutter_ndk_version" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
required = sys.argv[2]
versions = []
for directory in root.iterdir():
    if not directory.is_dir() or not (directory / "ndk-build").is_file():
        continue
    if required and directory.name != required:
        continue
    try:
        version_key = tuple(int(part) for part in directory.name.split("."))
    except ValueError:
        continue
    versions.append((version_key, directory))
if versions:
    print(max(versions, key=lambda entry: entry[0])[1])
PY
    )"
fi

if [[ -z "$android_ndk" && -n "$flutter_ndk_version" ]]; then
    sdkmanager=""
    for candidate in \
        "$android_sdk/cmdline-tools/latest/bin/sdkmanager" \
        "$android_sdk/tools/bin/sdkmanager"
    do
        if [[ -x "$candidate" ]]; then
            sdkmanager="$candidate"
            break
        fi
    done
    if [[ -n "$sdkmanager" ]]; then
        log "Installing Flutter's required Android NDK $flutter_ndk_version."
        "$sdkmanager" --sdk_root="$android_sdk" "ndk;$flutter_ndk_version"
        if [[ -x "$android_sdk/ndk/$flutter_ndk_version/ndk-build" ]]; then
            android_ndk="$android_sdk/ndk/$flutter_ndk_version"
        fi
    fi
fi

[[ -n "$android_ndk" && -x "$android_ndk/ndk-build" ]] ||
    fail "No usable Android NDK was found for this Flutter SDK${flutter_ndk_version:+ (required $flutter_ndk_version)}."

export ANDROID_HOME="$android_sdk"
export ANDROID_SDK_ROOT="$android_sdk"
export ANDROID_NDK_HOME="$android_ndk"
export ANDROID_NDK_ROOT="$android_ndk"

properties_tmp="$(mktemp "$android_dir/local.properties.XXXXXX")"
trap 'rm -f "$properties_tmp"' EXIT
if [[ -f "$local_properties" ]]; then
    awk -F= '$1 != "sdk.dir" && $1 != "ndk.dir" {print}' \
        "$local_properties" > "$properties_tmp"
fi
printf 'sdk.dir=%s\n' "$ANDROID_SDK_ROOT" >> "$properties_tmp"
printf 'ndk.dir=%s\n' "$ANDROID_NDK_HOME" >> "$properties_tmp"
mv "$properties_tmp" "$local_properties"
trap - EXIT

if [[ -n "${CM_ENV:-}" ]]; then
    {
        printf 'JAVA_HOME=%s\n' "$JAVA_HOME"
        printf 'ANDROID_HOME=%s\n' "$ANDROID_HOME"
        printf 'ANDROID_SDK_ROOT=%s\n' "$ANDROID_SDK_ROOT"
        printf 'ANDROID_NDK_HOME=%s\n' "$ANDROID_NDK_HOME"
        printf 'ANDROID_NDK_ROOT=%s\n' "$ANDROID_NDK_ROOT"
        printf 'PATH=%s\n' "$PATH"
    } >> "$CM_ENV"
fi

log "Using Android SDK at $ANDROID_SDK_ROOT."
log "Using Android NDK at $ANDROID_NDK_HOME."
