# Contributing to opus-gemini-orchestrator

Contributions are welcome. Please follow these guidelines to maintain quality and consistency across the project.

## Running Tests Locally

Run the test suite locally before submitting changes:

```bash
bash tests/test_scripts.sh
bash tests/test_install.sh
```

Check all shell scripts with ShellCheck using severity level error:

```bash
shellcheck -S error skills/opus-gemini-orchestrator/bin/* skills/opus-gemini-orchestrator/scripts/*.sh tests/*.sh
```

## Script Guidelines

- Keep all scripts bash-only. Do not introduce new dependencies.
- Rely only on core tools: bash, jq, sqlite3, python3, and git.
- Never call the real `agy` binary in tests. Use mocks or stubs.
- Describe verified `agy` behaviour alongside the specific `agy` version in `skills/opus-gemini-orchestrator/reference/agy-cli.md`.

## Workflow

- Open an issue before proposing large changes.
- Limit each pull request to one feature or bugfix.
