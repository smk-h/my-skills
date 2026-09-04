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
- **箭头标签**是 `containerId` 指向箭头的 text 元素，会跟随箭头移动

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
- 标签最多 2 行；确需换行用 `\n`
- 容器（外框）要比内部元素四周多留 20-40 的边距
- 长文本节点按「CJK 1em + 拉丁 0.6em」估算宽度后，容器宽度再留 10% 余量
- `roughness` 建议 1（默认手绘感）；追求工整用 0

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
| **`pos` 属性不能绝对定位** | Excalidraw 没有 graphviz 的 `pos`；布局就是元素的 `x`/`y` 绝对坐标，直接写值即可 |
