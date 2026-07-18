---
name: git-commit-spec
description: Git 提交规范的检查、格式化与编写指导，基于 Conventional Commits 规范
---

# Skill: Git 提交规范

## 技能说明

本技能定义了一套统一的 Git 提交信息规范，基于 [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) 并结合语义化版本（SemVer），涵盖**提交信息格式**、**类型定义**、**范围与破坏性变更**、**正文与页脚**及**中文提交规范**。当用户要求**检查提交信息规范性**、**格式化提交信息**或**编写符合规范的提交信息**时，AI 必须严格遵循以下规则。

## 何时触发

当用户提出以下类型请求时自动激活：

**提交信息检查场景：**
- "帮我检查这个 commit message 是否符合规范"
- "这个提交信息有什么问题"
- "帮我审查提交记录"

**提交信息编写场景：**
- "帮我写一个 commit message"
- "帮我生成提交信息"
- "帮我提交代码"
- "git commit" 相关的任何场景

**提交信息格式化场景：**
- "帮我格式化这个 commit message"
- "按规范整理这个提交信息"

<GATE>
执行 `git commit` / `git push` 之前，必须将完整的提交信息展示给用户并等待明确确认。无论提交多简单，一律先展示再执行。
</GATE>

## 禁止事项

1. **【最高优先级】禁止未经用户确认直接执行 `git commit` 或 `git push`**。生成提交信息后必须先展示给用户，经用户明确确认（「确认 / ok / 同意」）后方可执行。其余禁止事项均次于本条。
2. **禁止使用无意义的提交信息**，如 `update`、`fix bug`、`wip`、`misc` 等。
3. **禁止在描述中使用过去时**，应使用祈使句（如 "add" 而非 "added" 或 "adds"）。
4. **禁止在描述末尾加句号**。
5. **禁止在类型或范围中使用中文**。
6. **禁止遗漏破坏性变更声明**，凡涉及 API 不兼容变更的提交必须声明 `BREAKING CHANGE` 或使用 `!` 标记。
7. **禁止在一个提交中混合多个不相关的变更**，应拆分为多个独立提交。
8. **禁止 `BREAKING CHANGE` 使用小写**，必须全大写。
9. **禁止冗余或无意义的正文**。正文应补充 description 无法承载的关键信息（变更原因、设计决策、多个变更点、迁移指引等），**禁止罗列能从 diff 直接看出的内容**（如逐文件复述改动），也**禁止简单复述描述**。当正文过长（超过 6 个列表项或 10 行）时，应精简或考虑拆分提交。

## 行为规范

### 提交信息检查

当用户要求检查提交信息规范性时：

1. 逐一对照本规范进行检查。
2. 重点检查：类型是否合法、描述是否超长、是否使用祈使句、破坏性变更是否声明、中文格式是否正确。
3. 指出不符合规范的具体位置和原因。
4. 提供修改后的完整提交信息。

### 提交信息编写

当用户要求编写提交信息时：

1. 分析本次代码变更的内容和范围。
2. 选择最合适的 type 和 scope，按 `<type>[(scope)][!]: <description>` 格式撰写首行（type/scope 定义见下方「提交信息格式」）。确保描述不超过 72 字符，使用祈使句，破坏性变更必须声明。
3. 如有需要，补充正文和页脚。**当一次提交包含多个变更要点时，正文优先使用列表逐条展开**，每条聚焦一个变更点；背景说明等纯叙述内容可用段落。
4. **【硬节点】将完整的提交信息展示给用户，等待明确确认：**
   - 用户确认（「确认 / ok / 同意」）→ 执行 `git commit`
   - 用户要求修改 → 调整后重新回到第 4 步展示
   - **绝不在第 4 步通过之前执行 `git commit` 或 `git push`**

### 提交信息格式化

当用户要求格式化现有提交信息时：

1. 保留原意，调整格式使其符合规范。
2. 补充缺失的 type 或 scope。
3. 修正时态、去除句号。
4. 超长描述进行精简或移入正文部分。

---

## 提交信息格式

### 1. 基本结构

提交信息必须遵循以下结构：

```
<type>[(scope)][!]: <description>

[optional body]

[optional footer(s)]
```

完整示例：

```
feat(api)!: add user authentication endpoint

Add JWT-based authentication endpoint that validates
user credentials and returns access tokens.

BREAKING CHANGE: old /auth endpoint removed, use /auth/token instead
Refs: #123
```

### 2. 各部分详解

#### type（类型）- 必填

类型必须是以下预定义名词之一：

