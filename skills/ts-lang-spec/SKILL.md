---
name: ts-lang-spec
description: TypeScript 语言编程规范的代码检查与格式化指导
---

# Skill: TypeScript 语言编程规范

## 技能说明

本技能定义了一套统一的 TypeScript 编程规范，涵盖**排版规则**、**命名规范**、**类型规范**、**注释规范**、**导入导出规范**及**类与函数规范**。当用户要求**检查代码规范性**、**格式化 TypeScript 代码**或**编写符合规范的 TypeScript 代码**时，AI 必须严格遵循以下规则。

## 何时触发

当用户提出以下类型请求时自动激活：

**代码检查场景：**
- "帮我检查这段 TypeScript 代码是否符合规范"
- "帮我检查这段 ts 代码是否符合规范"
- "这段代码有什么不规范的地方"
- "代码审查"

**代码格式化场景：**
- "帮我格式化这段 TypeScript 代码"
- "帮我格式化这段 ts 代码"
- "按照规范整理这段代码"

**编写新代码场景：**
- "帮我写一个 TypeScript 函数"
- "用 TypeScript 实现 xxx 功能"
- "用 ts 帮我写一个 xxx"
- "用 ts 实现 xxx"
- 任何涉及 TypeScript 代码编写的场景
- 用 TypeScript 帮我写一个 xxx 程序

## 强制格式规范

### 1. 缩进规范

- 缩进使用 **2 个空格键**，禁止使用 Tab。
- 程序块的分界符（大括号 `{` 和 `}`）中，左花括号 `{` 紧跟语句块，与前面的关键字或参数间隔一个空格，右花括号 `}` 独占一行。
- `if`、`for`、`do`、`while` 的执行语句部分无论多少行都要加括号 `{}`，且左花括号与关键字在同一行，之间间隔一个空格。

【**正确示例**】

```typescript
for (...) {
  ... // program code
}

if (...) {
  ... // program code
} else {
  ... // program code
}

while (...) {
  ...
}

function exampleFun(): void {
  ... // program code
}

class ExampleClass {
  constructor() {
    ...
  }
}
```

### 2. 空行规范

- 相对独立的程序块之间、变量说明之后必须加空行。
- 在每个函数定义、类定义结束之后都要加 1 个空行。
- 导入语句与后续代码之间加 1 个空行。
- 类的各个方法之间加 1 个空行。

### 3. 行长与换行规范

- 不允许把多个短语句写在一行中，一行只写一条语句。
- 一行程序以小于 **100 字符**为宜，不要超过 **120 字符**。
- 对于较长的语句（> 100 字符）要分成多行书写。长表达式在低优先级操作符处划分新行，操作符放在新行之首，新行进行适当缩进。
- 链式调用过长时，每个 `.method()` 单独一行。

【**正确示例**】

```typescript
const result = someVeryLongVariableName
  + anotherVeryLongVariableName
  - yetAnotherVariable;

someObject
  .method1()
  .method2()
  .method3();
```

### 4. 空格规范

- 逗号、分号只在后面加空格。
- 双目操作符前后加空格。
- 单目操作符（`!`、`~`、`++`、`--`）前后不加空格。
- `?.`、`.`、`[]` 前后不加空格。
- `if`、`for`、`while`、`switch` 等关键字与后面括号间加空格；函数名之后不留空格，紧跟左括号 `(`。
- 类型注解的冒号 `:` 前不加空格，后加空格。例如：`const name: string`。
- 对象字面量的冒号 `:` 前不加空格，后加空格。

【**正确示例**】

```typescript
const count: number = 0;
const obj = { key: value, other: 'text' };
if (count > 0) {
  console.log(count);
}
```

### 5. 分号规范

- 每条语句末尾必须加分号。
- 类的方法、函数声明不需要在末尾加分号。

## 命名规范

### 1. 基本原则

- 标识符命名要清晰、明了，有明确含义。
- 禁止使用单个字母作为变量名（`i`、`j`、`k` 作为局部循环变量除外）。
- 避免使用无意义的缩写，优先使用完整单词。

### 2. 具体命名规则

| 类型 | 命名风格 | 示例 |
|------|----------|------|
| 类、接口、类型别名 | PascalCase | `UserService`、`ApiResponse` |
| 函数、变量、参数 | camelCase | `getUserInfo`、`userCount` |
| 常量（不可重新赋值） | 全大写下划线 | `MAX_RETRY_COUNT`、`API_BASE_URL` |
| 枚举类型 | PascalCase | `UserStatus` |
| 枚举成员 | PascalCase | `Active`、`Inactive` |
| 私有类成员 | 下划线前缀 + camelCase | `_privateField` |
| 泛型参数 | 单个大写字母或 PascalCase | `T`、`K`、`V`、`ItemType` |

