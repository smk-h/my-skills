---
name: makefile-spec
description: Makefile 编写规范的代码检查、格式化与编写指导
---

# Skill: Makefile 编写规范

## 技能说明

本技能定义了一套统一的 GNU Makefile 编写规范，涵盖**格式排版**、**结构组织**、**变量命名**、**隐含规则**、**增量编译**及**注释规范**。当用户要求**检查 Makefile 规范性**、**编写 Makefile** 或**格式化现有 Makefile** 时，AI 必须严格遵循以下规则。

## 何时触发

当用户提出以下类型请求时自动激活：

**编写场景：**
- "帮我写一个 Makefile"
- "给这个项目添加构建脚本"
- "帮我生成编译规则"

**检查/格式化场景：**
- "帮我检查这段 Makefile 是否符合规范"
- "这个 Makefile 有什么问题"
- "帮我格式化这个 Makefile"

## 强制格式规范

### 1. 缩进规范

- 命令行必须以 **单个 Tab 字符**开头，**禁止使用空格替代**。
- 变量赋值、目标声明均顶格书写，不以 Tab 开头。

【**正确示例**】

```makefile
CC      = gcc
CFLAGS  = -Wall -Wextra -std=c99

build: main.o utils.o
	$(CC) $(CFLAGS) -o $@ $^
```

### 2. 空行规范

- 不同逻辑块（变量定义区、规则区）之间加一行空行。
- 文件末尾保留一行空行。

### 3. 行长与换行规范

- 单行不超过 120 字符。
- 过长命令使用 `\` 续行，续行以 Tab 缩进对齐。
- 变量定义过长时，使用 `\` 在等号后换行，续行以空格对齐。

【**示例**】

```makefile
$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) $(INCLUDES) $(LIBPATHS) \
		$(LINKLIBS) -o $@ $^
```

### 4. 空格规范

- 变量赋值 `=` / `:=` / `+=` / `?=` 前后各留一个空格。
- 目标与冒号之间不留空格，冒号与依赖之间留一个空格。
- 多个依赖之间用一个空格分隔。
- 逗号、分号之后留一个空格。

### 5. 对齐规范

- 同一区块的变量赋值，`=` 按最长变量名对齐。
- 不同类型变量（工具链/路径/选项）各自独立对齐。

【**示例**】

```makefile
CC       = gcc
CXX      = g++
AR       = ar

CFLAGS   = -Wall -Wextra -std=c99
CXXFLAGS = -Wall -Wextra -std=c++11
LDFLAGS  =

SRCDIRS  = src
SRCDIRS  += src/core
```

## 结构规范

### 1. 文件内顺序

Makefile 内容按以下顺序组织：

1. 文件头注释
2. 工具链变量（CC、AR 等）
3. Git 版本信息变量（GIT_REPO_TEST、GIT_SHA、GIT_SEQ、GIT_VER_INFO、GIT_SVR_PATH、GIT_CFLAGS）
4. 路径变量（SRCDIRS、INCDIRS、LIBDIRS、OBJDIR 等，通过 `+=` 追加）
5. 编译选项（CFLAGS，其中 `-I`/`-L`/`-l` 由函数自动生成）
6. 文件列表（SRCS、OBJS、DEPS）
7. VPATH 搜索路径
8. `.PHONY` 声明
9. 默认目标 `all`
10. 主构建目标 + 隐含规则
11. 辅助目标（clean、install、help）
12. `-include $(DEPS)`

### 2. 目标命名规范

- 目标名称使用全小写字母，单词以连字符 `-` 分隔（如 `dist-clean`）。
- 标准目标名：`all`、`clean`、`install`、`uninstall`、`test`、`help`。

### 3. 变量命名规范

- 变量名使用全大写字母，单词以下划线分隔。
- 常用标准变量名：

| 变量 | 含义 | 变量 | 含义 |
|------|------|------|------|
| `CC` | C 编译器 | `SRCDIRS` | 源文件目录列表 |
| `CXX` | C++ 编译器 | `INCDIRS` | 头文件目录列表 |
| `AR` | 打包工具 | `LIBDIRS` | 库文件目录列表 |
| `LIBS` | 库名列表（裸名，不含 `-l`）| `GIT_CFLAGS` | Git 版本编译选项 |
| `CFLAGS` | C 编译选项（不含 `-I`）| `INCLUDES` | 自动生成的 `-I` 参数 |
| `CPPFLAGS` | 预处理器选项（含 `-I`）| `LIBPATHS` | 自动生成的 `-L` 参数 |
| `LDFLAGS` | 链接选项（含 `-L`/`-l`）| `LINKLIBS` | 自动生成的 `-l` 参数 |
| `SRCS` | 源文件列表 | `DEPS` | 依赖文件列表 |
| `OBJS` | 目标文件列表 | `TARGET` | 最终产出物 |
| `OBJDIR` | 编译产物目录 | `DEPDIR` | 依赖文件目录 |
| `BINDIR` | 可执行文件目录 | `VPATH` | Make 搜索路径 |

### 4. 路径变量统一管理

- 源文件目录、头文件目录、库目录、库名统一定义为路径变量，集中放在路径定义区块。
- 使用 `+=` 逐行追加，每行一个目录/库名，便于增删和 diff 比较。
- **禁止**把所有目录挤在一行或直接在 CFLAGS 中写死路径。
- **禁止**在编译/链接选项区块中定义裸路径或裸库名（如 `LIBS = pthread m`），应统一放在路径定义区块。

【**正确示例**】

```makefile
SRCDIRS  = src
SRCDIRS  += src/core
SRCDIRS  += src/network

