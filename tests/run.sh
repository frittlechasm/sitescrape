#!/bin/bash

set -u

repoDir="$(cd "$(dirname "$0")/.." && pwd)"
fixtureDir="$repoDir/tests/fixtures"
fakeBin="$repoDir/tests/fake-bin"
testRoot="$(mktemp -d /tmp/sitescrape-tests.XXXXXX)" || exit 1
runId="$$-$RANDOM"
passed=0
failed=0

function cleanupTests() {
  local outputDir

  if [ -f "$testRoot/output-dirs" ]; then
    while IFS= read -r outputDir; do
      case "$outputDir" in
        /tmp/site/sitescrape-test-"$runId"-*.example.test)
          [ ! -d "$outputDir" ] || find "$outputDir" -depth -delete
          ;;
      esac
    done < "$testRoot/output-dirs"
  fi
  find "$testRoot" -depth -delete
}

trap cleanupTests EXIT

function beginCase() {
  local name="$1"

  TEST_DOMAIN="sitescrape-test-$runId-$name.example.test"
  TEST_BASE_URL="https://$TEST_DOMAIN"
  TEST_OUTPUT_DIR="/tmp/site/$TEST_DOMAIN"
  TEST_STATE_DIR="$testRoot/$name"
  TEST_FIXTURE_DIR="$fixtureDir"
  mkdir -p "$TEST_STATE_DIR/active"
  : > "$TEST_STATE_DIR/calls"
  printf "0\n" > "$TEST_STATE_DIR/max-active"
  printf "%s\n" "$TEST_OUTPUT_DIR" >> "$testRoot/output-dirs"
  export TEST_BASE_URL TEST_FIXTURE_DIR TEST_STATE_DIR
}

function runCli() {
  if PATH="$fakeBin:$PATH" "$repoDir/sitescrape" "$@" \
    > "$TEST_STATE_DIR/stdout" 2> "$TEST_STATE_DIR/stderr"; then
    CLI_STATUS=0
  else
    CLI_STATUS=$?
  fi
}

function assertEqual() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [ "$expected" != "$actual" ]; then
    echo "    $message: expected '$expected', got '$actual'" >&2
    return 1
  fi
}

function assertNotEqual() {
  local unexpected="$1"
  local actual="$2"
  local message="$3"

  if [ "$unexpected" = "$actual" ]; then
    echo "    $message: did not expect '$unexpected'" >&2
    return 1
  fi
}

function assertFile() {
  local file="$1"

  if [ ! -f "$file" ]; then
    echo "    missing file: $file" >&2
    return 1
  fi
}

function assertNoFile() {
  local file="$1"

  if [ -e "$file" ]; then
    echo "    unexpected file: $file" >&2
    return 1
  fi
}

function assertContains() {
  local expected="$1"
  local file="$2"

  if ! grep -Fq "$expected" "$file"; then
    echo "    '$expected' not found in $file" >&2
    return 1
  fi
}

function assertNotContains() {
  local unexpected="$1"
  local file="$2"

  if grep -Fq "$unexpected" "$file"; then
    echo "    '$unexpected' unexpectedly found in $file" >&2
    return 1
  fi
}

function fileCount() {
  find "$1" -type f -name "$2" | wc -l | tr -d ' '
}

function checksum() {
  cksum "$1" | sed 's/ .*//'
}

function testMissingArguments() {
  beginCase missing-arguments
  runCli
  assertNotEqual 0 "$CLI_STATUS" "missing arguments status" || return 1
  assertContains "Pass a Site Map URL" "$TEST_STATE_DIR/stderr"
}

