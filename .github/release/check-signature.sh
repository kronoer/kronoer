#!/usr/bin/env bash
# Checks that every APK is signed with the key in KEYSTORE alone, and prints
# that key's certificate SHA-256 fingerprint (lowercase hex, no colons).
#
# Usage: KEYSTORE_PASSWORD=... check-signature.sh KEYSTORE ALIAS APK...
#
# Every way it can fail says why: a release must not go out with a check that
# stopped without a reason.
set -euo pipefail

if [ $# -lt 3 ]; then
    echo "::error::Usage: check-signature.sh KEYSTORE ALIAS APK..." >&2
    exit 1
fi
keystore=$1
alias=$2
shift 2

fail() {
    echo "::error::$1" >&2
    exit 1
}

[ -n "${KEYSTORE_PASSWORD:-}" ] || fail "KEYSTORE_PASSWORD is not set"
[ -f "$keystore" ] || fail "There is no keystore at $keystore"

# The newest build tools that have apksigner, or APKSIGNER when it is set.
apksigner=${APKSIGNER:-}
if [ -z "$apksigner" ]; then
    [ -n "${ANDROID_HOME:-}" ] || fail "Neither APKSIGNER nor ANDROID_HOME is set"
    for tools in $(ls -d "$ANDROID_HOME"/build-tools/* | sort -rV); do
        if [ -x "$tools/apksigner" ]; then
            apksigner=$tools/apksigner
            break
        fi
    done
    [ -n "$apksigner" ] || fail "No build tools in $ANDROID_HOME/build-tools have apksigner"
fi
echo "Checking with $apksigner" >&2

# The digest as both tools print it, lowercase and without colons.
normalize() { tr -d ':\r' | tr 'A-F' 'a-f'; }

if ! keytool_out=$(keytool -list -v -keystore "$keystore" -storepass:env KEYSTORE_PASSWORD -alias "$alias" 2>&1); then
    echo "$keytool_out" >&2
    fail "keytool could not read the key \"$alias\" from $keystore"
fi
expected=$(printf '%s\n' "$keytool_out" | awk '$1 == "SHA256:" { print $2; exit }' | normalize)
[ -n "$expected" ] || fail "keytool printed no SHA-256 fingerprint for \"$alias\""

for apk in "$@"; do
    [ -f "$apk" ] || fail "There is no APK at $apk"
    if ! certs=$("$apksigner" verify --print-certs "$apk" 2>&1); then
        echo "$certs" >&2
        fail "$apk does not verify"
    fi
    signers=$(printf '%s\n' "$certs" \
        | awk '/^Signer #[0-9]+ certificate SHA-256 digest:/ { print $NF }' | normalize)
    if [ "$signers" != "$expected" ]; then
        echo "$certs" >&2
        fail "$apk is not signed with the key \"$alias\" alone"
    fi
    echo "$apk is signed with \"$alias\" alone" >&2
done

echo "$expected"
