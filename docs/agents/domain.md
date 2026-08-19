# 领域文档

工程技能在探索代码库时，应如何使用本仓库的领域文档。

## 探索之前，请先阅读这些

* 仓库根目录下的 **`CONTEXT.md`**，或
* **`CONTEXT-MAP.md`**，如果它存在于仓库根目录 — 它为每个上下文指向一个 `CONTEXT.md`。请阅读与当前主题相关的每一个。
* **`docs/adr/`** — 阅读与你即将工作的领域相关的 ADR。在多上下文仓库中，还要检查 `src/<context>/docs/adr/` 以获取上下文范围内的决策。

如果这些文件中有任何不存在，**请静默继续**。不要标记它们的缺失；也不要建议提前创建它们。`/domain-modeling` 技能（通过 `/grill-with-docs` 和 `/improve-codebase-architecture` 触达）会在术语或决策实际得到解决时惰性创建它们。

## 文件结构

单上下文仓库（大多数仓库）：

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-event-sourced-orders.md
│   └── 0002-postgres-for-write-model.md
└── src/
```

多上下文仓库（根目录存在 `CONTEXT-MAP.md`）：

```
/
├── CONTEXT-MAP.md
├── docs/adr/                          ← 全局决策
└── src/
    ├── ordering/
    │   ├── CONTEXT.md
    │   └── docs/adr/                  ← 上下文范围内的决策
    └── billing/
        ├── CONTEXT.md
        └── docs/adr/
```

## 使用术语表的词汇

当你的输出命名一个领域概念时（在 issue 标题、重构提案、假设、测试名称中），请使用 `CONTEXT.md` 中定义的术语。不要偏离到术语表明确避免的同义词。

如果你需要的概念尚未出现在术语表中，那是一个信号 — 要么你在发明项目不使用的语言（请重新考虑），要么确实存在缺口（请将其记录给 `/domain-modeling`）。

## 标记 ADR 冲突

如果你的输出与现有 ADR 矛盾，请显式地将其提出，而不是静默覆盖：

> *与 ADR-0007（事件溯源订单）矛盾 — 但值得重新讨论，因为…*