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

function assertExecutable() {
  local file="$1"

  if [ ! -x "$file" ]; then
    echo "    file is not executable: $file" >&2
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
  if grep -Fq "$TEST_BASE_URL/image.jpg" "$TEST_OUTPUT_DIR/urls.txt"; then
    echo "    image URL unexpectedly found in $TEST_OUTPUT_DIR/urls.txt" >&2
    return 1
  fi
  xmlFile="$(find "$TEST_OUTPUT_DIR" -type f -name '*.xml' -print -quit)"
  header="$(LC_ALL=C od -An -t x1 -N 2 "$xmlFile")"
  header="${header//[[:space:]]/}"
  assertNotEqual 1f8b "$header" "saved XML compression"
}

function testLargeMixedDomainUrls() {
  local expectedPrimary
  local expectedSecondary
  local number=1
  local secondaryOutputDir

  beginCase large
  expectedPrimary="$TEST_STATE_DIR/expected-primary"
  expectedSecondary="$TEST_STATE_DIR/expected-secondary"
  TEST_SECONDARY_DOMAIN="sitescrape-test-$runId-large-secondary.example.test"
  secondaryOutputDir="/tmp/site/$TEST_SECONDARY_DOMAIN"
  export TEST_SECONDARY_DOMAIN
  printf "%s\n" "$secondaryOutputDir" >> "$testRoot/output-dirs"
  while [ "$number" -le 600 ]; do
    printf '%s/primary-%s\n' "$TEST_BASE_URL" "$number" >> "$expectedPrimary"
    printf 'https://%s/secondary-%s\n' "$TEST_SECONDARY_DOMAIN" "$number" >> "$expectedSecondary"
    number=$((number + 1))
  done
  printf '%s/primary-1\n' "$TEST_BASE_URL" >> "$expectedPrimary"
  printf 'https://%s/secondary-1\n' "$TEST_SECONDARY_DOMAIN" >> "$expectedSecondary"

  runCli "$TEST_BASE_URL/large-mixed"
  assertEqual 0 "$CLI_STATUS" "large sitemap status" || return 1
  if ! cmp -s "$expectedPrimary" "$TEST_OUTPUT_DIR/urls.txt"; then
    echo "    primary-domain URL order or duplicates changed" >&2
    return 1
  fi
  if ! cmp -s "$expectedSecondary" "$secondaryOutputDir/urls.txt"; then
    echo "    secondary-domain URL order or duplicates changed" >&2
    return 1
  fi
}

