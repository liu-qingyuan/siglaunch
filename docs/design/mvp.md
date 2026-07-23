# Siglaunch MVP 设计规格

本文记录原型讨论中已确认、但尚未稳定到需要 ADR 的产品行为与可调参数。参数在实机测试后可以直接调整。

## 目标

验证一个本地优先的 macOS 菜单栏应用能否持续识别单用户的精确单手姿态，并可靠触发一个真实开发 Workspace。

## 已确认范围

- 已有 Personal Recognizer 时，应用启动后默认进入 Active Monitoring；首次启动且尚无 Personal Recognizer 时进入 Setup Required，并保持摄像头关闭。
- 用户可从菜单栏切换到 Paused Monitoring；暂停必须停止采集并释放摄像头。
- 退出菜单项完全结束应用进程。
- MVP 只有一个真实 Workspace、一个 Primary Workflow 和一个 Trigger Gesture。
- Diagnostic Gesture 只验证摄像头与 Vision 手部姿态检测，绝不触发 Workflow。
- Trigger Gesture 是用户提供参考图中的单手 Domain Expansion Pose。
- 精准识别指 MacBook 正面摄像头画面中可见的交叉和接触外观，不声称验证三维物理接触。
- 识别只面向一名用户和当前 MacBook；用户在 App 中导入 Pose Dataset，并在本机训练和启用 Personal Recognizer。
- MVP 不要求用户执行固定次数的手势测试或长时间误触验收流程。

## 训练入口

- 设置界面提供“导入训练集”命令，使用系统文件选择器读取本地图片目录。
- Pose Dataset 根目录必须包含 `domain_expansion/` 和 `other/` 两个标签目录，每类至少包含 `10` 张可读取图片。
- `domain_expansion/` 保存交叉和接触外观正确的目标手型；`other/` 保存其他单手姿态，尤其是接近但不完全正确的困难负样本。
- App 报告并跳过 Vision 无法检测到手的图片；任一标签的有效图片不足 `10` 张时拒绝开始训练。
- 训练在本机通过 Create ML 执行，不上传图像或模型。
- App 在训练前使用与运行时相同的 Vision 手部定位与裁剪流程规范化图片。
- App 自动按标签分层划分训练与验证数据，用户不需要准备独立测试目录。
- 训练成功后保存 Personal Recognizer，并将其用于后续 Gesture Monitoring。
- Recognizer Training 开始前记录当前监听状态，停止采集并释放摄像头；训练结束后恢复此前状态。
- 新 Personal Recognizer 训练和保存成功后才原子替换当前模型；失败或取消时继续使用旧模型。
- 菜单栏显示训练进度并提供取消命令。

## 识别管线

1. AVFoundation 持续提供摄像头帧。
2. Vision 检测手部姿态并定位候选手部区域。
3. 应用裁剪规范化的手部图像。
4. 自定义 Core ML 图像分类器判断 Domain Expansion Pose。
5. 状态机根据多个 Pose Match 决定是否触发 Primary Workflow。

Vision 提供二维关节点与置信度，不提供手指深度或物理接触信号。因此 Core ML 分类器匹配的是二维可见外观。

摄像头采集与分类使用同一个 Recognition Frame Rate。MVP 不采集高帧率视频后再跳过部分帧；每个交付给应用的摄像头帧都应进入识别管线。

摄像头帧使用容量为 `1` 的最新帧缓冲。如果设备无法按目标帧率完成处理，新帧覆盖尚未处理的旧帧；诊断信息同时显示目标帧率与实际完成分类的帧率，证据窗口只统计真正完成分类的帧。

## 触发规则

- 自定义分类器必须将 `domain_expansion` 判为最高概率标签且置信度至少为 `0.75`，该帧才构成 Pose Match。
- 证据窗口保留最近 `5` 个已完成分类的帧。
- 窗口中至少 `3` 个 Pose Match 即识别成功；不要求连续命中。
- 正常连续采集期间不施加时间限制。
- Recognition Frame Rate 由用户配置，摄像头采集和分类使用相同的目标帧率，实际识别延迟随该设置变化。
- Recognition Frame Rate 提供 `10`、`15`、`30 FPS` 三档，默认 `15 FPS`；设备不支持目标值时，使用最接近且不高于目标值的实际帧率。
- 暂停、恢复、摄像头切换、系统休眠、模型重载或采集流中断时清空证据窗口。
- 识别成功后，目标手型必须消失约 `1 秒`，并且自成功起至少经过 `5 秒`，系统才可 Rearm。

## 工作流边界

