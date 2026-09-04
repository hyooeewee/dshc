# Translation rules

How to translate between the two sides of a documentation pair in this repo. Both languages carry equal authority ([README.md](README.md)): a change is authored in either language, and that side is the source for that update — these rules govern producing or updating the counterpart. They bind humans and agents equally. Rule levels follow RFC 2119 usage: **MUST** / **MUST NOT** are gate- or review-blocking; **SHOULD** needs a stated reason to deviate; **MAY** is discretionary.

## Faithfulness

- The counterpart *MUST* say what the authored side says — no added behavior, prerequisites, warnings, version claims, or examples, and no dropped ones. If the pair disagrees on substance, neither language wins by default: fix the side that is wrong, then bring the other along in the same change.
- The counterpart *SHOULD* read as natural technical writing in its own language, not word-by-word gloss. Translate meaning, restructure sentences where the target grammar wants it, and keep the author's register.
- Do not translate the untranslatable: if a sentence resists natural rendering because it leans on an idiom of the source language, translate the idea, not the idiom.

## Voice

- Chinese targets use institutional technical Chinese; English targets use concise professional developer prose.
- Write as a native technical author restating the content, not as a translator transposing sentences, while preserving every source clause: nothing added, nothing dropped — fluency never justifies losing a clause.
- Give sentences an explicit actor when the target language would otherwise obscure it; for Chinese, replace vague passives or abstract subjects with the actual actor (镜像、门禁、评审人).
- Prefer established target-language engineering idiom over calques; localize metaphors instead of transplanting them.
- Split long paragraphs by semantic unit — one idea per paragraph. Paragraph boundaries MAY differ from the source; the structural signature does not count paragraphs.
- Literal file and directory references stay code-formatted English on both sides.

## Structure preservation

The pairing gate checks heading depths, fenced code blocks, table row and column counts, list kinds, ordered-list starts, list item counts, link locale, and semantic targets. Preserve the rest of the frame manually; the paired files MUST match one to one in:

- heading hierarchy (same levels, same order — heading TEXT is translated),
- list shape and numbering,
- tables (same columns, same row order; header cells translated per terminology),
- fenced code blocks — **byte-identical, including comments**; the pairing signature compares their info strings and contents,
- inline code spans (commands, flags, config keys, file paths, container paths, env variable names, API names, version numbers, image tags) — verbatim, never translated or reformatted,
- links and anchors: every relative document link MUST keep the same semantic target and exact query/fragment suffix. When the target belongs to the bilingual corpus, the English side uses its `.md` path and the Chinese side uses its `.zh.md` path; targets outside it (for example `RELEASE.md`, `.env.example`) keep the original path. External URLs, images, and pure in-page fragments stay unchanged. The language switcher remains the explicit cross-locale exception. Link TEXT is translated.

## Terminology

- [terminology.md](terminology.md) is the source of truth in both directions. Before translating, load it; every listed term MUST follow its row and its "不要译作" prohibitions. A Chinese target uses the "中文" column and its "首次出现" annotation; an English target uses the "English" column.
- For a Chinese target, an unlisted technical term MAY use an established rendering from a major Chinese-language OSS or vendor source (K8s/Vue/MDN Chinese docs, 微软简中风格指南, big-tech project docs), cited in the PR. Without such precedent it MUST stay in English and be listed under 「待定术语」(pending terms) with a suggested rendering.
- Neither direction may invent a rendering inline; a decided term enters [terminology.md](terminology.md) in the same PR or a follow-up.
