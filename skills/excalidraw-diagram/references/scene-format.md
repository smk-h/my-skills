# Excalidraw 场景格式参考

面向「手工编写 `.excalidraw` 场景 JSON」的完整字段说明与避坑清单。字段清单对照官方类型定义
`@excalidraw/excalidraw@0.18.1`（`dist/types/excalidraw/element/types.d.ts`）。

## 一、文件整体结构

```json
{
  "type": "excalidraw",
  "version": 2,
  "source": "CodeBuddy",
  "elements": [ /* 见下 */ ],
  "appState": { "viewBackgroundColor": "#ffffff", "gridSize": null },
  "files": {}
}
```

- `elements` 数组顺序即**绘制层级**，靠后的元素画在上层（先矩形、后文字、再箭头）
- `files` 存放图片等二进制资源，无图片时为空对象

## 二、元素必填字段

### 通用基础字段（所有元素都必须有）

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | string | 场景内唯一 |
| `x` / `y` | number | 左上角坐标（画布坐标，y 向下增大） |
| `width` / `height` | number | 尺寸 |
| `angle` | number | 弧度，通常为 0 |
| `strokeColor` / `backgroundColor` | string | 线条色 / 填充色，`"transparent"` 表示不填充 |
| `fillStyle` | string | `solid` / `hachure` / `cross-hatch` / `zigzag` |
| `strokeWidth` | number | 1（细）/ 2（中）/ 4（粗） |
| `strokeStyle` | string | `solid` / `dashed` / `dotted` |
| `roundness` | object/null | 矩形用 `{ "type": 3 }`（自适应圆角），箭头用 `{ "type": 2 }` |
| `roughness` | number | 0 建筑师（工整）/ 1 艺术家（默认手绘）/ 2 漫画家 |
| `opacity` | number | 0-100 |
| `seed` | number | 随机整数，决定手绘抖动形状，需固定以保证渲染稳定 |
| `version` / `versionNonce` | number | 版本号 / 随机整数，随便给不重复的值 |
| `index` | string/null | 分数索引，手写场景给 `null`（由编辑器分配） |
| `isDeleted` | boolean | 通常 false |
| `groupIds` | array | 分组 id，无则 `[]` |
| `frameId` | string/null | 所属 frame，无则 null |
| `boundElements` | array/null | 绑定到此元素的元素列表 |
| `updated` | number | 秒级时间戳 |
| `link` | string/null | 超链接 |
| `locked` | boolean | 是否锁定 |

### 各类型附加字段

| 类型 | 附加必填字段 |
|---|---|
| `rectangle` / `diamond` / `ellipse` | 无 |
| `text` | `fontSize`, `fontFamily`, `text`, `textAlign`, `verticalAlign`, `containerId`, `originalText`, `autoResize`, `lineHeight` |
| `arrow` | `points`, `lastCommittedPoint`, `startBinding`, `endBinding`, `startArrowhead`, `endArrowhead`, `elbowed` |
| `line` | `points`, `lastCommittedPoint`, `startBinding`, `endBinding`, `startArrowhead`, `endArrowhead` |
| `frame` | `name` |
| `image` | `fileId`, `status`, `scale`, `naturalWidth`, `naturalHeight` |

## 三、文本与容器的绑定

框内文字不是节点的属性，而是**独立的 text 元素**，通过双向引用关联：

```json
{ "id": "r_a", "type": "rectangle", "...": "...", "boundElements": [{ "id": "t_a", "type": "text" }] },
{ "id": "t_a", "type": "text", "containerId": "r_a", "text": "节点 A", "textAlign": "center",
  "verticalAlign": "middle", "fontSize": 14, "fontFamily": 5, "originalText": "节点 A",
  "autoResize": true, "lineHeight": 1.25 }
```

- **两侧都要写**：容器的 `boundElements` 和文本的 `containerId`
- 文本换行直接用 `\n`（JSON 里是真正的换行转义）
- `originalText` 必须与 `text` 一致（编辑器据此判断是否需要重新排版）
- 文字坐标会被编辑器自动重算，首次手写给个近似居中值即可

