# Repository Guidelines

- Keep the CLI self-contained and compatible with Bash 3.2 on macOS and Linux.
- Preserve the current CLI and `/tmp/site` output behavior unless asked otherwise.
- Run `bash -n` on each changed shell script. Run `bash tests/run.sh` for CLI, installer, or test changes.
- Extend the existing offline fixture tests. Isolate installer tests' home and install directories; clean up only test-owned output.
- Keep CI deferred unless requested.
- Update `README.md` when usage, installation, or behavior changes.
- Keep development and validation instructions in `CONTRIBUTING.md`.
- Keep README installer links on `main`. The installer must resolve the latest published release and download its payload from that immutable release tag.