INCDIRS  = include
INCDIRS  += include/core

LIBDIRS  = /usr/local/lib
LIBDIRS  += thirdparty/sqlite3/lib

LIBS     = pthread m z
```

### 5. `-I` / `-L` / `-l` 参数自动生成

- **禁止**在 CFLAGS / LDFLAGS 中手写 `-I`、`-L`、`-l` 前缀。
- 路径变量和库名变量只存放裸路径/裸库名，前缀通过函数自动生成。

【**正确示例**】

```makefile
INCLUDES  = $(addprefix -I, $(INCDIRS))
LIBPATHS  = $(addprefix -L, $(LIBDIRS))
LINKLIBS  = $(addprefix -l, $(LIBS))

CFLAGS    = -Wall -Wextra
CPPFLAGS  = $(INCLUDES)
LDFLAGS   = $(LIBPATHS) $(LINKLIBS)
```

【**错误示例**】

```makefile
# 禁止：手写前缀，新增目录或库时需多处修改
CFLAGS  = -Wall -Iinclude -Iinclude/core -Iinclude/network
LDFLAGS = -L/usr/local/lib -Lthirdparty/lib -lpthread -lm
```

### 6. Git 版本信息

- 编写 Makefile 时**必须**包含 Git 版本信息获取逻辑，将版本信息通过编译宏注入程序。
- 使用 `GIT_REPO_TEST` 先检测是否在 Git 仓库内，避免非仓库环境下 `git` 命令报错。
- 版本信息变量必须在 `ifeq ($(GIT_REPO_TEST),true)` 条件内赋值。
- 通过 `GIT_CFLAGS` 变量收集所有 Git 相关的 `-D` 编译选项，最终追加到 `CFLAGS`。
- **禁止**直接在 `CFLAGS` 中手写 Git 相关的 `-D` 选项，必须通过 `GIT_CFLAGS` 统一管理。
- 未获取到版本信息时，必须提供 `"unknown"` 兜底值。

【**标准模板**】

```makefile
# ---- Git 版本信息 ----
GIT_REPO_TEST = $(shell if git rev-parse --is-inside-work-tree >/dev/null 2>&1; \
					then echo "true"; \
					else echo "false"; fi ;)

ifeq ($(GIT_REPO_TEST),true)
GIT_SHA = $(shell git rev-parse --short HEAD | awk 'NR==1')
GIT_SEQ = $(shell git rev-list HEAD | wc -l)
GIT_VER_INFO = $(GIT_SHA)-$(GIT_SEQ)
GIT_SVR_PATH = $(shell git remote -v | awk 'NR==1' | sed 's/[()]//g' | sed 's/\t/ /g' |cut -d " " -f2)
endif

ifneq ($(GIT_VER_INFO),)
  GIT_CFLAGS += -DGIT_VERSION=\"$(GIT_VER_INFO)\"
else
  GIT_CFLAGS += -DGIT_VERSION=\"unknown\"
endif

ifneq ($(GIT_SVR_PATH),)
  GIT_CFLAGS += -DGIT_PATH=\"$(GIT_SVR_PATH)\"
else
  GIT_CFLAGS += -DGIT_PATH=\"unknown\"