function testFlatSitemap() {
  beginCase flat
  runCli "$TEST_BASE_URL/flat"
  assertEqual 0 "$CLI_STATUS" "flat sitemap status" || return 1
  assertFile "$TEST_OUTPUT_DIR/urls.txt" || return 1
  assertEqual "$TEST_BASE_URL/one" "$(sed -n '1p' "$TEST_OUTPUT_DIR/urls.txt")" "first URL" || return 1
  assertEqual "$TEST_BASE_URL/two?a=1&b=2" "$(sed -n '2p' "$TEST_OUTPUT_DIR/urls.txt")" "decoded URL" || return 1
  assertEqual 1 "$(fileCount "$TEST_OUTPUT_DIR" '*.xml')" "saved sitemap count"
}

function testNestedDeduplication() {
  beginCase nested
  runCli "$TEST_BASE_URL/index"
  assertEqual 0 "$CLI_STATUS" "nested sitemap status" || return 1
  assertEqual "$TEST_BASE_URL/article.xml" "$(sed -n '1p' "$TEST_OUTPUT_DIR/urls.txt")" "nested page URL" || return 1
  assertEqual 1 "$(grep -Fxc "$TEST_BASE_URL/child" "$TEST_STATE_DIR/calls")" "child fetch count" || return 1
  assertEqual 2 "$(fileCount "$TEST_OUTPUT_DIR" '*.xml')" "nested sitemap file count"
}

function testSnapshotReplacementAndFailure() {
  local previousChecksum

  beginCase snapshots
  runCli "$TEST_BASE_URL/flat"
  assertEqual 0 "$CLI_STATUS" "seed snapshot status" || return 1
  previousChecksum="$(checksum "$TEST_OUTPUT_DIR/urls.txt")"

  runCli "$TEST_BASE_URL/failure"
  assertNotEqual 0 "$CLI_STATUS" "failed fetch status" || return 1
  assertEqual "$previousChecksum" "$(checksum "$TEST_OUTPUT_DIR/urls.txt")" "snapshot after failed fetch" || return 1

  runCli "$TEST_BASE_URL/child"
  assertEqual 0 "$CLI_STATUS" "replacement status" || return 1
  assertEqual "$TEST_BASE_URL/article.xml" "$(sed -n '1p' "$TEST_OUTPUT_DIR/urls.txt")" "replacement URL" || return 1
  assertEqual 1 "$(wc -l < "$TEST_OUTPUT_DIR/urls.txt" | tr -d ' ')" "replacement line count"
}

function testHttpAndWww() {
  beginCase http-www
  TEST_BASE_URL="http://www.$TEST_DOMAIN"
  export TEST_BASE_URL
  runCli "$TEST_BASE_URL/flat"
  assertEqual 0 "$CLI_STATUS" "HTTP sitemap status" || return 1
  assertFile "$TEST_OUTPUT_DIR/urls.txt" || return 1
  assertEqual "$TEST_BASE_URL/one" "$(sed -n '1p' "$TEST_OUTPUT_DIR/urls.txt")" "HTTP page URL"
}

function testUnsafeUrls() {
  beginCase unsafe-urls

  runCli "ftp://$TEST_DOMAIN/flat"
  assertNotEqual 0 "$CLI_STATUS" "unsupported scheme status" || return 1

  runCli "https://user:pass@$TEST_DOMAIN/flat"
  assertNotEqual 0 "$CLI_STATUS" "credential URL status" || return 1

  assertEqual 0 "$(wc -l < "$TEST_STATE_DIR/calls" | tr -d ' ')" "unsafe URL fetch count" || return 1
  assertNoFile "$TEST_OUTPUT_DIR/urls.txt"
}

function testXmlAndGzip() {
  local xmlFile
  local header

  beginCase xml-gzip
  runCli "$TEST_BASE_URL/namespace-gzip"
  assertEqual 0 "$CLI_STATUS" "gzip sitemap status" || return 1
  assertEqual "$TEST_BASE_URL/page?a=1&b=2" "$(sed -n '1p' "$TEST_OUTPUT_DIR/urls.txt")" "namespace URL" || return 1
  assertNotContains "$TEST_BASE_URL/image.jpg" "$TEST_OUTPUT_DIR/urls.txt" || return 1
  xmlFile="$(find "$TEST_OUTPUT_DIR" -type f -name '*.xml' -print -quit)"
  header="$(LC_ALL=C od -An -t x1 -N 2 "$xmlFile")"
  header="${header//[[:space:]]/}"
  assertNotEqual 1f8b "$header" "saved XML compression"
}

