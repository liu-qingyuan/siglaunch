# Issue tracker: GitHub

此仓库的 issue、PRD 和工作 ticket 存放在 GitHub Issues 中。所有操作使用 `gh` CLI。

## 仓库

- GitHub 仓库：`liu-qingyuan/siglaunch`
- 从仓库 clone 内运行 `gh` 时，默认从 `git remote` 推断仓库。

## 惯例

- 创建：`gh issue create --title "..." --body "..."`
- 阅读：`gh issue view <number> --comments`
- 列出：`gh issue list --state open --json number,title,body,labels,comments`
- 评论：`gh issue comment <number> --body "..."`
- 添加或删除标签：`gh issue edit <number> --add-label "..."` /
  `gh issue edit <number> --remove-label "..."`
- 关闭：`gh issue close <number> --comment "..."`

## 语言约定

issue 标题、正文、评论和完成摘要默认使用中文。标签、命令、路径、
代码标识符、配置键和错误原文保留原 token。

## 请求入口

**PR 作为请求入口：否。**

`/triage-lqy` 只处理 GitHub Issues，不把外部 PR 纳入相同的 triage 队列。

## Skill 操作

当 skill 要求“发布到 issue tracker”时，创建 GitHub Issue。

当 skill 要求“获取相关 ticket”时，运行：

`gh issue view <number> --comments`

## Wayfinding operations

`/wayfinder-lqy` 使用独立 issue 作为 map，并使用 child issues 作为 Ticket。

- Map 使用 `wayfinder:map` 标签。
- Child Ticket 优先使用 GitHub sub-issues；不可用时，在 map 正文使用 task list，
  并在 child 正文顶部写 `Part of #<map>`。
- Blocking 优先使用 GitHub issue dependencies；不可用时，在正文顶部写
  `Blocked by: #<n>, #<n>`。
- Frontier 只包含没有 open blocker 且没有 assignee 的 open child issues。
- Claim：`gh issue edit <n> --add-assignee @me`。
- Resolve：评论结果、关闭 child，并在 map 的 Decisions-so-far 中追加上下文链接。
