---
name: graphviz-diagram
description: 用 Graphviz dot 绘制架构图、流程图、拓扑图、依赖图、简单时序交互图并转 SVG 嵌入 Markdown 文档。固化在线渲染的中文/字体/布局限制与避坑规则（Noto Sans CJK SC 中文字体、标签最多两行、禁空装饰框、cluster 带语义、生命线实线贯穿、阶段横向虚线分隔、反向平边翻转等）。自带 render-dot.mjs 脚本把 .dot 渲染成 SVG。用于"画架构图"、"画流程图"、"graphviz"、"dot"、"dot 转 svg"、"拓扑图"、"依赖图"、"画图"等场景。
---

# Skill: Graphviz dot 画图与 SVG 渲染

用 Graphviz dot 绘制技术文档配图（架构图、流程图、拓扑图、依赖图等），用自带脚本 `scripts/render-dot.mjs`（调用 QuickChart 在线 Graphviz 服务）把 `.dot` 渲染成 SVG，嵌入 Markdown 文档。图的类型与语法按需自由编写，本 skill 只固化**统一皮肤**和**实测踩坑的避坑规则**，不提供图类型模板。

**时序图路由**：两三个角色的简单消息往返可以用 dot 画（必须按下文"时序/交互图构造规则"）；复杂时序图（多角色、嵌套分组、alt/loop）dot 没有对应语义，用 plantuml-diagram skill。

## 何时触发

当用户提出以下请求时激活：

- "帮我画一张架构图/流程图/拓扑图/依赖图"
- "把这个 ASCII 图转成 dot/svg"
- "dot 转 svg"、"graphviz 渲染"
- "文档里加几张图"、"给文档配图"
- 直接提到 "graphviz"、"dot"、"digraph"

## 工作流程

### 第 1 步：确定目录约定

遵循"一篇文档 + 同级同名资源目录"的约定（与 markdowncli 配合）。**md 文档在哪里，同名资源目录就在同级**，不限定是 `docs/`，只要 md 与资源目录是同级兄弟关系即可：

```
<任意目录>/某主题.md               ← 文档正文（引用 ./某主题/img/xxx.svg）
<任意目录>/某主题/                 ← 同名资源目录（与 md 同级、同名去掉 .md）
  ├── layered-architecture.dot    ← 源文件（必须保留, 便于改图重渲染）
  ├── data-flow.dot
  └── img/                        ← SVG 输出目录(脚本默认写这里)
      ├── layered-architecture.svg
      └── data-flow.svg
```

- md 文档与资源目录是**同级兄弟**，目录名 = md 文件名去掉 `.md`
- `.dot` 与 `img/*.svg` **同名**，便于对照
- 文档中用相对路径引用：`![标题](./某主题/img/xxx.svg)`（`./` 指向同级同名目录）

### 第 2 步：写 .dot 源文件

以**统一皮肤**开头，图的具体写法自由发挥，但必须遵守下述**语法要点**；画时序/交互图还必须遵守专门的**构造规则**。每个 `.dot` 必须是一个完整的 `digraph`（或 `graph`）定义。

三个语法要点（写图时遵守）：

- **中文必须显式指定字体 `Noto Sans CJK SC`**：顶层裸 `fontname` + `graph`/`node`/`edge` 三处属性块都要写。在线服务器默认字体 Times 无中文字形，漏写就渲染成豆腐块。勿改成"微软雅黑"等本机字体（服务器没有）
- **标签最多 2 行**：凡渲染成文字的都是 `label`——节点方框内的文字、边（箭头）旁的文字、图标题、cluster 分组标题，本约束全部适用。`label` 无自动换行，换行只能用官方转义符 `\n`（居中）/`\l`（左对齐）/`\r`（右对齐）。横向有扩展空间时（同行节点少、整行宽度充裕）标签**保持 1 行展开**；确需分段最多 2 行。禁止为省宽度把一个标签拆成 3 行以上的窄高条，破坏整图协调
- **分组用 `subgraph cluster_xxx`**：cluster 必须带 `label` 承载语义；禁止画只装饰不表意的空虚线框

### 第 3 步：渲染成 SVG

```bash
# 渲染某 md 文档对应的同名资源目录下的所有 dot
node scripts/render-dot.mjs 某主题/*.dot

# 指定输出目录（默认: 各 dot 同级的 img/，即 <资源目录>/img/）
node scripts/render-dot.mjs 某主题/foo.dot --out-dir ./out-img
```

脚本位置：本 skill 的 `scripts/render-dot.mjs`。它是零依赖的 ESM 脚本（仅用 Node 内置模块），复制到任意项目即可用。输出每个 SVG 时打印 `✓ xxx.dot → img/xxx.svg (NNN bytes)`，语法错误打印 `✗ ... Graph Error: syntax error in line N`。

### 第 4 步：嵌入文档

把渲染出的 SVG 用相对路径嵌入 Markdown：

```markdown
![三层分层架构](./某主题/img/layered-architecture.svg)
```

## 统一皮肤（强制套用，保证视觉一致）

每张图开头都加这套属性（白底 + Noto Sans CJK SC + 蓝色系，与 plantuml-diagram skill 配色对齐）：