### 3. 布尔变量命名

- 布尔变量名应使用 `is`、`has`、`can`、`should` 等前缀。
- 示例：`isActive`、`hasPermission`、`canEdit`、`shouldRefresh`

### 4. 接口与类型别名

- 优先使用 `interface` 定义对象类型，需要联合类型或工具类型时使用 `type`。
- 接口名不使用 `I` 前缀。
- 类型别名名不使用 `T` 后缀。

## 类型规范

### 1. 显式类型声明

- 函数参数必须显式声明类型。
- 函数返回值尽量显式声明类型（简单推断除外）。
- 类属性必须显式声明类型。

【**正确示例**】

```typescript
function add(a: number, b: number): number {
  return a + b;
}

class User {
  public name: string;
  private age: number;

  constructor(name: string, age: number) {
    this.name = name;
    this.age = age;
  }
}
```

### 2. 禁止使用 any

- 禁止使用 `any` 类型。如果类型不确定，使用 `unknown` 并在使用前进行类型检查。
- 对于第三方库没有类型定义的情况，优先安装 `@types/xxx`，其次使用 `.d.ts` 声明文件。

### 3. 可选属性与只读属性

- 可选属性使用 `?` 标记。
- 只读属性使用 `readonly` 修饰符。
- 优先使用 `readonly` 数组替代可变数组。

【**正确示例**】

```typescript
interface Config {
  readonly id: string;
  name: string;
  description?: string;
  readonly items: readonly string[];
}
```

### 4. 类型守卫

- 使用类型守卫（`typeof`、`instanceof`、自定义守卫函数）进行类型收窄。
- 避免使用非空断言 `!`。

【**正确示例**】

```typescript
function processValue(value: string | number): void {
  if (typeof value === 'string') {
    console.log(value.toUpperCase());
  } else {
    console.log(value.toFixed(2));
  }
}
```

## 注释规范

### 1. 注释风格

- 使用 JSDoc / TSDoc 风格注释为公共 API 添加文档。
- 单行注释使用 `//`，多行注释使用 `/* ... */`。
- 注释应放在被注释代码的上方。
- 注释与所描述内容进行同样的缩进。
- 修改代码同时更新注释，不再有用的注释要删除。

### 2. 文件头注释

文件头部应进行注释，注释必须列出：版权说明、版本号、生成日期、作者、内容、功能等。

【**推荐格式**】

```typescript
/**
 * =====================================================
 * Copyright © sumu. 2022-present. Tech. Co., Ltd. All rights reserved.
 * File name  : 文件名
 * Author     : xxx
 * Date       : YYYY/MM/DD
 * Version    :
 * Description:
 * ======================================================
 */
```

### 3. 函数与类注释

**函数注释（强制）**

每个函数必须添加 JSDoc 风格注释，包含 `@param`、`@returns`、`@throws` 等标签。函数内部关键逻辑处必须添加合理的注释，说明非显而易见的处理意图。

- 函数头注释：描述函数功能、每个参数的含义、返回值、可能抛出的异常。
- 函数内注释：在复杂算法、分支逻辑、特殊处理、边界条件等处添加注释，说明"为什么"而非"做什么"。

【**正确示例**】

```typescript
/**
 * 计算两个数字的和
 * @param a - 第一个加数
 * @param b - 第二个加数
 * @returns 两数之和
 * @throws {TypeError} 当传入非数字时抛出
 */
function add(a: number, b: number): number {
  // 类型检查，防止非预期输入
  if (typeof a !== 'number' || typeof b !== 'number') {
    throw new TypeError('Parameters must be numbers');
  }
  // 直接返回计算结果
  return a + b;
}
```

**类注释（强制）**

每个类声明必须添加 JSDoc 风格注释，说明类的职责与用途。类内部的每个方法也必须有 JSDoc 注释。

```typescript
/**
 * 用户服务类，负责用户的增删改查与权限校验
 */
class UserService {
  /**
   * 根据用户 ID 获取用户信息
   * @param id - 用户唯一标识
   * @returns 用户对象，不存在时返回 undefined
   */
  public getUser(id: string): User | undefined {
    // 从缓存中查找，减少数据库查询
    return this.cache.get(id) as User | undefined;
  }
}
```

### 4. 接口与类型注释

**接口与类型别名（强制）**

每个接口和类型别名声明必须添加 JSDoc 风格注释，说明其用途与职责。成员注释使用双斜杠 `//`，紧跟在成员后面，不要另起一行。

