---
status: accepted
---

# 通过 AppleScript 自动化 Ghostty

Siglaunch MVP 要求 Ghostty 1.3.0 或更高版本，并通过其原生 AppleScript API 检查和控制终端、启动 Herdr 默认 Session。该方案需要用户授予 macOS Automation 权限，但相比模拟键盘输入或盲目启动重复 Ghostty 实例，目标明确且失败可诊断；用户拒绝权限时应用明确报告错误，不静默降级。
