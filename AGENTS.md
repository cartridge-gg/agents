# Repository Guidelines

## Project Structure & Module Organization

- The repository is currently minimal: `README.md` lives at the root and no source, test, or asset directories exist yet.
- When adding code, keep the root clean and introduce standard folders (example: `src/` for implementation, `tests/` for tests, `assets/` for static files).
- Mirror structure between `src/` and `tests/` so it is easy to find related files.

## Build, Test, and Development Commands

- No build, test, or run commands are defined yet.
- If you add a build system, document it in this file and the `README.md` (examples: `npm run build`, `pytest`, `make test`).
- Prefer one canonical command per task and keep scripts in the repository root.

## Coding Style & Naming Conventions

- No formatter or linter is configured yet. When introducing a language, add a formatter or linter and document it here.
- Until tooling exists, use consistent indentation (2 spaces for JSON/YAML/Markdown lists, 4 spaces for code) and avoid tabs.
- Use descriptive, lowercase, hyphenated names for Markdown files (example: `architecture-overview.md`).

## Testing Guidelines

- No testing framework is configured; coverage targets are not defined.
- If tests are added, place them under `tests/` and mirror `src/` paths (example: `src/foo/bar.js` -> `tests/foo/bar.test.js`).
- Document the chosen framework and the primary test command here.

## Commit & Pull Request Guidelines

- Git history currently includes only `first commit`, so no established commit message convention exists.
- Recommended format: short imperative summary (<= 72 characters), optionally with a scope (example: `docs: add contribution guide`).
- Pull requests should include a brief description, rationale, and testing notes; add screenshots for UI changes.

## Security & Configuration Tips

- Do not commit secrets or local credentials. If configuration is needed later, provide a sample file (example: `.env.example`).

## Skills Index

- The generated hierarchy for `.agents/skills` lives between the markers below and is refreshed by `generate_index.sh`.
<!-- SKILLS_INDEX_START -->
skills|create-pr:{create-pr.md}
<!-- SKILLS_INDEX_END -->