## 四、箭头

```json
{
  "id": "a_1", "type": "arrow", "x": 180, "y": 35, "width": 140, "height": 0,
  "points": [[0, 0], [140, 0]],
  "startArrowhead": null, "endArrowhead": "arrow",
  "startBinding": null, "endBinding": null,
  "lastCommittedPoint": null, "elbowed": false, "strokeWidth": 2,
  "boundElements": [{ "id": "ta_1", "type": "text" }]
}
```

- `points` 是**相对 `x`/`y` 的偏移量**，首点必须是 `[0, 0]`；`width`/`height` 取偏移的绝对值
- `endArrowhead` 常用 `arrow`；`startArrowhead` 一般 `null`
- **吸附（binding）可选**：`startBinding`/`endBinding` 填 `{ "elementId": "r_a", "focus": 0, "gap": 4 }` 可让箭头跟随节点移动；手写场景允许留 `null`，代价是拖动节点时箭头不跟随，用户可在编辑器里把箭头端点拖到节点边缘重新吸附
- **箭头标签**是 `containerId` 指向箭头的 text 元素，会跟随箭头移动；渲染器自动居中并加白色遮罩（虚线不穿字）

**箭头绕行与几何四规则**（`validate-scene.mjs` 已内置检查）：

1. **线体不得穿框**：被节点挡住时用弧线或折线**绕行**，直线只许贴框边或走空白。
   豁免：箭头进组/出组穿过「包含起/终点节点的祖先容器」边框属合法语义。
   样条箭头（≥3 点 + type 2）的实际曲线与折线弦不同，校验按弦近似、命中降级为警告，
   最终以渲染产物视觉验收为准
2. **端点贴边框 + 入射禁平行**：首尾端点必须贴合某节点的边框（±6px 内），且首/末段
   **禁止与所贴边框平行**——水平段落在左/右边框、垂直段落在顶/底边框时，线会贴着框边
   滑行（过边上一点作平行线必与边线共线，几何上必然贴边），不美观。
   **斜向成角进出完全合法**，与边框有任何非零夹角即可，不要求 90° 正交（正交只是最常用
   特例）。选边优先选面向目标的那条边：目标在右下，从底边或右边斜出都可以；一源多目标
   用扇形斜连，从同一条边的不同位置出框。合法形态示例见
   `assets/template-arrow-patterns.excalidraw`
3. **弧线 vs 折线，按 `roundness` 二选一**：
   - 精确弧 = 多中间点 + `roundness: {type: 2}`。必须按真圆弧**密集采样 10-14 个中间点**
     （每段转角 ≤35°）——样条保证穿过全部采样点，但稀疏手摆点之间会内凹穿框；
     实测 12 点圆弧样条精确过点（±1px）。端点精确 `[0,0]` / `[dx,dy]`。
     需要贴着指定圆弧走线时用这种
   - 三点甩弧 = 起点边 → 外甩拐点 → 终点边，共 3 点 + `roundness: {type: 2}`。
     绕过单个障碍物时够用，是编辑器原生弧线箭头的画法；曲线会向拐角内侧偏移
     （实测 77° 内偏约 50px），拐点离被绕框留足余量，靠渲染视觉验收兜底
   - 折线 = 多拐点 + `roundness: null`。90° 直角绕行走廊，先算拐点坐标再写 `points`，
     保持 `x`/`y` 为起点绝对坐标
   - 反例：≥4 点（多拐点）转角 >50°（尤其 90°）配 type 2，样条在拐角拉出大幅弧线甩尾
     （实测 90° 甩 74px、45° 甩 57px），图上像线在「绕圈」；35°-50° 为风险区
4. **走廊优先**：跨层长箭头规划「出框边中点 → 空白走廊 → 入框边中点」路由，每拐一次只转 90°

## 五、字体与中文

