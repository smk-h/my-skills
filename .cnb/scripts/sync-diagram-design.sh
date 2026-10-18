#!/usr/bin/env bash
#
# 同步 skills/diagram-design 到上游仓库的最新提交（供 .cnb.yml 定时任务与页面按钮调用）。
#
# 流程：
#   1. 从 skills/diagram-design/README.md 的「来源与版本记录」表读取原仓库与已拉取提交；
#   2. 浅克隆上游，取最新提交；哈希与已拉取一致且内容无差异时直接退出（幂等）；
#   3. 用上游内层 skills/diagram-design/ 覆盖本目录，保留本地 README.md 与 LICENSE；
#   4. 回写 README.md 表格（提交哈希/提交信息/提交日期/拉取日期/技能版本）与目录统计；
#   5. 提交并推送（CI 中用 CNB_TOKEN，推送后会触发 .cnb.yml 的 GitHub 同步任务）。
#
# 用法：
#   bash .cnb/scripts/sync-diagram-design.sh             # 同步 + 提交 + 推送
#   bash .cnb/scripts/sync-diagram-design.sh --dry-run   # 只报告差异，不改工作区
#   bash .cnb/scripts/sync-diagram-design.sh --no-push   # 同步 + 提交，不推送
#
# 页面手动触发按钮（.cnb/web_trigger.yml）通过环境变量 DRY_RUN_INPUT=true 传入试运行模式。
#
set -euo pipefail

# ---------------------------------------------------------------- 全局配置

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SKILL_DIR=${SKILL_DIR:-skills/diagram-design}
DOC="$SKILL_DIR/README.md"
UPSTREAM_REF=${UPSTREAM_REF:-main}
BRANCH=${BRANCH:-${CNB_BRANCH:-main}}
DEFAULT_UPSTREAM=${DEFAULT_UPSTREAM:-https://github.com/cathrynlavery/diagram-design}

# 运行期状态（由各函数填充）
DRY_RUN=false
PUSH=true
WORK=""
UPSTREAM_REPO=""
OLD_SHA=""
NEW_SHA=""
NEW_MSG=""
NEW_DATE=""
SKILL_VERSION=""
SRC=""

# ---------------------------------------------------------------- 基础工具

log() { printf '[sync-diagram-design] %s\n' "$*"; }
die() { printf '[sync-diagram-design] 错误：%s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
同步 skills/diagram-design 到上游仓库的最新提交。

用法：
  bash .cnb/scripts/sync-diagram-design.sh             # 同步 + 提交 + 推送
  bash .cnb/scripts/sync-diagram-design.sh --dry-run   # 只报告差异，不改工作区
  bash .cnb/scripts/sync-diagram-design.sh --no-push   # 同步 + 提交，不推送

环境变量：
  DRY_RUN_INPUT=true     同 --dry-run（页面「试运行」开关）
  BRANCH=<分支>          推送目标分支，默认取 CNB_BRANCH 或 main
  UPSTREAM_REF=<分支>    上游分支，默认 main
EOF
}

parse_args() {
  # 页面按钮传入的开关（select 传的是字符串）
  case "${DRY_RUN_INPUT:-}" in
    1|true|TRUE|yes|是) DRY_RUN=true ;;
  esac

  while (($#)); do
    case "$1" in
      --dry-run) DRY_RUN=true ;;
      --no-push) PUSH=false ;;
      -h|--help) usage; exit 0 ;;
      *) die "未知参数：$1（可用：--dry-run / --no-push）" ;;
    esac
    shift
  done
}

init_workdir() {
  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT
}

check_local_files() {
  [[ -f "$DOC" ]] || die "找不到 $DOC，无法读取版本记录"
  [[ -f "$SKILL_DIR/SKILL.md" ]] || die "找不到 $SKILL_DIR/SKILL.md"
}

# 读取 README 表格中 `| 标签 | 值 |` 的值
doc_field() {
  sed -n "s/^| $1 | \(.*\) |\r\{0,1\}\$/\1/p" "$DOC" | head -n 1 | tr -d '\r'
}

# ---------------------------------------------------------------- 上游侧

