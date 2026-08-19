# AGENTS.md

Conventions for agents working in this repository.

## Language

To avoid encoding surprises in code and tooling, all project text is written in **English**:

- Code comments, source files, docs, and commit messages are in English.
- Comments are restrained: write one only when it explains *why* something is
  non-obvious — never restate what the code does.
- Chinese (or other non-ASCII) appears only in:
  - `*.zh.md` files — user-facing Chinese translations (e.g. `README.zh.md`);
  - places the human explicitly requested Chinese (e.g. this chat, the wayfinder
    flow) — those are not committed to the project tree.

## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues (read/write via the `gh` CLI).
See `docs/agents/issue-tracker.md`.

### Triage labels

Uses the five standard triage labels: `needs-triage`, `needs-info`,
`ready-for-agent`, `ready-for-human`, `wontfix`.
See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: root `CONTEXT.md` + `docs/adr/`. See `docs/agents/domain.md`.