- `fontFamily` 取值：`1` Virgil（**已废弃**）、`2` Helvetica（废弃）、`3` Cascadia、`5` Excalifont（**当前默认，用这个**）、`6` Nunito、`7` Lilita One、`8` Comic Shanns、`9` Liberation Sans
- 中文：Excalifont 等西文字体不含 CJK 字形，编辑器与浏览器会自动回退到系统 CJK 字体，显示正常，**不要**为了中文改用废弃字体
- 文本宽度估算（用于判断容器是否够宽）：CJK 字符 ≈ `1.0 × fontSize`，拉丁字符 ≈ `0.6 × fontSize`

## 六、配色（与 graphviz-diagram / plantuml-diagram 技能对齐）

| 颜色 | 用途 |
|---|---|
| `#7A93BE` | 节点主边框色 |
| `#DCE9FB` | 浅蓝——主参与者 / 容器 / 起止节点 |
| `#DDF3E4` | 浅绿——中间层（传输 / 桥接层） |
| `#FFF3D6` | 浅黄——外部设备 / 第三方 |
| `#F7F9FC` | 极浅蓝——普通处理节点 |
| `#FAFAFA` + `strokeStyle: dashed` + `#999999` | 虚线边界节点 |
| `#555555` | 默认箭头色 |
| `#2C5F8A` | 蓝色通路（如文件同步） |
| `#4E7A2C` | 绿色通路（如 MCP 通道） |
| `#8A4B2C` | 棕色通路（如部署闭环） |
| `#1F2933` | 文字色 |

## 七、布局建议

- **先规划列与行的坐标网格**，再逐个写元素；节点垂直间距建议 110-140，水平间距 150+
- **节点框彼此不得重叠**：部分交叠（压角/压边）= 坐标错位，`validate-scene.mjs` 按包围盒
  两两判定强制拦截；容器/分组框与组内节点的完全包含合法，相邻贴边（间隙 0）合法
- 标签最多 2 行；确需换行用 `\n`
- 容器（外框）要比内部元素四周多留 20-40 的边距
- 长文本节点按「CJK 1em + 拉丁 0.6em」估算宽度后，容器宽度再留 10% 余量
- 判断框（diamond）的文字只占中部内接区：宽度按文字估算宽 ×2 起步，高度约为宽度一半；
  流程图整体规范画法（起止/执行/判断、分支标签、回路、多框汇入）见
  `assets/template-flowchart.excalidraw`
- `roughness` 建议 1（默认手绘感）；追求工整用 0
- 节点填充风格：流程图/示意图用 `"hachure"`（内部斜线手绘风），需要平整色块（如高亮）时用 `"solid"`

## 八、环境与工具避坑

