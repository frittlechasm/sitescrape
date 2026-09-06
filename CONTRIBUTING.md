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

## Validation

Run syntax checks and the fixture-based CLI tests:

```bash
bash -n sitescrape
bash -n install.sh
bash tests/run.sh
```

The tests exercise the real scripts with a fake `curl`, so they do not need network access. They use unique directories under `/tmp/site` and clean them up afterward.

## Maintainer

- [@frittlechasm](https://github.com/frittlechasm)
