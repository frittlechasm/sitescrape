# sitescrape

`sitescrape` downloads a sitemap and writes its page URLs to a text file. It follows nested sitemap indexes automatically.

## Usage

```bash
sitescrape https://example.com/sitemap.xml
```

Results are written to `/tmp/site/<domain>/`:

```text
/tmp/site/example.com/
├── urls.txt
└── <downloaded sitemap files>.xml
```

`urls.txt` contains one page URL per line. A successful run replaces the previous results for each domain processed by that command.

You can process more than one sitemap at once:

```bash
sitescrape https://example.com/sitemap.xml https://example.org/sitemap.xml
```

## Installation

Install the latest release to `$HOME/.local/bin`:

```bash
curl -fsSL https://raw.githubusercontent.com/frittlechasm/sitescrape/main/install.sh | bash
```

`$HOME/.local/bin` must be on your `PATH`. If it is not, add it before running the installer:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Add that line to your shell configuration to keep it available in future shells.

To install somewhere else, pass `--bin-dir`:

```bash
curl -fsSL https://raw.githubusercontent.com/frittlechasm/sitescrape/main/install.sh | sudo bash -s -- --bin-dir /usr/local/bin
```

The installer checks dependencies, downloads and validates the script, and installs it with executable permissions. It does not install packages, invoke `sudo`, or modify your shell configuration.

To update, rerun the same installation command. To uninstall, remove the installed executable:

```bash
rm "$HOME/.local/bin/sitescrape"
```

## Requirements

- Bash 3.2 or newer
- `curl`
- `gzip`
- `od`
- `xsltproc`

macOS normally includes these commands. On Linux, install them with your package manager. The installer lists any missing commands and suggests packages for Debian, Ubuntu, Fedora, RHEL, Arch, and Alpine.

## Behavior

- Accepts HTTP and HTTPS sitemap URLs.
- Supports sitemap indexes, URL sets, XML namespaces, gzip responses, and encoded URL characters.
- Does not require sitemap URLs to end in `.xml`.
- Fetches up to five sitemaps concurrently and fetches each exact sitemap URL once per run.
- Removes a leading `www.` from the output directory name.
- Rejects page URLs and other documents that are not valid sitemaps.
- Exits with a non-zero status if any sitemap cannot be fetched, parsed, or written.
- Publishes results only after all nested sitemaps finish successfully.
