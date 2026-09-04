# Bilingual documentation

Every user-facing document in this repo is maintained in English and Simplified Chinese as a complete pair, following the pairing contract this page defines. `terminology.md` is the terminology source of truth and `translation-rules.md` defines how to translate. The pairing gate is `pnpm run verify-translation-pairing`, part of `pnpm run doc-sync`.

## The pairing contract

- **Both languages carry equal authority.** A change is authored in either language first, and the counterpart is translated from it. Neither file outranks the other; what binds them is that they must say the same thing.
- **A pair is three sibling files.** The English `foo.md`, the Chinese `foo.zh.md`, and a consistency record `foo.i18n.yaml`, all in the same directory. No locale directories, no separate translation repo. Pairs merge whole: a PR never lands one language without the other two files.
- **The consistency record.** `foo.i18n.yaml` holds the full git blob hash of each side as of the last time the two were confirmed to say the same thing:

  ```yaml
  foo.md: 3f786850e387550fdab836ed7e6dc881de23001b
  foo.zh.md: 89e6c98d92887913cadf06b2adb97f26cde4849b
  ```

  Blob hashes, not commit hashes, so the record is computable for files edited in the same PR (`git hash-object foo.md`) and consistency is a pure content comparison. `--write` stores those snapshots in the local Git object database before recording them, including uncommitted working-tree contents. After bringing a pair back in line, re-record with `pnpm run verify-translation-pairing --write foo.md`; that yaml diff is the reviewable act of confirming consistency, which is why `--write` requires naming the pairs you confirmed (`--write --all` is the explicit corpus-wide form).
- **Language switcher.** The Chinese file always links back immediately after its H1 with `[English](foo.md) | 中文`. The English file reciprocates there with `English | [中文](foo.zh.md)`.
- **Structure mirrors the counterpart.** Heading depths and order, list kinds, ordered-list starts, list item counts, table row and column counts, semantic link targets with exact query/fragment suffixes, and verbatim code blocks match one to one across the pair. When a relative document link targets the bilingual corpus, the English side uses its `.md` path and the Chinese side uses its `.zh.md` path; targets outside the corpus keep the authored path. See `translation-rules.md` for the full preservation rules.

## The gate: verify-translation-pairing

`pnpm run verify-translation-pairing` (part of `doc-sync`) enforces the contract mechanically:

1. Every in-scope document has a complete pair.
2. Each side's current blob hash equals the recorded one (editing either side without re-confirming goes red), and the structural signatures match in order.
3. Files listed as `excluded` in `scripts/translation-pairing.manifest.json` have no `.zh.md` and no `.i18n.yaml` at all.

`pnpm run verify-translation-pairing --list` prints the state of every in-scope document; `pnpm run verify-translation-pairing <pair...>` checks just the named pairs so an update loop verifies its own pair in seconds. A green gate means the pair was confirmed consistent at these exact contents, not that the confirmation was sound: it checks hashes and structure, not whether the two sides actually say the same thing. That is the reviewer's half of the contract.

## Scope and exclusions

**In scope**: the root `README.md` and every user-facing document under `docs/` (`docs/design.md`, `docs/security.md`, `docs/usage.md`). README matching is case-insensitive on the basename.

**Excluded** (never paired; the gate rejects a `.zh.md` or `.i18n.yaml` for them): `AGENTS.md` and agent instructions under `docs/agents/` (English only), `CONTEXT.md` and `docs/research/` (bilingual or research vocabulary, maintained separately), `RELEASE.md`, and this `docs/i18n/` corpus's own operational files (`terminology.md` is bilingual by construction, `translation-rules.md` is single-language). The manifest `scripts/translation-pairing.manifest.json` holds the explicit exclusions.

## Division of labor

Routine counterparts are updated by the working agent in one terminology-guided pass after loading `terminology.md`; it edits the counterpart directly, preserves untouched prose, verifies the changed hunks clause by clause, and re-records with `verify-translation-pairing --write <pair>`. A heavier briefing mechanism, `pnpm run gen-translation-brief`, can assemble the narrowest safely aligned update when a pair drifts.

## Definition of done

A bilingual change is done when both sides say the same thing, structure and code blocks mirror exactly, terminology follows `terminology.md`, the pair passes `pnpm run verify-translation-pairing`, and the `.i18n.yaml` diff is the only remaining artifact of having confirmed it.
