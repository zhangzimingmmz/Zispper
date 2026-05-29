# zispper

zispper 是一个 macOS 菜单栏语音输入工具。

它会监听 `Fn` 键，在按住时录制麦克风音频，松开后把整段音频发送到 ASR 服务，再将识别出的文字粘贴到当前聚焦的输入框中。

## 功能概览

- 菜单栏应用，不显示 Dock 图标
- 按住 `Fn` 录音，松开 `Fn` 转写
- 录制音频统一转换为 16kHz 单声道 PCM，再封装为 WAV 上传
- 本地 ASR 优先，本地不可用时自动切换到 Doubao 极速版作为远程兜底
- 基于会话 ID 处理请求，避免旧请求结果串到新一轮输入
- 文本注入前保存剪贴板，注入后恢复
- 菜单栏图标和菜单状态可反映当前运行状态与当前 provider
- 通过日志文件排查问题

## 运行要求

- macOS 13 或更高版本
- 安装 Xcode Command Line Tools 或完整 Xcode
- Swift 5.7 或更高版本
- 麦克风权限
- 辅助功能权限
- 一个可访问的本地 ASR HTTP 接口，兼容 `POST /v1/audio/transcriptions`
- 如果需要远程兜底，需要配置 Doubao 极速版凭据

## 项目结构

```text
Package.swift
Sources/zispper/
  main.swift            应用入口、状态机、会话主流程
  InputManager.swift    Fn 键监听与辅助功能权限检测
  AudioEngine.swift     麦克风采集与音频格式转换
  ASRClient.swift       本地优先/远程兜底的 ASR 路由与请求处理
  TextInjector.swift    文本注入与剪贴板恢复
  Configuration.swift   运行时配置与环境变量覆盖
  Protocol.swift        日志工具
bundle_app.sh           打包生成 zispper.app 的脚本
```

## 工作流程

```text
Fn 按下
  -> 开始会话
  -> 录制音频
Fn 松开
  -> 停止录音
  -> 优先上传到本地 ASR
  -> 本地不可用时切到 Doubao 极速版
  -> 接收识别文本
  -> 粘贴到当前输入框
```

应用内部使用了一个简单的状态机：

- `idle`
- `recording`
- `finishing`
- `committing`
- `failed`

每次开始录音都会创建新的 `sessionID`。如果旧请求在新会话开始后才返回，结果会被忽略，不会污染当前输入。

## 构建与运行

构建调试版本：

```bash
swift build
```

直接运行：

```bash
swift run
```

如果要生成 `.app` 包：

```bash
bash bundle_app.sh
open zispper.app
```

## 权限要求

zispper 需要两类系统权限：

- `麦克风权限`：用于采集语音
- `辅助功能权限`：用于监听 `Fn` 键以及向当前应用粘贴文本

辅助功能权限路径：

`系统设置 -> 隐私与安全性 -> 辅助功能`

如果权限缺失，应用会进入失败状态，菜单栏图标会显示为异常状态，而不是假装可用。

## 配置项

运行时配置定义在 [Configuration.swift](Sources/zispper/Configuration.swift)。

支持以下环境变量覆盖。旧版 `DOUBAOVOICE_*` 变量仍会作为兼容别名读取，但新配置建议使用 `ZISPPER_*`。

