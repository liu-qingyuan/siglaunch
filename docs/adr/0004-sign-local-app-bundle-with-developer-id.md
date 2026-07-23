---
status: accepted
---

# 使用 Developer ID 签名本地 App Bundle

Siglaunch 继续使用 SwiftPM，并由本地安装命令形成 `/Applications/Siglaunch.app`；安装命令使用当前 Mac 已配置的 Developer ID Application 身份签名，身份不可用时明确失败，不回退到每次构建可能改变身份的 ad-hoc 签名。这样可以让摄像头与 Automation 权限依赖稳定的 App 身份；当前范围不包含公证、外部分发、安装包或自动更新。