```typescript
/** 用户实体接口 */
interface User {
  id: string;   // 用户唯一标识
  name: string; // 用户显示名称
}

/** 创建用户请求参数 */
type CreateUserRequest = {
  name: string;
  email: string;
  role?: string; // 角色可选
};
```

## 导入导出规范

### 1. 导入顺序

- 按以下顺序分组，组间留一个空行：
  1. 内置模块（如 `fs`、`path`）
  2. 第三方模块（如 `react`、`lodash`）
  3. 本地绝对路径导入
  4. 本地相对路径导入（按 `../`、`./` 顺序）

### 2. 导入格式

- 优先使用具名导入，避免使用默认导入（React 组件除外）。
- 禁止使用 `require`，统一使用 ES Module 的 `import`。
- 导入多个成员时使用多行格式。

【**正确示例**】

```typescript
import { readFile } from 'fs';

import { useState, useEffect } from 'react';
import axios from 'axios';

import { Config } from '~/config';

import { helper } from '../utils/helper';
import { localUtil } from './localUtil';
```

### 3. 导出规范

- 优先使用具名导出。
- 每个文件最多一个默认导出（React 组件文件除外）。
- 导出语句放在文件底部。

## 类与函数规范

### 1. 类规范

- 类的属性按 `public` -> `protected` -> `private` 顺序排列。
- 方法按 `public` -> `protected` -> `private` 顺序排列。
- 构造函数参数中直接声明属性时，使用访问修饰符简写。

【**正确示例**】

```typescript
/**
 * 用户服务类，管理用户数据与缓存
 */
class UserService {
  public readonly name: string;
  protected cache: Map<string, unknown>;
  private _secret: string;

  constructor(name: string, secret: string) {
    this.name = name;
    this._secret = secret;
    this.cache = new Map();
  }

  /**
   * 获取用户信息
   * @param id - 用户唯一标识
   * @returns 用户对象，可能为 undefined
   */
  public getUser(id: string): User | undefined {
    return this.cache.get(id) as User | undefined;
  }

  /**
   * 校验内部密钥有效性
   * @returns 密钥有效返回 true
   */
  private _validate(): boolean {
    return !!this._secret;
  }
}
```

### 2. 函数规范

- 优先使用函数声明而非函数表达式。
- 函数参数不超过 4 个，超过时使用对象传参。
- 使用默认参数值替代条件判断赋值。
- 箭头函数在简单场景下使用隐式返回。

【**正确示例**】

```typescript
// 函数声明
function greet(name: string, greeting: string = 'Hello'): string {
  return `${greeting}, ${name}!`;
}

// 参数对象化
interface CreateUserOptions {
  name: string;
  email: string;
  age?: number;
  role?: string;
}

function createUser(options: CreateUserOptions): User {
  // ...
}
```

### 3. 异步规范

- 优先使用 `async/await`，避免回调地狱。
- `Promise` 链式调用过长时，使用 `async/await` 重构。
- 错误处理使用 `try/catch`。

【**正确示例**】

```typescript
async function fetchUserData(userId: string): Promise<User> {
  try {
    const response = await api.get(`/users/${userId}`);
    return response.data;
  } catch (error) {
    console.error('Failed to fetch user:', error);
    throw new Error('User data fetch failed');
  }
}
```

## 错误处理规范

- 优先使用自定义错误类，而非直接抛出字符串或普通 Error。
- 错误类命名以 `Error` 结尾。
- 在 `catch` 块中对错误进行适当处理，不要静默吞掉错误。

【**正确示例**】

```typescript
class ValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ValidationError';
  }
}

function validateInput(input: string): void {
  if (!input.trim()) {
    throw new ValidationError('Input cannot be empty');
  }
}
```

## 行为规范

### 代码检查

当用户要求检查代码规范性时：

1. 逐一对照本规范进行检查。
2. 重点检查：`any` 使用、类型显式声明、命名规范、导入顺序、注释规范。
3. 指出不符合规范的具体位置和原因。
4. 提供修改建议。

### 代码编写

当用户要求编写 TypeScript 代码时：

1. 优先应用本规范的所有格式要求。
2. 为文件添加标准文件头注释。
3. 为**每个函数**添加 JSDoc 风格注释（`@param`、`@returns`、`@throws`），函数内部关键逻辑添加注释。
4. 为**每个类**添加 JSDoc 风格注释，类内每个方法也须添加 JSDoc 注释。
5. 确保命名符合规范要求。
6. 避免使用 `any`，使用严格的类型声明。
7. 使用 `async/await` 处理异步操作。