| 变量名 | 默认值 | 说明 |
|---|---|---|
| `ZISPPER_ASR_URL` | `http://100.64.0.6:30766/v1/audio/transcriptions` | ASR 服务地址 |
| `ZISPPER_LOCAL_ASR_HEALTH_URL` | 与 `ZISPPER_ASR_URL` 相同 | 本地 ASR 健康检查地址；未单独配置时仅作粗略探测，最终以转写请求结果为准 |
| `ZISPPER_ASR_LANGUAGE` | `zh` | 请求中提交的语言参数 |
| `ZISPPER_REQUEST_TIMEOUT` | `30` | HTTP 请求超时，单位秒 |
| `ZISPPER_LOCAL_FALLBACK_TIMEOUT` | `2` | 本地 ASR 不可用时等待多久后切到远程兜底，单位秒 |
| `ZISPPER_LOCAL_HEALTH_PROBE_TIMEOUT` | `1` | 本地 ASR 健康检查超时，单位秒 |
| `ZISPPER_LOCAL_HEALTH_CHECK_INTERVAL` | `60` | 本地 ASR 健康检查轮询间隔，单位秒 |
| `ZISPPER_LOCAL_HEALTH_RETRY_COOLDOWN` | `20` | 本地 ASR 标记不可用后，多久允许重新尝试本地请求，单位秒 |
| `ZISPPER_RECORDING_TAIL_DELAY` | `0.1` | 松开按键后额外保留的录音尾延迟，单位秒 |
| `ZISPPER_MIN_RECORDING_DURATION` | `0.25` | 低于该时长的录音会被当作误触忽略，单位秒 |
| `ZISPPER_FINAL_RESULT_TIMEOUT` | `10` | 等待最终识别结果的超时时间，单位秒 |
| `ZISPPER_PASTEBOARD_PASTE_DELAY` | `0.03` | 写入剪贴板后等待多久再触发粘贴，单位秒 |
| `ZISPPER_PASTEBOARD_RESTORE_DELAY` | `0.2` | 文本注入后恢复剪贴板的延迟，单位秒 |
| `ZISPPER_DOUBAO_FLASH_URL` | `https://openspeech.bytedance.com/api/v3/auc/bigmodel/recognize/flash` | Doubao 极速版识别接口地址 |
| `ZISPPER_DOUBAO_APP_ID` | 空 | Doubao App ID；未配置时不启用远程兜底 |
| `ZISPPER_DOUBAO_ACCESS_TOKEN` | 空 | Doubao Access Token；未配置时不启用远程兜底 |
| `ZISPPER_DOUBAO_RESOURCE_ID` | `volc.bigasr.auc_turbo` | Doubao 资源 ID |
| `ZISPPER_DOUBAO_MODEL` | `bigmodel` | Doubao 模型名 |

示例：

```bash
ZISPPER_ASR_URL=http://127.0.0.1:8000/v1/audio/transcriptions \
ZISPPER_DOUBAO_APP_ID=your-app-id \
ZISPPER_DOUBAO_ACCESS_TOKEN=your-access-token \
swift run
```

如果未设置 `ZISPPER_DOUBAO_APP_ID` 或 `ZISPPER_DOUBAO_ACCESS_TOKEN`，应用只会使用本地 ASR，不会启用远程兜底。请通过环境变量注入凭据，不要把个人凭据固化在源码里。

## 日志

日志文件默认写入：

```text
/tmp/zispper.log
```

实时查看日志：

```bash
tail -f /tmp/zispper.log
```

应用菜单中也提供了 `View Logs`，会尝试用 `iTerm` 打开日志跟踪窗口。

## 打包说明

打包脚本位于 [bundle_app.sh](bundle_app.sh)。

它会执行以下步骤：

- 编译 release 二进制
- 创建 `zispper.app`
- 生成最小 `Info.plist`
- 使用 ad hoc 签名对应用包签名

默认的 `Bundle Identifier` 是：

```text
com.zhangziming.zispper
```

如果需要临时覆盖：

```bash
BUNDLE_IDENTIFIER=com.example.zispper bash bundle_app.sh
```

## 手工测试建议

建议至少做一次基础冒烟测试：

1. 启动 `zispper.app`
2. 授予麦克风和辅助功能权限
3. 打开任意可输入文本的应用
4. 按住 `Fn` 说一句话，松开 `Fn`
5. 确认文本成功插入
6. 确认原来的剪贴板内容已经恢复

建议补充测试这些边界场景：

- 快速按下又松开
- 连续多轮短句输入
- 较长句子输入
- 本地 ASR 服务不可达，确认是否自动走远程 provider
- 麦克风权限被拒绝
- 辅助功能权限被拒绝
- 在 TextEdit、浏览器输入框、聊天软件输入框中分别测试

## 当前已知限制

- 文本注入本质上仍然依赖粘贴，因此目标应用必须支持粘贴操作
- 本地与远程 ASR 的文本风格可能略有差异
- 生成的应用包里 ATS 仍然是较宽松配置，后续可以继续收紧
- 暂时没有设置界面
- 暂时没有自动化测试

## 开发说明

- 代码规模较小，没有第三方依赖
- 当前通信模式是整段 HTTP 上传，不是流式 WebSocket ASR
- 优化设计和任务拆分记录在 [openspec/changes/optimize-zispper-core-reliability](openspec/changes/optimize-zispper-core-reliability)

## License

当前仓库还没有附带许可证文件。
