# AGENTS.md

本文件为在此仓库中工作的 agent 提供约定。

## Agent skills

### Issue tracker

本仓库的 issue 存放在 GitHub Issues 中（使用 `gh` CLI 读写）。参见 `docs/agents/issue-tracker.md`。

### Triage labels

使用五个标准分流标签：`needs-triage`、`needs-info`、`ready-for-agent`、`ready-for-human`、`wontfix`。参见 `docs/agents/triage-labels.md`。

### Domain docs

单一上下文：根目录 `CONTEXT.md` + `docs/adr/`。参见 `docs/agents/domain.md`。