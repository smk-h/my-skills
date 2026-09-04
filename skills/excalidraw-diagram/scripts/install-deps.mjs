#!/usr/bin/env node
/**
 * 为 excalidraw-diagram 技能安装渲染依赖。
 *
 * 依赖装在技能目录自己的 .render-runtime/ 下，不写入项目的 package.json。
 *
 * 用法:
 *   node install-deps.mjs            # 依赖缺失时才安装，已就绪则跳过
 *   node install-deps.mjs --force    # 强制重装
 *   node install-deps.mjs --check    # 只检查状态，不安装
 *   node install-deps.mjs --remove   # 删除已安装的依赖目录
 */
import { execSync } from "node:child_process";
import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const SKILL_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const RUNTIME_DIR = path.join(SKILL_DIR, ".render-runtime");

/** 依赖清单：@excalidraw/utils 是预发布版，必须锁死精确版本 */
export const DEPS = ["@excalidraw/utils@0.1.3-test32", "jsdom@^26.0.0"];

/** 依赖是否已就绪（两个包都能解析到即视为就绪） */
export function depsReady() {
  try {
    const req = createRequire(path.join(RUNTIME_DIR, "noop.js"));
    req.resolve("@excalidraw/utils");
    req.resolve("jsdom");
    return true;
  } catch {
    return false;
  }
}

/** 安装依赖到 .render-runtime/ */
export function installDeps() {
  console.log("正在安装渲染依赖（约 100MB，仅本地 dev 用途，不影响项目 package.json）…");
  fs.mkdirSync(RUNTIME_DIR, { recursive: true });

  const pkgFile = path.join(RUNTIME_DIR, "package.json");
  if (!fs.existsSync(pkgFile)) {
    fs.writeFileSync(
      pkgFile,
      JSON.stringify(
        { name: "excalidraw-render-runtime", private: true, type: "module", version: "1.0.0" },
        null,
        2,
      ) + "\n",
    );
  }

  execSync(`npm install --no-audit --no-fund --loglevel=error ${DEPS.join(" ")}`, {
    cwd: RUNTIME_DIR,
    stdio: "inherit",
  });
  console.log(`依赖安装完成: ${RUNTIME_DIR}`);
}

/** 确保依赖就绪：缺失时自动安装。供 render-excalidraw.mjs 调用 */
export function ensureDeps() {
  if (depsReady()) return;
  installDeps();
  if (!depsReady()) {
    throw new Error(`依赖安装失败，请手动执行: node ${fileURLToPath(import.meta.url)}`);
  }
}

function removeDeps() {
  if (!fs.existsSync(RUNTIME_DIR)) {
    console.log("依赖目录不存在，无需清理。");
    return;
  }
  fs.rmSync(RUNTIME_DIR, { recursive: true, force: true });
  console.log(`已删除 ${RUNTIME_DIR}`);
}

function isDirectRun() {
  return process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
}

if (isDirectRun()) {
  const args = process.argv.slice(2);

  if (args.includes("--remove")) {
    removeDeps();
  } else if (args.includes("--check")) {
    const ready = depsReady();
    console.log(ready ? `依赖已就绪: ${RUNTIME_DIR}` : `依赖未安装: ${RUNTIME_DIR}`);
    process.exit(ready ? 0 : 1);
  } else if (args.includes("--force")) {
    installDeps();
  } else {
    if (depsReady()) {
      console.log(`依赖已就绪，跳过安装: ${RUNTIME_DIR}`);
    } else {
      installDeps();
    }
  }
}
