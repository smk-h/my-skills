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

---
*本文档由 markdowncli 技能辅助生成*