- Siglaunch 在识别成功后先检查 Ghostty 是否已安装并正在运行；未安装时停止并报告错误，未运行时先启动 Ghostty。
- MVP 要求 Ghostty `1.3.0+`，通过其原生 AppleScript API 控制终端并启动命令；首次使用需要用户授予 macOS Automation 权限。
- Siglaunch 不使用模拟键盘输入或向当前 shell 粘贴命令作为回退；Ghostty 版本不满足或权限被拒绝时明确失败。
- Siglaunch 确保 Ghostty 中连接的是 Herdr 默认 Session；若默认 Session 尚未运行，则在 Ghostty 中启动 `herdr`。
- 默认 Herdr Session 可用后，Siglaunch 通过 Herdr 的 Agent 命令检查 Pi Agent。
- Siglaunch 先按 `agent == "pi"` 与规范化后的 Workspace 路径筛选 Pi Agent；存在匹配项时选择 Herdr 返回顺序中的 Leading Pi Agent 并聚焦。
- 不存在匹配的 Pi Agent 时，由 Herdr 在目标目录启动或恢复；Siglaunch 不因存在多个匹配项而报错。
- Siglaunch 不绕过 Herdr 直接枚举或管理 Pi 会话。

## HUD

- 第一个和第二个 Pose Match 只更新内部候选进度，不显示屏幕 HUD，也不高频改变菜单栏图标。
- 普通下拉菜单只显示稳定状态和命令，不随每个完成分类帧刷新。
- 证据窗口达到 `3/5` 后，在当前屏幕显示不抢键盘焦点的透明 HUD。
- Domain Expansion HUD 立即显示“领域展开”；MVP 特效为细线圆环快速展开，持续约 `1.2 秒`。
- HUD 不阻塞 Primary Workflow，也不改变当前前台应用的激活状态。
- 未达到触发门槛的候选不显示屏幕弹窗；MVP 默认不播放声音。
- 菜单栏不提供“重试上次 Workflow”命令。
- Primary Workflow 成功时不追加完成文案，Domain Expansion HUD 按原动画淡出。
- Primary Workflow 失败时，动画结束后显示包含失败步骤的简短错误 HUD；错误只允许关闭，不提供重试。
- 整个 Primary Workflow 失败后不自动从头重跑；用户下一次完成 Trigger Gesture 时产生新的尝试。

## 诊断手势

- Diagnostic Gesture 是由 Vision 关节规则直接判断的单手张开手掌，不使用第二个自定义模型。
- Diagnostic Gesture 只能更新诊断输出，绝不能产生 Workflow 触发效果。

## 识别诊断

- 用户从菜单栏打开一个只读的 Recognition Diagnostics 窗口；普通下拉菜单保持稳定，不显示逐帧数据。
- 窗口只显示实时摄像头、实际送入分类器的归一化手部 crop、当前最高类别与 confidence、是否构成 Pose Match、最近 `5` 帧中的 Pose Match 数量，以及目标、采集和完成分类 FPS。
- 窗口固定显示判定规则：`domain_expansion` 必须为最高类别且 confidence `>= 0.75`，最近 `5` 个完成分类帧至少 `3` 个 Pose Match 才产生 Recognition Success。
- 窗口打开时不启动 Workflow，不保存图像，不调整阈值，也不训练、修改或替换 Personal Recognizer；关闭时清空证据并恢复此前的监听状态。
- 本轮不自动收集或判断是否需要更多样本；用户根据窗口中的实时证据自行分析，现有 Pose Dataset 和 Personal Recognizer 保持不动。

## 安装与启动

- 项目继续使用 SwiftPM；本地安装命令从 release 可执行文件形成 Siglaunch App Bundle，并安装到 `/Applications/Siglaunch.app`。
- 本地安装命令使用当前 Mac 已配置的 Developer ID Application 身份签名；签名身份不可用时明确失败，不回退到 ad-hoc 签名。
- MVP 不做公证、外部分发、安装包或自动更新。
- `/Applications/Siglaunch.app` 是日常使用入口；仓库中的 `.build` 可执行文件只用于开发。
- Siglaunch App Bundle 保持 `LSUIElement=true`：运行时常驻菜单栏，不显示 Dock 图标，但可以从 Applications、Launchpad、Spotlight 或 `open -a Siglaunch` 手动打开。
- “Quit Siglaunch”完全结束进程；退出后通过相同入口再次启动。
- 更新时重新运行同一本地安装命令并替换 App Bundle；Application Support 中的 Personal Recognizer、Pose Dataset 产物和 Workflow 配置不随 App 更新删除。
- MVP 不自动登录启动。

## 实现范围

- MVP 写死 Domain Expansion Pose 的两阶段识别管线、`3/5` 触发规则、Ghostty 到默认 Herdr Session 再到 Pi Agent 的步骤顺序，以及 Domain Expansion HUD。
- App 设置只提供暂停或恢复、Recognition Frame Rate、导入 Pose Dataset、Recognizer Training 进度，以及打开 Recognition Diagnostics 的入口。
- 本地 Workflow 配置只保存 Workspace 路径和 Pi 启动命令。
- MVP 不实现多 Trigger Gesture、多 Workspace、脚本编辑器、插件系统、特效编辑器、云训练或登录时启动。
- 内部 Module 保持清晰 Interface，但不预先设计插件协议。
