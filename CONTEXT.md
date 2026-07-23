# Siglaunch

Siglaunch 是一个本地优先的 macOS 开发者工作流启动 Hub，通过用户定义的手势触发工作空间启动流程。

## Language

**Gesture Monitoring**:
应用持续观察摄像头中的候选手势，直到用户从菜单栏暂停监听或退出应用。
_Avoid_: Recognition Window, Scan Session

**Active Monitoring**:
Gesture Monitoring 正在运行，应用可以观察并识别手势。
_Avoid_: Running, Enabled

**Paused Monitoring**:
应用仍驻留菜单栏，但不再观察用户且不占用摄像头；用户可以从菜单栏恢复 Active Monitoring。
_Avoid_: Disabled, Muted

**Setup Required**:
尚无 Personal Recognizer、因此不能进入 Gesture Monitoring 的首次使用状态。
_Avoid_: Unconfigured, Disabled

**Workflow**:
由一个手势触发、用于进入开发工作状态的一组有序步骤。
_Avoid_: Macro, Script

**Primary Workflow**:
MVP 中唯一会实际启动 Workspace 的 Workflow。
_Avoid_: Default Workflow

**Trigger Gesture**:
完成识别后可以启动 Workflow 的手势。
_Avoid_: Command Gesture, Activation Gesture

**Domain Expansion Pose**:
参考用户提供图像定义的单手姿态；在 MacBook 正面摄像头视角中，目标手指必须呈现指定的交叉和接触外观。
_Avoid_: Approximate Seal, Two-Hand Expansion

**Domain Expansion HUD**:
Domain Expansion Pose 识别成功后显示的非交互式屏幕反馈，首要文案为“领域展开”。
_Avoid_: Launch Notification, Progress Dialog

**Pose Dataset**:
用户提供、用于建立其个人 Domain Expansion Pose 识别能力的一组本地图像。
_Avoid_: Reference Image, Sample Upload

**Personal Recognizer**:
从一名用户的 Pose Dataset 建立、面向该用户和当前 MacBook 的识别器。
_Avoid_: Universal Model, Shared Classifier

**Recognizer Training**:
使用 Pose Dataset 在本机建立新的 Personal Recognizer 的过程。
_Avoid_: Model Upload, Cloud Training

**Pose Match**:
一个完成分类的摄像头帧被认定呈现了 Domain Expansion Pose。
_Avoid_: Hit, Positive Frame

**Recognition Success**:
在 Active Monitoring 且已 Rearm 时，系统确认 Trigger Gesture，并以同一触发显示 Domain Expansion HUD、且仅启动一次 Primary Workflow。Workflow 的最终结果不属于 Recognition Success。
_Avoid_: Workflow Success, HUD Display

**Rearm**:
Trigger Gesture 成功后，系统重新获得触发 Workflow 资格的状态转换。
_Avoid_: Reset, Reactivate

**Diagnostic Gesture**:
用于验证摄像头与手部姿态检测、但绝不会启动 Workflow 的简单静态手势。
_Avoid_: Test Gesture

**Recognition Diagnostics**:
用户从菜单栏打开的只读实时识别窗口，用于直接查看分类器输入、当前判定和固定触发规则；打开窗口不会启动 Workflow，也不会修改 Personal Recognizer。
_Avoid_: Calibration Mode, Validation Session

**Siglaunch App Bundle**:
安装在 `/Applications/Siglaunch.app`、供用户日常打开 Siglaunch 的本地 macOS App；SwiftPM 的 `.build` 可执行文件只用于开发。
_Avoid_: Development Executable, Menu Bar Item

**Workspace**:
一个可被 Workflow 启动或恢复的项目工作环境。
_Avoid_: Project, Profile

**Herdr Session**:
一个持久的终端工作环境，持有 Workspace 目录以及其中 Pi Agent 的运行状态。
_Avoid_: Terminal Session, Pi Session

**Pi Agent**:
在 Herdr Session 内启动或恢复的个人编码 Agent 进程。
_Avoid_: Assistant, Bot

**Leading Pi Agent**:
符合目标 Agent 类型与 Workspace 路径后，在 Herdr 返回顺序中排第一的 Pi Agent。
_Avoid_: Most Recent Agent, Focused Agent