# 从 README 表格读取上游地址与已拉取提交
load_pin() {
  UPSTREAM_REPO=$(doc_field 原仓库)
  UPSTREAM_REPO=${UPSTREAM_REPO:-$DEFAULT_UPSTREAM}

  OLD_SHA=$(doc_field 拉取提交 | tr -d '`')
  [[ -n "$OLD_SHA" ]] || die "README 表格未记录「拉取提交」哈希（应为 | 拉取提交 | \`<40位哈希>\` |）"
}

clone_upstream() {
  log "上游仓库：$UPSTREAM_REPO（$UPSTREAM_REF）"
  log "已拉取提交：$OLD_SHA"

  git clone --quiet --depth 1 --branch "$UPSTREAM_REF" "$UPSTREAM_REPO" "$WORK/up" \
    || die "克隆上游仓库失败（网络或仓库地址变更）"

  SRC="$WORK/up/skills/diagram-design"
}

# 上游目录结构校验：内层 skill 目录与 name 字段都还在
check_upstream_layout() {
  [[ -f "$SRC/SKILL.md" ]] || die "上游未找到内层目录 skills/diagram-design/SKILL.md，目录结构可能已调整"
  grep -q '^name: diagram-design' "$SRC/SKILL.md" || die "上游 SKILL.md 的 name 不再是 diagram-design，已停止同步"
}

# 取上游最新提交信息
load_upstream_meta() {
  NEW_SHA=$(git -C "$WORK/up" rev-parse HEAD)
  NEW_MSG=$(git -C "$WORK/up" log -1 --format='%s')
  NEW_DATE=$(git -C "$WORK/up" log -1 --format='%cd' --date=short)
}

# 哈希一致时再比一次内容，防止本地被改坏后无人纠正
is_up_to_date() {
  [[ "$OLD_SHA" == "$NEW_SHA" ]] || return 1
  diff -rq --exclude=README.md --exclude=LICENSE "$SKILL_DIR" "$SRC" >/dev/null 2>&1
}

show_diff() {
  log "差异清单（dry-run，不会修改工作区）："
  diff -rq --exclude=README.md --exclude=LICENSE "$SKILL_DIR" "$SRC" || true
}

# ---------------------------------------------------------------- 本地侧

# 覆盖技能本体，保留本地维护的 README.md 与 LICENSE
sync_skill_files() {
  find "$SKILL_DIR" -mindepth 1 -maxdepth 1 ! -name README.md ! -name LICENSE -exec rm -rf {} +
  cp -a "$SRC"/. "$SKILL_DIR"/
}

# 按行首 `| 标签 | ` 替换表格中的第一行
set_row() {
  local label=$1 value=$2 tmp="$DOC.tmp"

  awk -v label="$label" -v val="$value" '
    BEGIN { prefix = "| " label " | "; done = 0 }
    !done && index($0, prefix) == 1 { print prefix val " |"; done = 1; next }
    { print }
  ' "$DOC" > "$tmp"

  cat "$tmp" > "$DOC"
  rm -f "$tmp"
}

