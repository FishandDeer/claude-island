# Claude Island

一个原生 macOS 桌面灵动岛，用中文显示 Claude Code 当前状态。

Claude Island 通过 Claude Code hooks 写入本地状态文件，再由一个轻量 Cocoa 浮窗读取并展示状态。它不读取屏幕内容，不上传数据，也不保存提示词内容。

## 功能

- 中文状态显示：就绪、思考中、执行中、等你输入、需授权、出错、离线
- 状态变化提示音，首次启动读取当前状态时不会响
- 点击跳转到当前运行 Claude Code 的终端或编辑器窗口
- 固定模式贴合 MacBook 相机左侧区域，支持 1px 微调
- 执行中/思考中显示运行时长
- 等待输入/需授权时使用琥珀色呼吸描边和三连提示音

## 显示状态

- 就绪
- 思考中
- 执行中
- 等你输入
- 需授权
- 出错
- 离线

左侧状态指示器使用光核样式：工作状态会轻微呼吸，错误状态会短暂抖动。
执行中/思考中会显示运行时长；等待输入、需授权、出错时会自动轻微展开；长时间无更新会显示离线。
等待输入/需授权时会显示琥珀色呼吸描边，并播放三连提示音；如果一直未处理，会周期性重复提醒。点击灵动岛跳回 Claude 界面后，会停止当前这次确认提醒。

## 系统要求

- macOS 13 或更高版本
- Xcode Command Line Tools
- Claude Code

## 安装

克隆仓库后运行：

```sh
Scripts/build-app.sh
Scripts/install-claude-hooks.py
open "dist/Claude Island.app"
```

## 安装 hooks

```sh
Scripts/install-claude-hooks.py
```

安装脚本会：

- 复制 hook 脚本到 `~/.claude/claude-island/claude-island-hook.sh`
- 写入初始状态文件 `~/.claude/claude-island/status.json`
- 备份 `~/.claude/settings.json`
- 追加 Claude Code hooks，不覆盖已有 hooks

## 打包 app

```sh
Scripts/build-app.sh
```

输出：

```text
dist/Claude Island.app
```

## 启动和退出

启动：

```sh
open "dist/Claude Island.app"
```

退出：

```sh
Scripts/quit-app.sh
```

## 卸载 hooks

```sh
Scripts/uninstall-claude-hooks.py
```

卸载脚本会备份 `~/.claude/settings.json`，然后移除 Claude Island 追加的 hooks。

## 隐私

Claude Island 只写入并读取本地状态文件：

```text
~/.claude/claude-island/status.json
```

状态文件只包含状态、时间戳和 hook 事件名，不包含提示词、代码内容或 Claude 回复。

## License

MIT