```dot
digraph G {
  fontname="Noto Sans CJK SC";   // 顶层默认字体, cluster 标签继承它
  graph [fontname="Noto Sans CJK SC", label="<一句话标题>", labelloc="t",
         fontsize=16, fontcolor="#1F2933", bgcolor="white"];
  node [fontname="Noto Sans CJK SC", shape=box, style="rounded,filled",
        fillcolor="#F7F9FC", color="#7A93BE", fontcolor="#1F2933", fontsize=12];
  edge [fontname="Noto Sans CJK SC", color="#5A5A5A", fontcolor="#333333", fontsize=11];

  // ...节点与边
}
```

通用配色语义：

| 颜色 | 用途 |
|---|---|
| `white` | 背景底色（bgcolor） |
| `#7A93BE` | 边框主色（节点/cluster 边框） |
| `#DCE9FB` | 浅蓝底——主参与者/容器/起止节点/参与者列头 |
| `#DDF3E4` | 浅绿底——中间层（传输/桥接层） |
| `#FFF3D6` | 浅黄底——第三方库/外部设备；兼作判断菱形底色 |
| `#F7F9FC` | 极浅蓝底——普通处理节点（node 默认） |
| `#E0B400` / `#5C4A00` | 判断菱形的边框/文字色 |
| `#B0B0B0` | 阶段分隔虚线（时序/交互图） |
| `#5A5A5A` / `#333333` | 箭头线/边标签文字色 |

## 时序/交互图构造规则（dot 无原生时序语义，自由发挥必翻车）

点状断续竖线、无阶段分隔，就是 AI 不加约束自由画 dot 时序图时的典型错误样式（用户评审否决过的真实案例）。两三个角色的简单消息往返按以下规则构造，全部经在线渲染实测验证：

- **参与者各占一列**：列头是参与者节点（box，浅蓝 `#DCE9FB`），从上往下每条消息占一行
- **每行放两个隐形锚点**：锚点声明为 `[shape=point, style=invis, width=0.01]`，并用 `{rank=same; 左锚点; 右锚点;}` 约定同行；行内左右锚点之间的横向边就是消息
- **生命线必须实线贯穿上下**：每列从列头到最后一个锚点，用纵向 `style=solid, arrowhead=none` 的边首尾相接串成链，渲染成一条贯穿上下的连续竖线。**禁止 `style=dotted`**——渲染出来是"一个点一个点"的断续线
- **阶段之间必须横向虚线分隔**：在阶段边界处单独占一行，放两个隐形锚点，锚点间连 `style=dashed, color="#B0B0B0", arrowhead=none` 的横向边，`label` 写阶段名；多阶段图每个边界都要有，明确哪一部分属于哪个阶段
- **响应消息必须 `dir=back`**：消息边一律按"左列 → 右列"方向声明；右往左的响应用官方方向属性 `dir=back`（箭头画在起点端）。**禁止写"右 → 左"的反向平边（flat edge）**——dot 会为保持平边从左到右而翻转该 rank 内的节点顺序，导致两条生命线交叉打结、列位置漂移
- 列间距不够、消息 label 放不下时，加 `graph [nodesep=1.2]` 左右撑开

## render-dot.mjs 脚本说明

- **位置**：`scripts/render-dot.mjs`（零依赖 ESM，仅用 Node 内置 `fs/path/https`）
- **原理**：读 `.dot` 源文件，POST 到 `https://quickchart.io/graphviz`（body 为 `{graph, format:"svg", layout:"dot"}`），服务端用 graphviz 2.40.1 渲染并返回 SVG
- **错误反馈**：dot 语法错误时服务返回 HTTP 400 + `Graph Error: syntax error in line N` 文本，脚本原样打印出行号
- **输出**：默认写到每个 dot 同级的 `img/`；`--out-dir` 统一覆盖
- **用法**：

  ```bash
  node scripts/render-dot.mjs <dot> [dot...] [--out-dir <dir>]
  ```

复制到目标项目后即可用，无需 `npm install`。

## 注意事项

- **保留 .dot 源文件**：SVG 是产物，改图要改源再重渲染。没有 `.dot` 源的手工 SVG/贴图无法维护，是文档配图最不合理的形式；禁止手改 SVG。
- **改图后重渲染**：`node scripts/render-dot.mjs 某主题/xxx.dot` 覆盖 `img/xxx.svg` 即可。
- **标签行数约束（用户评审反馈）**：横向有扩展空间时标签 1 行展开；确需换行最多 2 行（`\n`）；禁止换行成 3-4 行的窄条，节点宽高比例要与整图协调。
- **菱形节点标签要短**（中文 ≤6 字）：文字会等比放大菱形，长了菱形巨大；长问题拆成"菱形短问句 + 旁边 box 说明"。
- **禁止空装饰虚线框**：只画边框不承载语义的虚线框是干扰项。边界/分组要么用带 label 的 cluster，要么让框本身是有内容的节点；箭头一律从真实节点出发。
- **在线服务局限**：无法本地校验语法，错误只能通过 HTTP 400 或 "Graph Error" 文本反馈。复杂图建议先用最小用例验证语法再加内容。
- **本地 vs 在线**：本机装了 graphviz 也可 `dot -Tsvg xxx.dot -o img/xxx.svg`，但与在线服务（graphviz 2.40.1）的新版本地布局可能有细微差异，同一项目固定用一种方式。
- **回归验证**：改了脚本逻辑后，重渲染既有 dot 并 `diff` 旧 SVG，确认字节一致。