endif
```

【**变量说明**】

| 变量 | 含义 |
|------|------|
| `GIT_REPO_TEST` | 是否在 Git 仓库内（"true"/"false"） |
| `GIT_SHA` | 当前 commit 短 hash |
| `GIT_SEQ` | 当前 commit 数量 |
| `GIT_VER_INFO` | 组合版本信息，格式为 `SHA-SEQ` |
| `GIT_SVR_PATH` | 远程仓库地址 |
| `GIT_CFLAGS` | Git 版本相关的编译选项（`-D` 宏定义） |

## 隐含规则与增量编译

### 1. 必须使用隐含规则

- `.o` 文件**必须**使用隐含规则（`%.o: %.c`）统一生成，不得为每个源文件单独写规则。
- 隐含规则使 Make 自动比对时间戳，只重编译变化的文件。

【**正确示例**】

```makefile
$(OBJDIR)/%.o: %.c
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(CPPFLAGS) -MMD -MP -MF $(DEPDIR)/$(*F).d -c $< -o $@
```

【**错误示例**】

```makefile
# 禁止：逐个手写规则，无法自动处理依赖
main.o: main.c
	$(CC) $(CFLAGS) -c main.c -o main.o
utils.o: utils.c
	$(CC) $(CFLAGS) -c utils.c -o utils.o
```

### 2. 自动依赖生成（`-MMD` / `-MP`）

- 编译时必须附加 `-MMD -MP`，生成 `.d` 依赖文件。
- `.d` 文件通过 `-include` 引入（前缀 `-` 表示文件不存在时不报错）。
- 头文件变更时，Make 通过 `.d` 文件自动感知并重编译，实现增量编译。

```makefile
# -MMD : 生成依赖 .d 文件（不含系统头文件）
# -MP  : 为每个依赖生成空 target，防止头文件删除后报错
# -MF  : 指定 .d 文件输出路径
$(OBJDIR)/%.o: %.c
	@mkdir -p $(@D) $(DEPDIR)
	$(CC) $(CFLAGS) $(CPPFLAGS) -MMD -MP -MF $(DEPDIR)/$(*F).d -c $< -o $@