# 回写 README 表格与目录统计
update_readme() {
  SKILL_VERSION=$(sed -n 's/^ *version: *"\([^"]*\)".*/\1/p' "$SKILL_DIR/SKILL.md" | head -n 1)
  local today assets_count refs_count
  today=$(date +%F)
  assets_count=$(find "$SKILL_DIR/assets" -maxdepth 1 -name '*.html' 2>/dev/null | wc -l | tr -d ' ')
  refs_count=$(find "$SKILL_DIR/references" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')

  set_row 拉取提交 "\`$NEW_SHA\`"
  set_row 提交信息 "${NEW_MSG//|/\\|}"
  set_row 提交日期 "$NEW_DATE"
  set_row 拉取日期 "$today"
  [[ -n "$SKILL_VERSION" ]] && set_row 技能版本 "$SKILL_VERSION（见 \`SKILL.md\` 的 metadata.version）"
  [[ -n "$assets_count" ]] && sed -i "s/\(- \`assets\/\`：\)[0-9]\+/\1$assets_count/" "$DOC"
  [[ -n "$refs_count" ]] && sed -i "s/\(- \`references\/\`：\)[0-9]\+/\1$refs_count/" "$DOC"
  return 0
}

# 暂存并提交；无实际改动时返回 1
commit_changes() {
  git add -A -- "$SKILL_DIR"
  if git diff --cached --quiet; then
    return 1
  fi

  # 提交作者优先取流水线触发者身份：CNB 的提交签名要求作者与令牌用户一致
  local author_name=${GIT_AUTHOR_NAME:-${CNB_BUILD_USER:-}}
  local author_email=${GIT_AUTHOR_EMAIL:-${CNB_BUILD_USER_EMAIL:-}}
  local git_cmd=(git) commit_args
  [[ -n "$author_name" ]] && git_cmd+=(-c "user.name=${author_name}")
  [[ -n "$author_email" ]] && git_cmd+=(-c "user.email=${author_email}")

  commit_args=(commit --quiet
    -m "ci(skills/diagram-design): 同步上游 ${OLD_SHA:0:8} → ${NEW_SHA:0:8}"
    -m "上游提交：${NEW_MSG}"
    -m "上游提交时间：${NEW_DATE}；技能版本：${SKILL_VERSION:-unknown}")

  if ! "${git_cmd[@]}" "${commit_args[@]}"; then
    log "带签名提交失败，改用 --no-gpg-sign 重试"
    "${git_cmd[@]}" "${commit_args[@]}" --no-gpg-sign
  fi

  log "已提交：$(git log -1 --format='%h %s')"
}

# 推送地址：CI 内用 CNB_TOKEN 拼 HTTPS 地址，本地回退 origin
resolve_push_url() {
  if [[ -n "${CNB_TOKEN:-}" ]]; then
    # 文档：用户名固定 cnb，密码用访问令牌（https://docs.cnb.cool/zh/guide/git-access.md）
    local base_url=${CNB_REPO_URL_HTTPS:-https://${CNB_WEB_HOST:-cnb.cool}/${CNB_REPO_SLUG:-}}
    [[ -n "$base_url" ]] || die "无法确定仓库地址（CNB_REPO_URL_HTTPS / CNB_REPO_SLUG 均为空）"
    printf '%s\n' "https://cnb:${CNB_TOKEN}@${base_url#https://}"
    return 0
  fi

  log "未检测到 CNB_TOKEN，回退到 origin 推送（本地执行需自行具备推送权限）" >&2
  git remote get-url origin
}

push_changes() {
  local remote_url
  remote_url=$(resolve_push_url)

  if ! git push --quiet "$remote_url" "HEAD:refs/heads/${BRANCH}" 2> "$WORK/push.err"; then
    sed "s|${CNB_TOKEN:-__none__}|***|g" "$WORK/push.err" >&2
    die "推送到 $BRANCH 失败（常见原因：目标分支有保护规则需走 MR，或远端有新提交非快进）"
  fi

  log "已推送到 ${BRANCH}，GitHub 镜像由 push 流水线自动同步"
}

# ---------------------------------------------------------------- 主流程

main() {
  parse_args "$@"
  check_local_files
  load_pin
  init_workdir

  clone_upstream
  check_upstream_layout
  load_upstream_meta

  if is_up_to_date; then
    log "已是上游最新版本（$NEW_SHA），本次无需更新"
    return 0
  fi

  # hash 相同但内容有差异：本地被改过，继续走覆盖同步纠正
  if [[ "$OLD_SHA" == "$NEW_SHA" ]]; then
    log "提交 hash 相同（${NEW_SHA:0:8}）但本地内容与上游不一致，重新同步"
  fi

  log "上游最新提交：$NEW_SHA"
  log "提交信息：$NEW_MSG（$NEW_DATE）"

  if $DRY_RUN; then
    show_diff
    return 0
  fi

  sync_skill_files
  update_readme

  if ! commit_changes; then
    log "未产生实际改动，跳过提交"
    return 0
  fi

  if ! $PUSH; then
    log "按 --no-push 跳过推送"
    return 0
  fi

  push_changes
}

main "$@"