| 坑 | 说明 |
|---|---|
| **主包无法在 Node 直接 import** | `@excalidraw/excalidraw` 的 bundle 裸导入 CSS，Node 会报 `ERR_IMPORT_ATTRIBUTE_MISSING`。命令行渲染改用 `@excalidraw/utils` |
| **`@excalidraw/utils` 需要浏览器全局** | 缺一即报错：`devicePixelRatio`、`top`、`FontFace`、`document.fonts`、`window`/`document`/`navigator`/`location`。`scripts/render-excalidraw.mjs` 已内置全部垫片 |
| **navigator 是只读 getter（Node 24+）** | 必须用 `Object.defineProperty` 赋值，直接 `globalThis.navigator = ...` 会抛 `TypeError` |
| **jsdom 无 `FontFace`** | 需手写桩类 + `document.fonts` mock，否则报 `ReferenceError: FontFace is not defined` |
| **Kroki 在线 excalidraw 服务不可用** | 实测连最小场景都返回 HTTP 500（POST 与 GET 编码均失败），不要依赖它做渲染 |
| **版本是预发布版** | `@excalidraw/utils` 当前为 `0.1.3-test32`，务必锁死精确版本 |
| **内置的 Xiaolai 中文字体在无头环境取不到 `unicodeRange`** | 渲染时会打印 `Couldn't transform font-face to css for family "Xiaolai"` 的栈，属非致命错误：中文会回退系统字体，出图正常。`render-excalidraw.mjs` 已静音该噪声 |
| **产物命名冲突** | 同一文档资源目录常并存同名 `.dot`/`.excalidraw` 源文件；若都输出成 `<stem>.svg` 会互相覆盖，务必用 `<stem>.excalidraw.svg` |
| **箭头线体穿框** | 直线/折线斜穿无关节点内部会让语义混乱，必须用弧线或折线绕行走廊；豁免「进组/出组穿过祖先容器」。`validate-scene.mjs` 已做线段-矩形相交检查（样条按弦近似、命中降为警告，靠视觉验收兜底） |
| **弧线箭头不能手摆稀疏点** | `roundness:{type:2}` 样条只保证穿过采样点，稀疏手摆点之间会内凹、实际曲线可能穿框（弦以为绕过去了）。弧线必须按真圆弧密集采样 10-14 个中间点（每段转角 ≤35°，实测 12 点误差 ±1px） |
| **`lastCommittedPoint` 不是曲线控制点** | 它只是编辑器记录的最后提交点；想让箭头拐弯必须改 `points` 数组，往 `lastCommittedPoint` 塞坐标对渲染无任何效果（实测照画直线） |
| **首/末段与贴合边框平行（贴边滑行）** | 从底边框中点向右水平出框、或从右边框中点垂直出框，线段与框边共线贴边滑行 40-80px 才离开，不美观。**只禁平行，不要求正交**：斜向成角进出合法，90° 只是特例；选边选面向目标的那条边。`validate-scene.mjs` 仅拦截首/末段恰为水平/垂直且与所贴边共线的情形 |
| **多拐点箭头配 `roundness:{type:2}` 会样条甩尾** | ≥4 点且转角 >50°（尤其 90°）的箭头若用 type 2，渲染器在拐角拉出大幅弧线（实测 90° 甩 74px、45° 甩 57px）。直角折线一律 `roundness: null`；平滑弧线用「密集采样点 + type 2」或「三点甩弧 + type 2」（三点单拐角仅警告：曲线向拐角内侧偏移，拐点留足余量）。`validate-scene.mjs` 按转角分类拦截 |
| **编辑器保存的文件含 `isDeleted` 墓碑元素** | 在编辑器里删掉的元素仍以 `isDeleted: true` 留在 JSON 里，文件因此偏大；`validate-scene.mjs` 自动跳过墓碑，批量修改时不要把墓碑当活元素改，也不要手工复活 |
| **手写/脚本生成的箭头缺 `lastCommittedPoint`，binding 缺 `focus`/`gap`** | `lastCommittedPoint` 对渲染无效果（补 `null` 即可）；binding 缺 `focus`/`gap` 会让编辑器拖拽吸附行为异常（补 `0`/`4`）。`--fix` 已自动补齐这三类字段 |
| **节点框部分交叠（压角/压边）** | 手写坐标错位的常见结果，视觉上一眼穿帮。`validate-scene.mjs` 按包围盒两两判定：交叠深度 >2px 且互不包含即报错；容器/分组完全包含（组内节点准出 ≤2px）与相邻贴边合法。在编辑器里把演示框叠画到底图上就会触发 |
| **渲染器不重算端点吸附** | `startBinding`/`endBinding` 只对编辑器拖拽生效；导出 SVG 按存储的 `x`/`y`/`points` 原样绘制。端点坐标必须自己写准，写偏了渲染产物就偏——校验脚本会检查端点是否贴合边框 |
| **firefox 无头截图默认 profile 冲突** | 已有 firefox 实例时 `--headless --screenshot` 直接退出码 2。加 `--no-remote --profile /tmp/独立目录` 隔离即可 |
| **`pos` 属性不能绝对定位** | Excalidraw 没有 graphviz 的 `pos`；布局就是元素的 `x`/`y` 绝对坐标，直接写值即可 |