-include $(DEPS)
```

### 3. 多目录源文件与 VPATH

- 多目录源文件通过 `foreach` + `wildcard` 收集，必须设置 `VPATH` 使隐含规则能定位源文件。

```makefile
SRCS  = $(foreach dir, $(SRCDIRS), $(wildcard $(dir)/*.c))
OBJS  = $(patsubst %.c, $(OBJDIR)/%.o, $(notdir $(SRCS)))
DEPS  = $(patsubst %.c, $(DEPDIR)/%.d, $(notdir $(SRCS)))
VPATH = $(SRCDIRS)
```

## 编码安全规范

### 1. 伪目标声明

- 所有不对应真实文件的目标（clean、install、help 等）必须在 `.PHONY` 中声明。

```makefile
.PHONY: all clean install help
```

### 2. 目录存在性检查

- 编译产物输出到子目录时，规则中必须先 `@mkdir -p $(@D)`。
- 同时生成 `.d` 文件时，一并创建 DEPDIR。

### 3. 变量引用

- 使用 `$(VAR)` 形式引用变量，禁止使用 `${VAR}`。
- Shell 变量使用 `$$` 转义。

## 注释规范

### 1. 注释风格

- 使用 `#` 进行单行注释，`#` 与注释文字之间留一个空格。
- 注释放在被注释代码的上方，与代码保持相同缩进级别。
- 使用分段注释标注不同逻辑区块。

【**示例**】

```makefile
# ---- 工具链设置 ----
CC       = gcc

# ---- 源文件目录（+= 逐行追加，方便 diff）----
SRCDIRS  = src
SRCDIRS  += src/core

# ---- 编译选项 ----
CFLAGS   = -Wall -Wextra
```

### 2. 文件头注释

```makefile
# ============================================================
# 项目名称 : xxx 构建脚本
# 作者     : xxx
# 日期     : YYYY/MM/DD
# 说明     : 支持多目录源文件、增量编译
# 用法     : make [target]
#           make all     - 编译项目
#           make clean   - 清理产物
#           make help    - 显示帮助
# ============================================================
```

## 完整模板

```makefile
##============================================================================#
# Copyright © hk. 2022-2025. All rights reserved.
# File name: Makefile
# Author   : 苏木
# Date     : xxx-xx-xx
# Version  : 
# Description: 
##============================================================================#
# ---- 工具链 ----
CC       = gcc
AR       = ar

# ---- Git 版本信息 ----
GIT_REPO_TEST = $(shell if git rev-parse --is-inside-work-tree >/dev/null 2>&1; \
					then echo "true"; \
					else echo "false"; fi ;)

ifeq ($(GIT_REPO_TEST),true)
GIT_SHA = $(shell git rev-parse --short HEAD | awk 'NR==1')
GIT_SEQ = $(shell git rev-list HEAD | wc -l)
GIT_VER_INFO = $(GIT_SHA)-$(GIT_SEQ)
GIT_SVR_PATH = $(shell git remote -v | awk 'NR==1' | sed 's/[()]//g' | sed 's/\t/ /g' |cut -d " " -f2)
endif

ifneq ($(GIT_VER_INFO),)
  GIT_CFLAGS += -DGIT_VERSION=\"$(GIT_VER_INFO)\"
else
  GIT_CFLAGS += -DGIT_VERSION=\"unknown\"
endif

ifneq ($(GIT_SVR_PATH),)
  GIT_CFLAGS += -DGIT_PATH=\"$(GIT_SVR_PATH)\"
else
  GIT_CFLAGS += -DGIT_PATH=\"unknown\"
endif

# ---- 路径定义（+= 逐行追加，便于增删）----
SRCDIRS  = src
SRCDIRS  += src/core
SRCDIRS  += src/utils

INCDIRS  = include
INCDIRS  += include/core
INCDIRS  += thirdparty/libfoo/include

LIBDIRS  = thirdparty/libfoo/lib

LIBS     = pthread m

BINDIR   = bin
OBJDIR   = build/obj
DEPDIR   = build/dep

# ---- 编译/链接选项（-I/-L/-l 由函数自动生成）----
INCLUDES  = $(addprefix -I, $(INCDIRS))
LIBPATHS  = $(addprefix -L, $(LIBDIRS))
LINKLIBS  = $(addprefix -l, $(LIBS))

CFLAGS    = -Wall -Wextra -std=c99 $(GIT_CFLAGS)
CPPFLAGS  = $(INCLUDES)
LDFLAGS   = $(LIBPATHS) $(LINKLIBS)

# ---- 源文件与目标文件 ----
SRCS      = $(foreach dir, $(SRCDIRS), $(wildcard $(dir)/*.c))
OBJS      = $(patsubst %.c, $(OBJDIR)/%.o, $(notdir $(SRCS)))
DEPS      = $(patsubst %.c, $(DEPDIR)/%.d, $(notdir $(SRCS)))
TARGET    = $(BINDIR)/myapp

# ---- 搜索路径 ----
VPATH     = $(SRCDIRS)

# ---- 伪目标 ----
.PHONY: all clean help

# ---- 默认目标 ----
all: $(TARGET)

# ---- 链接 ----
$(TARGET): $(OBJS)
	@mkdir -p $(@D)
	$(CC) $(LDFLAGS) -o $@ $^

# ---- 隐含规则（附带 -MMD 实现增量编译）----
$(OBJDIR)/%.o: %.c
	@mkdir -p $(@D) $(DEPDIR)
	$(CC) $(CFLAGS) $(CPPFLAGS) -MMD -MP -MF $(DEPDIR)/$(*F).d -c $< -o $@

# ---- 引入自动生成的依赖文件 ----
-include $(DEPS)

# ---- 清理 ----
clean:
	@rm -rf $(OBJDIR) $(DEPDIR) $(TARGET)

# ---- 帮助 ----
help:
	@echo "可用目标:"
	@echo "  make all   - 编译项目（默认）"
	@echo "  make clean - 清理编译产物"
	@echo "  make help  - 显示本帮助"
```

## 行为规范

### 代码检查

当用户要求检查 Makefile 规范时：

1. 逐一对照本规范进行检查。
2. 指出不符合规范的具体位置、原因及修改建议。
3. 特别关注：Tab 缩进、`.PHONY` 声明、路径变量管理、`-I`/`-L`/`-l` 自动生成、隐含规则、`-MMD -MP`、Git 版本信息。

### 代码编写

当用户要求编写 Makefile 时：

1. 应用本规范的所有格式要求。
2. 添加文件头注释，使用分段注释划分逻辑区块。
3. 路径变量统一用 `+=` 管理，`-I`/`-L`/`-l` 通过函数自动生成。
4. `.o` 编译使用隐含规则 `%.o: %.c`，附带 `-MMD -MP` 实现增量编译。
5. 多目录须设置 `VPATH`。
6. `.PHONY` 声明完整，提供 `all`、`clean`、`help` 三个目标。
7. 必须包含 Git 版本信息获取逻辑，通过 `GIT_CFLAGS` 注入编译宏。
