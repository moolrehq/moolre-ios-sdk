#!/bin/sh
# Stops the example build when sample credentials are missing or still placeholders.
# Prints only setting names, never credential values.
set -u

failures=""

fail() {
    failures="${failures}\n  - $1"
}

is_placeholder() {
    case "$1" in
        replace-with-*|your-*|"<"*) return 0 ;;
        *) return 1 ;;
    esac
}

environment="${MOOLRE_ENVIRONMENT:-}"
api_user="${MOOLRE_API_USER:-}"
public_key="${MOOLRE_PUBLIC_KEY:-}"
account_number="${MOOLRE_ACCOUNT_NUMBER:-}"

case "$environment" in
    SANDBOX|LIVE) ;;
    *) fail "MOOLRE_ENVIRONMENT must be SANDBOX or LIVE" ;;
esac

if [ -z "$api_user" ] || is_placeholder "$api_user"; then
    fail "MOOLRE_API_USER is missing or a placeholder"
fi

if [ -z "$account_number" ] || is_placeholder "$account_number"; then
    fail "MOOLRE_ACCOUNT_NUMBER is missing or a placeholder"
fi

if [ -n "$public_key" ] && is_placeholder "$public_key"; then
    fail "MOOLRE_PUBLIC_KEY is a placeholder; set a real key or leave it blank in SANDBOX"
elif [ "$environment" = "LIVE" ] && [ -z "$public_key" ]; then
    fail "MOOLRE_PUBLIC_KEY is required when MOOLRE_ENVIRONMENT is LIVE"
fi

if [ -n "$failures" ]; then
    printf "error: Moolre sample credentials are invalid:%b\n" "$failures"
    echo "error: Copy Config/Credentials.example.xcconfig to Config/Credentials.xcconfig and set the values above."
    exit 1
fi
