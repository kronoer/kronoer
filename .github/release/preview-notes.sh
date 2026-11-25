#!/usr/bin/env bash
# Prints the release notes of a Kronoer Preview: preview-notes.md with this
# version's section of CHANGELOG.md, the APKs' SHA-256, and the certificate's
# fingerprint filled in. Fails when CHANGELOG.md has no section for the version.
#
# Usage: preview-notes.sh VERSION CERT_SHA256 ARM64_APK ARMV7_APK
set -euo pipefail

if [ $# -ne 4 ]; then
    echo "usage: $0 VERSION CERT_SHA256 ARM64_APK ARMV7_APK" >&2
    exit 2
fi
version=$1
cert=$2
arm64=$3
armv7=$4
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)

# The lines between `## [VERSION]` and the next heading of that level or the
# link references, without blank lines at either end.
changes=$(awk -v heading="## [$version]" '
    index($0, heading) == 1 { on = 1; next }
    on && (/^## / || /^\[[^]]+\]: /) { exit }
    on { lines[++n] = $0 }
    END {
        first = 1; while (first <= n && lines[first] ~ /^[[:space:]]*$/) first++
        last = n; while (last >= first && lines[last] ~ /^[[:space:]]*$/) last--
        for (i = first; i <= last; i++) print lines[i]
    }
' "$root/CHANGELOG.md")
if [ -z "$changes" ]; then
    echo "CHANGELOG.md has no section for $version: add \"## [$version] - YYYY-MM-DD\" with what changed" >&2
    exit 1
fi

sha256() { sha256sum "$1" | cut -d' ' -f1; }

CHANGES=$changes awk \
    -v version="$version" \
    -v cert="$cert" \
    -v arm64="$(sha256 "$arm64")" \
    -v armv7="$(sha256 "$armv7")" '
    $0 == "{{CHANGES}}" { print ENVIRON["CHANGES"]; next }
    {
        gsub(/\{\{VERSION\}\}/, version)
        gsub(/\{\{CERT_SHA256\}\}/, cert)
        gsub(/\{\{ARM64_SHA256\}\}/, arm64)
        gsub(/\{\{ARMV7_SHA256\}\}/, armv7)
        print
    }
' "$here/preview-notes.md"
