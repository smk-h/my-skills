<!-- more -->

本文件面向 AI 编程代理（Claude Code、CodeBuddy、OpenCode、ZCode、dsh 等），按二级标题分主题约定工程规则。

## 一、 文件编码规则

### 1. 既有文件：保持原样

（1）只改内容，不动格式：原编码（UTF-8、GBK、GB18030、UTF-16 等）、BOM、行尾符（CRLF/LF）一律随原文件。

（2）禁止按错误编码读入再整体写回（如以 UTF-8 读写 GBK 文件），这是乱码的主要来源。

（3）编码不确定时先向用户确认，禁止猜测；打开文件已现乱码，停止修改。

### 2. 新建文件：默认 UTF-8

（1）默认 UTF-8（无 BOM）、LF 行尾；Windows 下也不例外，含中文也不用 GBK。

（2）例外：`.ps1` 面向 PowerShell 5.1 处理中文时用带 BOM 的 UTF-8（PowerShell 7 不需要）；`.bat`、`.cmd` 含中文且需 cmd 直接执行时按 GBK。

（3）项目已有 `.gitattributes`、`.editorconfig` 等显式约定时，从项目约定。

### 3. 检测与自检

（1）改前确认编码：VS Code 状态栏，或 Git Bash 的 `file -bi <文件>`。

（2）改后用 git diff 验证：只改几行却整文件标变，说明编码或行尾符被改变，恢复重做；脚本批量重写同样适用。

## 二、 画图规则

### 1. 技能选择

（1）时序图一律用 plantuml-diagram，其余图一律用 diagram-design。

（2）excalidraw-diagram 仅限用户点名时使用，禁止默认选用。

### 2. diagram-design 字号下限

（1）图中任何文本 font-size ≥ 12，轴刻度、图例、标注也不例外。

（2）内容放不下时加大画布或精简内容，禁止缩小字号硬塞。

## 三、 设备调试规则（embedded-mcp-toolkit）

### 1. 重启后必须先重新登录

（1）重启动作包括：`serial_exec` / `ssh_shell_exec` / `adb_shell_exec` 中执行 `reboot`、`shutdown -r`、`reset`、`poweroff` 后重新上电，以及 `serial_enter_uboot` 隐式触发的重启。

（2）重启指令一旦发出，**下一条业务命令之前必须重新一键登录**：串口设备 `serial_shell_login`、SSH 设备 `ssh_shell_login`；登录成功返回可用 session 后才可继续，并以返回的 `session_id` 为准。任何试探、重试、`serial_write` 都不得先于登录。

（3）禁止重启后直接重试原命令：此时设备停在 `login:` 或 PSH 的 `locked>`，输入会被当作凭据吞掉，重试只会连续失败并污染会话。

（4）唯一例外：`serial_enter_uboot` 成功后停在 U-Boot 提示符（目标即 U-Boot 命令行）无需登录；在 U-Boot 内 `boot` / `bootm` 进入 Linux 后仍按（2）重新登录。ADB 无登录环节，`adb_exec reboot` 后先 `adb_device_list` 等设备重新枚举，再 `adb_shell_open` 重连。

（5）登录未就绪（LOCKED / UNLOCKING / 失败）或设备仍在启动时，先补 `key`、等启动到 `login:` 或 shell 提示符，再重新登录；禁止绕过登录继续发命令。

---
*本文档由 markdowncli 技能辅助生成*