| 类型 | 含义 | 语义化版本影响 |
|------|------|----------------|
| `feat` | 新功能 | MINOR |
| `fix` | 修复 Bug | PATCH |
| `docs` | 仅文档变更 | 无 |
| `style` | 不影响代码含义的变更（空格、格式化、缺少分号等） | 无 |
| `refactor` | 既不修复 Bug 也不添加功能的代码变更 | 无 |
| `perf` | 提升性能的代码变更 | 无 |
| `test` | 添加或修正测试 | 无 |
| `build` | 影响构建系统或外部依赖的变更（如 webpack、npm） | 无 |
| `ci` | 对 CI 配置文件和脚本的变更 | 无 |
| `chore` | 其他不修改 src 或测试文件的变更 | 无 |
| `revert` | 回退之前的提交 | 无 |

#### scope（范围）- 可选

- 用括号包裹，紧跟类型之后、`!` 或 `:` 之前。
- 描述受影响代码库的模块或区域，如 `feat(parser):`、`fix(auth):`。
- 使用小写字母，单词以连字符 `-` 分隔。

#### `!`（破坏性变更标记）- 可选

- 放在类型/范围之后、冒号之前，表示该提交包含破坏性 API 变更。
- 与语义化版本 `MAJOR` 对应。
- 如果使用 `!`，页脚中的 `BREAKING CHANGE:` 可以省略，提交描述即可说明破坏性内容。
- 如果不使用 `!`，破坏性变更必须在页脚中通过 `BREAKING CHANGE:` 声明。

【**示例**】

```
feat(api)!: send an email to the customer when a product is shipped
```

等价于：

```
feat(api): send an email to the customer when a product is shipped

BREAKING CHANGE: existing API response format has changed
```

#### description（描述）- 必填

- 紧跟冒号和一个空格之后。
- 使用祈使句（如 "add feature" 而非 "added feature" 或 "adds feature"）。
- 简明扼要，不超过 **72 个字符**。
- 不以句号结尾。
- 首字母不大写（除非专有名词或中英文混合时英文首字母大写）。

【**正确示例**】

```
feat(api): add user authentication endpoint
fix(parser): handle whitespace in array parsing
docs: update README installation section
```

【**错误示例**】

```
feat(api): Add user authentication endpoint.   # 大写开头 + 句号
fix(parser): fixed whitespace bug              # 过去时
feat: this is a very very very very very very very very very very long description that exceeds 72 chars  # 超长
```

### 3. 正文（body）- 可选

#### 3.1 何时需要正文

正文不是必填项。**优先判断是否需要正文**——能用一句描述讲清、或改动可从 diff 直接看出的提交，应省略正文。仅当满足以下任一条件时才补充正文：

- **变更原因**需要交代背景或动机（为什么这么改）。
- 存在**多个独立的变更点**，一句话概括不全。
- 涉及**设计决策、权衡取舍**，需说明为什么选 A 不选 B。
- 含**破坏性变更迁移指引**、**重要约束**或**注意事项**。

#### 3.2 格式要求

- 与描述之间空一行。
- 用于提供比描述更详细的上下文信息。
- **当变更包含多个要点时，推荐使用列表逐条展开**，避免堆砌长段落，提升可读性。
- 列表项使用 `-` 开头，每条聚焦一个变更点，措辞简洁（祈使句或动宾短语）。
- 纯叙述性内容（如背景说明、设计取舍）仍可使用段落，段落之间空一行。
- 每行不超过 **100 字符**。
- **控制篇幅**：列表项一般不超过 6 个、正文总行数建议不超过 10 行；超出时考虑精简或拆分提交。

#### 3.3 正文形式示例

【**段落形式示例**】

```
fix: prevent racing of requests

Introduce a request id and a reference to latest request. Dismiss
incoming responses other than from latest request.

Remove timeouts which were used to mitigate the racing issue but are
obsolete now.
```

【**列表形式示例（推荐，多要点时使用）**】

```
feat(auth): 重构用户认证模块

- 新增 JWT token 签发与校验逻辑
- 移除旧的 session 认证方式
- 支持多端登录与 token 刷新机制
- 补充单元测试覆盖核心认证流程
```

【**段落 + 列表混排示例**】

```
refactor(api): 优化订单查询接口性能

针对订单列表加载缓慢的问题进行性能优化，主要改动如下：

- 为 order 表的 user_id 字段新增联合索引
- 将 N+1 查询重构为批量预加载
- 引入 Redis 缓存热点数据，TTL 设为 5 分钟

压测数据显示 P99 响应时间从 1.2s 降至 180ms。
```

### 4. 页脚（footer）- 可选