function testUnsafeDocumentsPreserveSnapshot() {
  local previousChecksum
  local path

  beginCase unsafe
  runCli "$TEST_BASE_URL/flat"
  assertEqual 0 "$CLI_STATUS" "unsafe test seed status" || return 1
  previousChecksum="$(checksum "$TEST_OUTPUT_DIR/urls.txt")"

  for path in corrupt-gzip doctype utf16 malformed html; do
    runCli "$TEST_BASE_URL/$path"
    assertNotEqual 0 "$CLI_STATUS" "$path status" || return 1
    assertEqual "$previousChecksum" "$(checksum "$TEST_OUTPUT_DIR/urls.txt")" "snapshot after $path" || return 1
  done
}

function testEmptySitemap() {
  beginCase empty
  runCli "$TEST_BASE_URL/empty"
  assertEqual 0 "$CLI_STATUS" "empty sitemap status" || return 1
  assertEqual 1 "$(fileCount "$TEST_OUTPUT_DIR" '*.xml')" "empty sitemap file count" || return 1
  assertNoFile "$TEST_OUTPUT_DIR/urls.txt"
}

function testConcurrencyLimit() {
  local maxActive

  beginCase concurrency
  runCli "$TEST_BASE_URL/batch-index"
  assertEqual 0 "$CLI_STATUS" "concurrency sitemap status" || return 1
  assertEqual 6 "$(wc -l < "$TEST_OUTPUT_DIR/urls.txt" | tr -d ' ')" "concurrency URL count" || return 1
  maxActive="$(sed -n '1p' "$TEST_STATE_DIR/max-active")"
  assertEqual 5 "$maxActive" "maximum concurrent fetches"
}

function testMissingDependency() {
  local dependencyBin

  beginCase missing-dependency
  dependencyBin="$TEST_STATE_DIR/bin"
  mkdir "$dependencyBin"
  ln -s "$fakeBin/curl" "$dependencyBin/curl"
  ln -s "$(command -v gzip)" "$dependencyBin/gzip"
  ln -s "$(command -v od)" "$dependencyBin/od"

  if PATH="$dependencyBin" "$repoDir/sitescrape" "$TEST_BASE_URL/flat" \
    > "$TEST_STATE_DIR/stdout" 2> "$TEST_STATE_DIR/stderr"; then
    CLI_STATUS=0
  else
    CLI_STATUS=$?
  fi
  assertNotEqual 0 "$CLI_STATUS" "missing dependency status" || return 1
  assertContains "Missing required command: xsltproc" "$TEST_STATE_DIR/stderr"
}

function runTest() {
  local name="$1"
  local testFunction="$2"

  if "$testFunction"; then
    passed=$((passed + 1))
    echo "PASS $name"
  else
    failed=$((failed + 1))
    echo "FAIL $name"
  fi
}

runTest "missing arguments" testMissingArguments
runTest "flat sitemap" testFlatSitemap
runTest "nested sitemap deduplication" testNestedDeduplication
runTest "snapshot replacement and failure" testSnapshotReplacementAndFailure
runTest "HTTP and www normalization" testHttpAndWww
runTest "unsafe URL rejection" testUnsafeUrls
runTest "XML namespaces, entities, and gzip" testXmlAndGzip
runTest "unsafe document rejection" testUnsafeDocumentsPreserveSnapshot
runTest "empty sitemap" testEmptySitemap
runTest "five-worker concurrency limit" testConcurrencyLimit
runTest "missing dependency" testMissingDependency

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
