---
status: accepted
---

# 由 Herdr 持有终端和 Agent 生命周期

Siglaunch MVP 只负责在 Trigger Gesture 成功后确保 Ghostty 正在运行，并在其中连接 Herdr 的默认 Session；Pi Agent 的查找、启动、聚焦与恢复均通过 Herdr 完成。让 Siglaunch 绕过 Herdr 直接管理 Pi 会产生两个生命周期所有者，并把启动器绑定到 Pi 的会话实现细节。