- 与正文之间空一行。
- 每个页脚格式为 `<token>: <value>` 或 `<token> #<value>`。
- token 中的空格用 `-` 替代（如 `Reviewed-by`）。
- `BREAKING CHANGE` 是唯一允许包含空格的 token（也可写为 `BREAKING-CHANGE`，两者等价）。
- `BREAKING CHANGE` 必须使用大写字母。

**常用页脚 token：**

| Token | 用途 |
|-------|------|
| `BREAKING CHANGE` | 描述破坏性变更 |
| `Refs` | 关联的 Issue 或 PR 编号 |
| `Reviewed-by` | 审查者 |
| `Co-authored-by` | 共同作者 |
| `Signed-off-by` | 签署者 |

【**示例**】

```
BREAKING CHANGE: environment variables now take precedence over config files
Refs: #123
Reviewed-by: Zhang San
Co-authored-by: Li Si <lisi@example.com>
```

## 破坏性变更规范

### 1. 两种声明方式

破坏性变更可以通过以下两种方式声明，效果等同：

**方式一：在类型/范围前缀中使用 `!`**

```
feat!: drop support for Node 6

feat(api)!: send an email to the customer when a product is shipped
```

**方式二：在页脚中使用 `BREAKING CHANGE:`**

```
feat: allow provided config object to extend other configs

BREAKING CHANGE: `extends` key in config file is now used for extending
other config files
```

### 2. 同时使用 `!` 和 BREAKING CHANGE 页脚

允许同时使用，此时描述和页脚应提供互补信息：

```
feat!: drop support for Node 6

BREAKING CHANGE: use JavaScript features not available in Node 6.
```

### 3. 破坏性变更描述要求

- 必须明确说明**什么发生了变更**、**为什么变更**以及**迁移指引**。
- 不允许仅写 `BREAKING CHANGE:` 而不给出具体描述。

【**正确示例**】

```
BREAKING CHANGE: the old `/auth` endpoint has been removed.
Use `/auth/token` instead. Pass the JWT token in the Authorization header.
```

【**错误示例**】

```
BREAKING CHANGE: API changed    # 描述过于简略，缺乏迁移指引
```

## 中文提交规范

### 1. 中文描述规则

- 描述使用中文时，语言简洁、准确。
- 类型（type）和范围（scope）保持英文，不改中文。
- 页脚中的 token 保持英文原样。

【**中文描述示例**】

```
feat(api): 新增用户认证接口
fix(parser): 修复解析数组时空格导致的异常
docs: 更新 README 安装说明
refactor(core): 重构日志模块，解耦输出格式
```

### 2. 中英文混排规则

- 中英文之间加一个空格。
- 中文与数字之间加一个空格。
- 中文标点与英文之间不加空格。

【**正确示例**】

```
feat(web): 首页加载速度提升 50%
fix(api): 修复 JWT token 在 Node 18 下的兼容问题
```

【**错误示例**】

```
feat(web): 首页加载速度提升50%          # 数字与中文之间无空格
fix(api): 修复JWTtoken在Node18下的兼容问题 # 英文与中文之间无空格
```

## 提交信息模板

### 最小化提交

```
<type>: <description>
```

### 带范围

```
<type>(<scope>): <description>
```

### 功能提交

```
feat(<scope>): <description>
```

### 修复提交

```
fix(<scope>): <description>
```

### 破坏性变更提交

```
<type>(<scope>)!: <description>

BREAKING CHANGE: <详细描述及迁移指引>
```

### 完整模板

```
<type>[(<scope>)][!]: <description>

[详细说明变更原因、实现方式及注意事项]

[BREAKING CHANGE: <破坏性变更描述及迁移指引>]
[Refs: <关联编号>]
[Reviewed-by: <审查者>]
```

## 常见场景参考

### 1. 新增功能

```
feat(dashboard): add real-time notification panel
```

```
feat(auth): implement OAuth 2.0 login flow

Add Google and GitHub OAuth providers. Users can now
log in via third-party accounts.

Refs: #42
```

### 2. 修复 Bug

```
fix(parser): handle empty array in JSON parsing
```

```
fix(parser): 修复 JSON 解析数组时的多个边界问题

- 处理空数组解析为 null 的错误
- 修复尾随逗号导致的解析中断
- 统一异常处理路径，避免静默失败
- 补充对应单元测试用例
```

### 3. 破坏性变更

```
feat(api)!: redesign user profile response structure

BREAKING CHANGE: user profile endpoint now returns a nested
object. Migrate by accessing `profile.data` instead of flat fields.

Refs: #89
```

### 4. 文档变更

```
docs: add API rate limiting section to README
```
