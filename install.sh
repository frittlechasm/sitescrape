#!/bin/bash

SITESCRAPE_INSTALL_URL="${SITESCRAPE_INSTALL_URL:-https://raw.githubusercontent.com/frittlechasm/sitescrape/v0.1.0/sitescrape}"
sourceLocation="${SITESCRAPE_INSTALL_SOURCE:-$SITESCRAPE_INSTALL_URL}"

function usage() {
  cat <<'USAGE'
Usage: install.sh [--bin-dir DIRECTORY] [--source PATH|URL]

Downloads and installs sitescrape into a directory on PATH.
The default directory is $HOME/.local/bin.

Environment:
  SITESCRAPE_INSTALL_SOURCE  Local file or URL to install from
  SITESCRAPE_INSTALL_URL     Default download URL
USAGE
}

function printLinuxInstructions() {
  local dependency
  local distro=""
  local installCommand=""
  local packages=()
  local xsltPackage=""

  if [ -r /etc/os-release ]; then
    # os-release is specified as shell-compatible variable assignments.
    distro="$(. /etc/os-release; echo "${ID:-} ${ID_LIKE:-}")"
  fi

  case "$distro" in
    *debian*|*ubuntu*)
      echo "  sudo apt-get update"
      installCommand="sudo apt-get install"
      xsltPackage="xsltproc"
      ;;
    *fedora*|*rhel*|*centos*|*rocky*|*almalinux*)
      installCommand="sudo dnf install"
      xsltPackage="libxslt"
      ;;
    *arch*)
      installCommand="sudo pacman -S"
      xsltPackage="libxslt"
      ;;
    *alpine*)
      installCommand="apk add"
      xsltPackage="libxslt"
      ;;
    *)
      echo "  Install packages that provide: ${missingDependencies[*]}"
      return
      ;;
  esac

  for dependency in "${missingDependencies[@]}"; do
    case "$dependency" in
      curl|gzip) packages+=("$dependency") ;;
      od) packages+=(coreutils) ;;
      xsltproc) packages+=("$xsltPackage") ;;
    esac
  done
  echo "  $installCommand ${packages[*]}"
}

function printMacInstructions() {
  local dependency
  local formulas=()

  for dependency in "${missingDependencies[@]}"; do
    case "$dependency" in
      curl) formulas+=(curl) ;;
      gzip) formulas+=(gzip) ;;
      od) formulas+=(coreutils) ;;
      xsltproc) formulas+=(libxslt) ;;
    esac
  done

  echo "  brew install ${formulas[*]}"
  for dependency in "${missingDependencies[@]}"; do
    case "$dependency" in
      curl)
        echo '  export PATH="$(brew --prefix curl)/bin:$PATH"'
        ;;
      od)
        echo '  export PATH="$(brew --prefix coreutils)/libexec/gnubin:$PATH"'
        ;;
      xsltproc)
        echo '  export PATH="$(brew --prefix libxslt)/bin:$PATH"'
        ;;
    esac
  done
}

function checkDependencies() {
  local dependency
  local os

  missingDependencies=()
  for dependency in curl gzip od xsltproc; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
      missingDependencies+=("$dependency")
    fi
  done

  if [ "${#missingDependencies[@]}" -eq 0 ]; then
    return 0
  fi

  echo "Missing required commands: ${missingDependencies[*]}" >&2
  echo >&2
  echo "Install the missing dependencies, then rerun this installer:" >&2
  os="$(uname -s 2>/dev/null)"
  case "$os" in
    Darwin) printMacInstructions >&2 ;;
    Linux) printLinuxInstructions >&2 ;;
    *) echo "  Install packages that provide: ${missingDependencies[*]}" >&2 ;;
  esac
  return 1
}

function copySource() {
  local destination="$2"
  local source="$1"

  case "$source" in
    http://*|https://*)
      if ! curl -fsSL "$source" -o "$destination"; then
        echo "Unable to download sitescrape from: $source" >&2
        return 1
      fi
      ;;
    *)
      if [ ! -f "$source" ]; then
        echo "Install source not found: $source" >&2
        return 1
      fi
      if ! cp "$source" "$destination"; then
        echo "Unable to copy install source: $source" >&2
        return 1
      fi
      ;;
  esac
}

function cleanupInstaller() {
  if [ -n "${downloadFile:-}" ] && [ -f "$downloadFile" ]; then
    rm -f "$downloadFile"
  fi
}

if [ -z "${BASH_VERSION:-}" ]; then
  echo "Run this installer with Bash." >&2
  exit 1
fi
if [ "${BASH_VERSINFO[0]}" -lt 3 ] || { [ "${BASH_VERSINFO[0]}" -eq 3 ] && [ "${BASH_VERSINFO[1]}" -lt 2 ]; }; then
  echo "sitescrape requires Bash 3.2 or newer." >&2
  exit 1
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --bin-dir)
      shift
      if [ "$#" -eq 0 ] || [ -z "$1" ]; then
        usage >&2
        exit 1
      fi
      binDir="$1"
      explicitBinDir=1
      ;;
    --source)
      shift
      if [ "$#" -eq 0 ] || [ -z "$1" ]; then
        usage >&2
        exit 1
      fi
      sourceLocation="$1"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if ! checkDependencies; then
  exit 1
fi

if [ -z "${binDir:-}" ]; then
  if [ -z "${HOME:-}" ]; then
    echo "HOME is not set; pass --bin-dir with an absolute directory." >&2
    exit 1
  fi
  binDir="$HOME/.local/bin"
fi
if [ "$binDir" != "/" ]; then
  binDir="${binDir%/}"
fi
case "$binDir" in
  /*) ;;
  *)
    echo "Install directory must be absolute: $binDir" >&2
    exit 1
    ;;
esac
case ":${PATH:-}:" in
  *":$binDir:"*) ;;
  *)
    if [ "${explicitBinDir:-0}" -eq 1 ]; then
      echo "Warning: install directory is not on the current PATH: $binDir" >&2
    else
      echo "Install directory is not on PATH: $binDir" >&2
      echo "Add it to PATH yourself or choose a directory already on PATH:" >&2
      echo "  --bin-dir /usr/local/bin" >&2
      exit 1
    fi
    ;;
esac

downloadFile="$(mktemp "${TMPDIR:-/tmp}/sitescrape.XXXXXX")" || {
  echo "Unable to create a temporary download file" >&2
  exit 1
}
trap cleanupInstaller EXIT
if ! copySource "$sourceLocation" "$downloadFile"; then
  exit 1
fi
if [ ! -s "$downloadFile" ] || ! "$BASH" -n "$downloadFile"; then
  echo "Install source failed validation" >&2
  exit 1
fi

if ! mkdir -p "$binDir"; then
  echo "Unable to create install directory: $binDir" >&2
  exit 1
fi
target="$binDir/sitescrape"
if ! install -m 0755 "$downloadFile" "$target"; then
  echo "Unable to install sitescrape at: $target" >&2
  exit 1
fi
if [ ! -f "$target" ] || [ ! -x "$target" ] || ! "$BASH" -n "$target"; then
  echo "Installed file failed verification: $target" >&2
  exit 1
fi

resolvedCommand="$(command -v sitescrape 2>/dev/null)"
echo "Installed sitescrape at: $target"
if [ "$resolvedCommand" != "$target" ]; then
  echo "Warning: 'sitescrape' currently resolves to: ${resolvedCommand:-not found}" >&2
  echo "Use $target or adjust PATH ordering." >&2
fi
printf "Uninstall with: rm %q\n" "$target"
