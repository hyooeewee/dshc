# Issue 追踪器：GitHub

本仓库的 Issues 和规格说明以 GitHub Issue 形式存在。所有操作请使用 `gh` CLI。

## 约定

* **创建 Issue**：`gh issue create --title "..." --body "..."`。多行正文请使用 heredoc。
* **读取 Issue**：`gh issue view <number> --comments`，通过 `jq` 过滤评论，并同时获取标签。
* **列出 Issues**：`gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'`，并按需使用 `--label` 和 `--state` 过滤器。
* **评论 Issue**：`gh issue comment <number> --body "..."`
* **添加 / 移除标签**：`gh issue edit <number> --add-label "..."` / `--remove-label "..."`
* **关闭**：`gh issue close <number> --comment "..."`

从 `git remote -v` 推断仓库——在克隆内运行时，`gh` 会自动完成。

## 将 Pull Request 作为分流入口

**是否将 PR 作为请求入口：否。** *（如果此仓库将外部 PR 视为功能请求，则设为 `yes`；`/triage` 会读取此标志。）*

## 当某个技能说“发布到 issue tracker”时

创建一个 GitHub Issue。

## 当某个技能说“获取相关工单”时

运行 `gh issue view <number> --comments`。

## 寻路操作

由 `/wayfinder` 使用。**地图**是一个单一的 issue，**子** issues 作为工单。

* **地图**：一个标记为 `wayfinder:map` 的 Issue，承载 Notes / Decisions-so-far / Fog 正文。`gh issue create --label wayfinder:map`。
* **子工单**：作为 GitHub 子 Issue 链接到地图的 Issue（使用 sub-issues 端点上的 `gh api`）。如果未启用子 Issue，则将子项添加到地图正文的任务列表中，并在子工单正文顶部放置 `Part of #<map>`。标签：`wayfinder:<type>`（`research`/`prototype`/`grilling`/`task`）。一旦被认领，工单将分配给负责的开发者。
* **阻塞**：GitHub 的**原生 Issue 依赖**——规范的、UI 可见的表示。使用 `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>` 添加一条边，其中 `<blocker-db-id>` 是阻塞者的数字**数据库 ID**（`gh api repos/<owner>/<repo>/issues/<n> --jq .id`，*不是* `#number` 或 `node_id`）。GitHub 报告 `issue_dependencies_summary.blocked_by`（仅开放阻塞者——实时门禁）。如果依赖不可用，则回退到在子工单正文顶部添加 `Blocked by: #<n>, #<n>` 一行。当所有阻塞者都关闭时，工单解除阻塞。
* **前沿查询**：列出地图的开放子项（`gh issue list --state open`，范围限定在地图的子 Issue / 任务列表中），丢弃任何带有开放阻塞者（`issue_dependencies_summary.blocked_by > 0`，或 `Blocked by` 行中的开放 Issue）或已被指派人的子项；按地图顺序第一个获胜。
* **认领**：`gh issue edit <n> --add-assignee @me`——会话的第一次写入。
* **解决**：`gh issue comment <n> --body "<answer>"`，然后 `gh issue close <n>`，接着将上下文指针（gist + 链接）追加到地图的 Decisions-so-far。