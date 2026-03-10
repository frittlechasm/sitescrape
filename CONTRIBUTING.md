# Contributing

Thanks for your interest in contributing to **sitescrape**.

## How to Contribute

Contributions are welcome. A few good ways to help:

- **Bug reports** — open an issue with the sitemap URL pattern, expected behavior, and actual behavior
- **Feature requests** — open an issue describing the use case before adding new behavior
- **Pull requests** — fork the repo, make a focused change in a branch, and open a PR against `main`

Please keep pull requests limited to a single change when possible. For larger ideas, open an issue first so the approach can be discussed.

## Guidelines

- Keep the tool as a small self-contained Bash script
- Avoid adding new runtime dependencies unless they are clearly justified
- Preserve the current CLI usage and `/tmp/site` output layout unless the change is intentional
- Update `README.md` when behavior or usage changes
- Run `bash -n sitescrape` before submitting

## Manual Validation

In addition to `bash -n sitescrape`, please do a quick runtime check:

```bash
./sitescrape https://example.com/sitemap.xml
find /tmp/site -maxdepth 2 -type f
```

Confirm that `/tmp/site/<domain>/` contains `urls.txt` plus any downloaded sitemap XML files.

## Maintainer

- [@frittlechasm](https://github.com/frittlechasm)