function testUnsafePageUrlPreservesSnapshot() {
  local previousChecksum

  beginCase unsafe-page
  runCli "$TEST_BASE_URL/flat"
  assertEqual 0 "$CLI_STATUS" "unsafe page seed status" || return 1
  previousChecksum="$(checksum "$TEST_OUTPUT_DIR/urls.txt")"

  runCli "$TEST_BASE_URL/unsafe-page"
  assertNotEqual 0 "$CLI_STATUS" "unsafe page URL status" || return 1
  assertEqual "$previousChecksum" "$(checksum "$TEST_OUTPUT_DIR/urls.txt")" "snapshot after unsafe page URL"
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

function testInstaller() {
  local installBin

  beginCase installer
  installBin="$TEST_STATE_DIR/bin"
  mkdir "$installBin"

  if PATH="$installBin:$PATH" "$repoDir/install.sh" --source "$repoDir/sitescrape" --bin-dir "$installBin" \
    > "$TEST_STATE_DIR/stdout" 2> "$TEST_STATE_DIR/stderr"; then
    CLI_STATUS=0
  else
    CLI_STATUS=$?
  fi

  assertEqual 0 "$CLI_STATUS" "installer status" || return 1
  assertFile "$installBin/sitescrape" || return 1
  assertExecutable "$installBin/sitescrape" || return 1
  if ! cmp -s "$repoDir/sitescrape" "$installBin/sitescrape"; then
    echo "    installed CLI differs from its source" >&2
    return 1
  fi
  assertContains "Installed sitescrape at: $installBin/sitescrape" "$TEST_STATE_DIR/stdout" || return 1
  assertContains "Uninstall with:" "$TEST_STATE_DIR/stdout" || return 1

  if PATH="$fakeBin:$PATH" "$installBin/sitescrape" "$TEST_BASE_URL/flat" \
    > "$TEST_STATE_DIR/stdout" 2> "$TEST_STATE_DIR/stderr"; then
    CLI_STATUS=0
  else
    CLI_STATUS=$?
  fi
  assertEqual 0 "$CLI_STATUS" "installed CLI status" || return 1
  assertEqual "$TEST_BASE_URL/one" "$(sed -n '1p' "$TEST_OUTPUT_DIR/urls.txt")" "installed CLI output" || return 1

  if PATH="$installBin:$PATH" "$repoDir/install.sh" --source "$repoDir/sitescrape" --bin-dir "$installBin" \
    > "$TEST_STATE_DIR/stdout" 2> "$TEST_STATE_DIR/stderr"; then
    CLI_STATUS=0
  else
    CLI_STATUS=$?
  fi
  assertEqual 0 "$CLI_STATUS" "installer update status"
}

function testInstallerRequiresPath() {
  local installHome

  beginCase installer-path
  installHome="$TEST_STATE_DIR/home"
  mkdir "$installHome"

  if HOME="$installHome" "$repoDir/install.sh" --source "$repoDir/sitescrape" \
    > "$TEST_STATE_DIR/stdout" 2> "$TEST_STATE_DIR/stderr"; then
    CLI_STATUS=0
  else
    CLI_STATUS=$?
  fi

  assertNotEqual 0 "$CLI_STATUS" "installer PATH status" || return 1
  assertContains "Install directory is not on PATH: $installHome/.local/bin" "$TEST_STATE_DIR/stderr" || return 1
  assertNoFile "$installHome/.local/bin/sitescrape"
}

function testInstallerHonorsExplicitDirectory() {
  local installBin

  beginCase installer-explicit
  installBin="$TEST_STATE_DIR/bin"

  if "$repoDir/install.sh" --source "$repoDir/sitescrape" --bin-dir "$installBin" \
    > "$TEST_STATE_DIR/stdout" 2> "$TEST_STATE_DIR/stderr"; then
    CLI_STATUS=0
  else
    CLI_STATUS=$?
  fi

  assertEqual 0 "$CLI_STATUS" "explicit install directory status" || return 1
  assertExecutable "$installBin/sitescrape" || return 1
  assertContains "Warning: install directory is not on the current PATH" "$TEST_STATE_DIR/stderr"
}

function testInstallerMissingDependencies() {
  local dependency
  local dependencyBin
  local installBin

  beginCase installer-dependencies
  dependencyBin="$TEST_STATE_DIR/dependencies"
  installBin="$TEST_STATE_DIR/install-bin"
  mkdir "$dependencyBin"

  for dependency in gzip od uname; do
    ln -s "$(command -v "$dependency")" "$dependencyBin/$dependency"
  done

  if PATH="$dependencyBin:$installBin" /bin/bash "$repoDir/install.sh" --source "$repoDir/sitescrape" --bin-dir "$installBin" \
    > "$TEST_STATE_DIR/stdout" 2> "$TEST_STATE_DIR/stderr"; then
    CLI_STATUS=0
  else
    CLI_STATUS=$?
  fi

  assertNotEqual 0 "$CLI_STATUS" "installer dependency status" || return 1
  assertContains "Missing required commands: curl xsltproc" "$TEST_STATE_DIR/stderr" || return 1
  assertContains "Install the missing dependencies" "$TEST_STATE_DIR/stderr" || return 1
  assertNoFile "$installBin/sitescrape"
}

function testInstallerDownloadsSource() {
  local dependencyBin
  local expectedUrl
  local installHome
  local installBin

  beginCase installer-download
  dependencyBin="$TEST_STATE_DIR/dependencies"
  installHome="$TEST_STATE_DIR/home"
  installBin="$installHome/.local/bin"
  expectedUrl="https://raw.githubusercontent.com/frittlechasm/sitescrape/v0.1.0/sitescrape"
  mkdir -p "$dependencyBin" "$installBin"
  ln -s "$fakeBin/install-curl" "$dependencyBin/curl"

  if env -u SITESCRAPE_INSTALL_SOURCE -u SITESCRAPE_INSTALL_URL \
    TEST_INSTALL_SOURCE="$repoDir/sitescrape" \
    TEST_INSTALL_CURL_LOG="$TEST_STATE_DIR/download-url" \
    HOME="$installHome" \
    PATH="$dependencyBin:$installBin:$PATH" \
    /bin/bash < "$repoDir/install.sh" \
    > "$TEST_STATE_DIR/stdout" 2> "$TEST_STATE_DIR/stderr"; then
    CLI_STATUS=0
  else
    CLI_STATUS=$?
  fi

  assertEqual 0 "$CLI_STATUS" "remote installer status" || return 1
  assertExecutable "$installBin/sitescrape" || return 1
  assertEqual "$expectedUrl" "$(sed -n '1p' "$TEST_STATE_DIR/download-url")" "download URL"
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
runTest "large mixed-domain URL ordering and duplicates" testLargeMixedDomainUrls
runTest "unsafe page URL preserves snapshot" testUnsafePageUrlPreservesSnapshot
runTest "unsafe document rejection" testUnsafeDocumentsPreserveSnapshot
runTest "empty sitemap" testEmptySitemap
runTest "five-worker concurrency limit" testConcurrencyLimit
runTest "missing dependency" testMissingDependency
runTest "installer" testInstaller
runTest "installer requires a PATH directory" testInstallerRequiresPath
runTest "installer honors an explicit directory" testInstallerHonorsExplicitDirectory
runTest "installer reports missing dependencies" testInstallerMissingDependencies
runTest "installer downloads its source" testInstallerDownloadsSource

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
