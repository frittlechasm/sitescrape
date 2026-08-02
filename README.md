# sitescrape
- A simple script which parses though a sitemap and dumps all urls in the sitemap in a text file
- All urls get listed in a file called `urls.txt` under `/tmp/site/<domain>/` along with the XML version of each sitemap and nested sitemap.
- The command exits with a non-zero status if any sitemap cannot be fetched or written, and only reports completion after all nested sitemaps finish.
- Each successful run deletes and replaces the previous results for every domain processed by that invocation.
- Sitemap URLs are fetched in batches of up to five, and each exact sitemap URL is fetched at most once per invocation.
- Sitemap documents are identified by their `sitemapindex` or `urlset` root element, so sitemap URLs do not need an `.xml` suffix.
- Every command-line argument must return a sitemap document; page URLs passed directly are rejected.
- Both HTTP and HTTPS sitemap URLs are supported, and a leading `www.` is omitted from the output directory name.
- Namespace-prefixed XML, encoded URL characters, and gzip-compressed sitemap responses are supported.

## Requirements

- Bash 3.2 or newer
- `curl`
- `gzip`
- `od`
- `xsltproc`

macOS normally includes these commands. On Linux, install the packages for your distribution if they are not already available:

```bash
# Debian or Ubuntu
sudo apt-get update
sudo apt-get install curl gzip coreutils xsltproc

# Fedora or RHEL
sudo dnf install curl gzip coreutils libxslt

# Arch Linux
sudo pacman -S curl gzip coreutils libxslt
```

The installer reports every missing command and prints instructions for macOS, Debian-based, Fedora-based, Arch, and Alpine systems. It does not install packages or change shell configuration automatically.

## Installation

Download and run the installer:

```bash
curl -fsSL https://raw.githubusercontent.com/frittlechasm/sitescrape/v0.1.0/install.sh | bash
```

By default, `sitescrape` is installed at `$HOME/.local/bin/sitescrape`. That directory must already be on `PATH`; the installer exits with instructions if it is not.

To make it available for the current shell without changing shell configuration automatically:

```bash
mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"
curl -fsSL https://raw.githubusercontent.com/frittlechasm/sitescrape/v0.1.0/install.sh | bash
```

To keep that directory on `PATH` in future shells, add the `export` line to your shell configuration yourself.

To choose another directory on your normal user `PATH`, use `--bin-dir`:

```bash
curl -fsSL https://raw.githubusercontent.com/frittlechasm/sitescrape/v0.1.0/install.sh | sudo bash -s -- --bin-dir /usr/local/bin
```

An explicit directory is always honored. The installer warns if it is not on the current execution environment's `PATH`, which can happen when `sudo` uses a restricted `PATH`; verify it from your normal shell with `command -v sitescrape`.

The installer checks runtime dependencies before installing anything, downloads and validates the script, installs it with executable permissions, and verifies the installed file. It never invokes `sudo` or modifies shell configuration itself.

To install from a local checkout instead of GitHub:

```bash
SITESCRAPE_INSTALL_SOURCE=./sitescrape ./install.sh
```

Confirm which executable your shell finds:

```bash
command -v sitescrape
```

### Updating

Rerun the installer with the same options used originally:

```bash
curl -fsSL https://raw.githubusercontent.com/frittlechasm/sitescrape/v0.1.0/install.sh | bash
```

For a system-wide installation:

```bash
curl -fsSL https://raw.githubusercontent.com/frittlechasm/sitescrape/v0.1.0/install.sh | sudo bash -s -- --bin-dir /usr/local/bin
```

### Uninstalling

Remove the installed executable. Use the exact path printed by the installer:

```bash
rm "$HOME/.local/bin/sitescrape"
```

For the system-wide example above:

```bash
sudo rm /usr/local/bin/sitescrape
```

## Manual validation

Run the script with a sitemap URL:

```bash
./sitescrape https://example.com/sitemap.xml
```

Then confirm it wrote the expected files under `/tmp/site`:

```bash
find /tmp/site -maxdepth 2 -type f
```

You should see a domain folder containing `urls.txt` and any fetched sitemap XML files.

## Tests

Run the local behavior suite:

```bash
./tests/run.sh
```

The suite uses isolated `.example.test` domains and controlled local fixtures. It does not make network requests or modify results for real domains.
