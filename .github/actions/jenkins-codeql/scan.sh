#!/bin/bash

# Keep this in sync with the rules
CODEQL_VERSION="2.8.1"
CODEQL_VERSION_STRING="CodeQL command-line toolchain release 2.8.1"

# Print the provided arguments if we're executing in a GH Action
function ghout {
    if [[ -v GITHUB_ACTIONS ]] ; then
        echo "$@"
    fi
}

function error {
    echo "$@" >&2
    exit 1
}

[[ -n "$GITHUB_TOKEN" ]] || error "GITHUB_TOKEN is not defined or empty"
[[ -n "$GITHUB_API_URL" ]] || error "GITHUB_API_URL is not defined or empty"
[[ -n "$GITHUB_REPOSITORY" ]] || error "GITHUB_REPOSITORY is not defined or empty"
[[ -n "$CODEQL_RULES_DIR" ]] || error "CODEQL_RULES_DIR is not defined or empty"
[[ -n "$GITHUB_TOKEN" ]] || error "GITHUB_TOKEN is not defined or empty"
[[ -n "$CHECKOUT_DIR" ]] || error "CHECKOUT_DIR is not defined or empty"
[[ -d "$CHECKOUT_DIR" ]] || error "CHECKOUT_DIR is not a directory"
[[ -n "$GITHUB_SHA" ]] || error "GITHUB_SHA is not defined or empty"
[[ -n "$GITHUB_REF" ]] || error "GITHUB_REF is not defined or empty"

set -o errexit
set -o nounset
set -o pipefail

TOOLS=( jq codeql mvn date git gzip base64 curl )
for TOOL in "${TOOLS[@]}" ; do
    command -v "$TOOL" > /dev/null || error "Required tool not found: $TOOL"
done

if ! codeql --version | grep -q -F "$CODEQL_VERSION_STRING" ; then
  echo "CodeQL version check failed, version $CODEQL_VERSION is required, but got: $( codeql --version )" >&2
  exit 1
fi

NOW="$( TZ=UTC date +'%Y-%m-%dT%H:%M:%SZ' )"
echo "Using time stamp: $NOW"

TEMP_DIR="$( mktemp -d )"
DB_DIR="$TEMP_DIR/database"
OUTPUT_FILE="$TEMP_DIR/output.sarif"
OUTPUT_FILE_GZ_B64="$TEMP_DIR/output.sarif.gz.b64"
RULES_SUB_DIR="$CODEQL_RULES_DIR/jenkins/java/ql/"

ghout "::group::Create Database"
LGTM_INDEX_XML_MODE=all codeql database create --language=java --source-root="$CHECKOUT_DIR" "$DB_DIR" || error "Failed to create database"
ghout "::endgroup::"

ghout "::group::Analyze Database"
codeql database analyze --sarif-add-query-help --format=sarifv2.1.0 --output="$OUTPUT_FILE" "$DB_DIR" "$RULES_SUB_DIR" || error "Failed to analyze database"
ghout "::endgroup::"


# Prevent conflicts with otherwise set up CodeQL scan
jq 'setpath(path(.runs[].tool.driver.name); "Jenkins Security Scan") | setpath(path(.runs[].tool.driver.organization); "Jenkins Project")' "$OUTPUT_FILE" > "${OUTPUT_FILE}.filtered"


if [[ "$OSTYPE" == darwin* ]] ; then
    gzip --to-stdout "${OUTPUT_FILE}.filtered" | base64 > "$OUTPUT_FILE_GZ_B64"
else
    gzip --to-stdout "${OUTPUT_FILE}.filtered" | base64 --wrap=0 > "$OUTPUT_FILE_GZ_B64"
fi

curl --fail -H "Authorization: Bearer $GITHUB_TOKEN" -X POST -H "Accept: application/vnd.github.v3+json" \
        --data-binary '{"commit_sha":"'"$GITHUB_SHA"'","ref":"'"$GITHUB_REF"'","started_at":"'"$NOW"'","tool_name":"Jenkins Security Scan","sarif":"'"$( cat "$OUTPUT_FILE_GZ_B64" )"'"}' \
        "$GITHUB_API_URL/repos/$GITHUB_REPOSITORY/code-scanning/sarifs" || error "Failed to upload results"
