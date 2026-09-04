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

## Bilingual documentation

User-facing docs merge as complete English/Chinese pairs: the English `foo.md`, the
Chinese `foo.zh.md`, and a consistency record `foo.i18n.yaml` (git blob hashes) live
together in one directory. Either side can be the source of a change; the counterpart
is brought along in the same change and the pair is re-recorded with
`pnpm run verify-translation-pairing --write <pair>`. Structure, code blocks, and
links mirror one to one; in-corpus links use `.md` on the English side and `.zh.md`
on the Chinese side. `CONTEXT.md`, `docs/agents/**`, `docs/research/**`, and
`docs/i18n/**` are exempt. Full contract: `docs/i18n/README.md`; rules and
terminology: `docs/i18n/translation-rules.md` and `docs/i18n/terminology.md`.

Run the local documentation gate before push: `pnpm run doc-sync` (pairs must stay
green; the repo's package manifest depends on `dist/` closure artifacts, so there is
no branch CI for docs — the gate is local and pre-push).

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