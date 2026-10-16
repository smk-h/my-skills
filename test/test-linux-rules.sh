#!/bin/bash
# * =====================================================
# * Copyright © sumu. 2026-present. Tech. Co., Ltd. All rights reserved.
# * File name  : test-linux-rules.sh
# * Author     : 苏木
# * Date       : 2026/10/16
# * Version    : 1.0.0
# * Description: linux-rules.sh 端到端测试（纯测试逻辑）
# *
# * 本脚本仅负责 Linux / 容器内的测试逻辑，与 test-windows-rules.ps1 用例对称：
# *   - Linux 下直接运行:   ./test-linux-rules.sh
# *   - Windows 下由 test-linux-rules.ps1 通过 docker 调起本脚本，
# *     仓库挂载到容器 /workspace（无需 Git Bash 中转）。
# *
# * 设计原则 (与 test-windows-rules.ps1 对称):
# *   1. 全程沙箱: HOME 指向临时目录, 真实用户目录零触碰（测试前后 md5 快照比对）
# *   2. 不破坏仓库源: 校验 rules/AGENTS.md md5 全程不变
# *   3. trap EXIT 兜底: 中途失败也清理沙箱
# *   4. 断言式: 每个用例 PASS/FAIL, 最后汇总
# *
# * 用法:
# *   ./test-linux-rules.sh          # 直接运行（Linux 或容器内）
# *   ./test-linux-rules.sh -v       # 详细输出
# * ======================================================

set -u

# ========================================================
# 路径与配置
# ========================================================
TEST_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "${TEST_DIR}/.." && pwd)
TARGET="${REPO_ROOT}/linux-rules.sh"
SRC="${REPO_ROOT}/rules/AGENTS.md"

# 沙箱 HOME：所有目标落在沙箱内，真实 HOME 零触碰
SANDBOX=$(mktemp -d) || exit 2
# 真实 HOME 下的目标路径（不变量基线）
REAL_HOME="${HOME}"
RULE_REL=".codebuddy/rules/agents-rules/RULE.mdc"
TOOL_RELS=(".claude/CLAUDE.md" ".zcode/AGENTS.md" ".config/opencode/AGENTS.md" "${RULE_REL}" ".dsh/AGENTS.md")
TOOL_KEYS=("claude" "zcode" "opencode" "codebuddy" "dsh")
LEGACY_REL=".codebuddy/CODEBUDDY.md"

# 计数器
PASS=0
FAIL=0
FAIL_CASES=()
VERBOSE=0
OUT=""
RC=0
for arg in "$@"; do
    case "$arg" in
        -v|--verbose) VERBOSE=1 ;;
    esac
done

# ========================================================
# 日志与断言
# ========================================================
c_pass()  { printf "  \e[32m[PASS]\e[0m %s\n" "$1"; }
c_fail()  { printf "  \e[31m[FAIL]\e[0m %s\n" "$1"; [ -n "${2:-}" ] && printf "         \e[90m%s\e[0m\n" "$2"; }
c_group() { printf "\n\e[36m━━━ %s ━━━\e[0m\n" "$1"; }
c_diag()  { [ $VERBOSE -eq 1 ] && printf "    \e[90m%s\e[0m\n" "$1" || true; }

assert_case() {
    local name="$1" check="$2" detail="${3:-}"
    local ok
    if type "$check" >/dev/null 2>&1; then
        "$check"; ok=$?
    else
        eval "$check"; ok=$?
    fi
    if [ $ok -eq 0 ]; then
        c_pass "$name"; PASS=$((PASS + 1))
    else
        c_fail "$name" "$detail"; FAIL=$((FAIL + 1)); FAIL_CASES+=("$name")
    fi
}

# ========================================================
# 工具函数
# ========================================================
md5short() {
    [ -f "$1" ] || { echo "MISSING"; return; }
    if command -v md5sum >/dev/null 2>&1; then
        md5sum "$1" | cut -c1-8
    else
        md5 -q "$1" 2>/dev/null | cut -c1-8 || echo "NOMD5"
    fi
}

# 沙箱内被测脚本调用：输出 -> OUT，退出码 -> RC
run_target() {
    OUT=$(HOME="$SANDBOX" bash "$TARGET" "$@" 2>&1)
    RC=$?
}

# 沙箱内目标绝对路径
sb_path() { echo "${SANDBOX}/$1"; }

# 输出包含某字符串
out_has() { printf '%s' "$OUT" | grep -q "$1"; }

# 输出中某状态出现次数
out_count() { printf '%s' "$OUT" | grep -c "$1" || true; }

# 沙箱内现存目标数量（可排除某个 key）
present_count() {
    local exclude="${1:-}" n=0 i=0
    for rel in "${TOOL_RELS[@]}"; do
        key="${TOOL_KEYS[$i]}"; i=$((i + 1))
        [ "$key" = "$exclude" ] && continue
        [ -f "$(sb_path "$rel")" ] && n=$((n + 1))
    done
    echo $n
}

# 目标与规则源字节一致
same_as_src() { [ -f "$1" ] && cmp -s "$SRC" "$1"; }

# 无 BOM 且纯 LF
no_bom_lf() {
    local f="$1"
    [ -f "$f" ] || return 1
    if [ "$(head -c 3 "$f" | od -An -tx1 | tr -d ' \n')" = "efbbbf" ]; then return 1; fi
    if grep -q $'\r' "$f"; then return 1; fi
    return 0
}

# RULE.mdc 正文（第二个 --- 之后）与 AGENTS.md 全文一致
rule_body_ok() {
    local f="$1" t1 t2 rc
    t1=$(mktemp); t2=$(mktemp)
    printf '\n' > "$t1"
    sed 's/\r$//' "$SRC" >> "$t1"
    awk 'BEGIN{n=0} {if (n>=2) print; if ($0=="---") n++}' "$f" > "$t2"
    cmp -s "$t1" "$t2"; rc=$?
    rm -f "$t1" "$t2"
    return $rc
}

# 真实 HOME 下目标的 md5 快照
real_snapshot() {
    local rel
    for rel in "${TOOL_RELS[@]}"; do
        printf '%s=%s\n' "$rel" "$(md5short "${REAL_HOME}/${rel}")"
    done
    printf '%s=%s\n' "$LEGACY_REL" "$(md5short "${REAL_HOME}/${LEGACY_REL}")"
}

# ========================================================
# Cleanup
# ========================================================
cleanup() {
    rm -rf "$SANDBOX"
}
trap cleanup EXIT

# ========================================================
# 前置检查
# ========================================================
if [ ! -f "$TARGET" ]; then echo "❌ 被测脚本不存在: $TARGET"; exit 2; fi
if [ ! -f "$SRC" ]; then echo "❌ 规则源不存在: $SRC"; exit 2; fi

SRC_MD5=$(md5short "$SRC")
REAL_BEFORE=$(real_snapshot)

echo ""
echo "=============================================="
echo "  linux-rules.sh 测试"
echo "=============================================="
echo "  被测脚本  : $TARGET"
echo "  规则源    : $SRC  (md5 $SRC_MD5)"
echo "  沙箱 HOME : $SANDBOX"
echo "  工具      : ${TOOL_KEYS[*]}"
echo ""

# ========================================================
# A. 初始状态
# ========================================================
c_group "A. 初始状态（沙箱为空）"

run_target status
assert_case "status 正常输出且退出码为 0" '[ $RC -eq 0 ] && out_has "rules status"' "$OUT"
assert_case "status 报告 5 个目标全部 missing" '[ "$(out_count "\[missing\]")" -eq 5 ]' "$OUT"
assert_case "空沙箱下未创建任何目标" '[ "$(present_count)" -eq 0 ]'

# ========================================================
# B. 安装
# ========================================================
c_group "B. 安装（install -f）"

run_target install -f
assert_case "install 成功返回 0" '[ $RC -eq 0 ] && out_has "installed"' "$OUT"
assert_case "5 个目标文件全部创建" '[ "$(present_count)" -eq 5 ]'
assert_case "4 个 file 目标与规则源字节一致" \
    'same_as_src "$(sb_path .claude/CLAUDE.md)" && same_as_src "$(sb_path .zcode/AGENTS.md)" && same_as_src "$(sb_path .config/opencode/AGENTS.md)" && same_as_src "$(sb_path .dsh/AGENTS.md)"'
assert_case "codebuddy RULE.mdc 无 BOM 且纯 LF" 'no_bom_lf "$(sb_path '"$RULE_REL"')"'
assert_case "codebuddy RULE.mdc front matter 为 always-apply" \
    'grep -q "^alwaysApply: true$" "$(sb_path '"$RULE_REL"')" && grep -q "^enabled: true$" "$(sb_path '"$RULE_REL"')" && grep -q "^description: .\+$" "$(sb_path '"$RULE_REL"')"'
assert_case "codebuddy RULE.mdc 正文与 AGENTS.md 全文一致" 'rule_body_ok "$(sb_path '"$RULE_REL"')"'
assert_case "install 提醒规则只在新会话生效" 'out_has "NEW chat sessions only"' "$OUT"

run_target status
assert_case "status 报告 5 个目标全部 ok" '[ "$(out_count "\[ok\]")" -eq 5 ]' "$OUT"

RULE_MD5=$(md5short "$(sb_path "$RULE_REL")")
CLAUDE_MD5=$(md5short "$(sb_path .claude/CLAUDE.md)")
run_target install -f
assert_case "重复 install 幂等（already up to date）" '[ "$(out_count "already up to date")" -eq 5 ]' "$OUT"
assert_case "重复 install 不改变已安装内容" \
    '[ "$(md5short "$(sb_path '"$RULE_REL"')")" = "'"$RULE_MD5"'" ] && [ "$(md5short "$(sb_path .claude/CLAUDE.md)")" = "'"$CLAUDE_MD5"'" ]'

# ========================================================
# C. 覆盖策略（不一致才询问）
# ========================================================
c_group "C. 覆盖策略（询问 / 强制 / 跳过）"

printf 'foreign content\n' > "$(sb_path .claude/CLAUDE.md)"
OUT=$(printf 'n\n' | HOME="$SANDBOX" bash "$TARGET" -link claude 2>&1)
assert_case "不一致 + 答 n -> 跳过" 'out_has "skipped"' "$OUT"
assert_case "答 n 后目标内容未变" '[ "$(cat "$(sb_path .claude/CLAUDE.md)")" = "foreign content" ]'

OUT=$(printf 'y\n' | HOME="$SANDBOX" bash "$TARGET" -link claude 2>&1)
assert_case "不一致 + 答 y -> 覆盖并匹配仓库源" 'out_has "updated" && same_as_src "$(sb_path .claude/CLAUDE.md)"' "$OUT"

printf 'foreign content\n' > "$(sb_path .claude/CLAUDE.md)"
run_target link claude -f
assert_case "不一致 + -f -> 不询问直接覆盖" 'out_has "updated" && same_as_src "$(sb_path .claude/CLAUDE.md)"' "$OUT"

printf 'foreign rule\n' > "$(sb_path "$RULE_REL")"
OUT=$(printf 'n\n' | HOME="$SANDBOX" bash "$TARGET" -link codebuddy 2>&1)
assert_case "codebuddy 规则不一致 + 答 n -> 跳过" 'out_has "skipped"' "$OUT"
assert_case "codebuddy 规则被跳过时内容未变" '[ "$(cat "$(sb_path '"$RULE_REL"')")" = "foreign rule" ]'

run_target install -f
run_target status
assert_case "install -f 恢复全部 ok" '[ "$(out_count "\[ok\]")" -eq 5 ]' "$OUT"

# ========================================================
# D. 旧版 CODEBUDDY.md 迁移清理
# ========================================================
c_group "D. 旧版 CODEBUDDY.md 清理"

cp "$SRC" "$(sb_path "$LEGACY_REL")"
run_target link codebuddy -f
assert_case "与源一致的旧文件被清理并提示" \
    '[ ! -f "$(sb_path '"$LEGACY_REL"')" ] && out_has "removed legacy file"' "$OUT"

printf 'user modified legacy\n' > "$(sb_path "$LEGACY_REL")"
run_target link codebuddy -f
assert_case "改动过的旧文件被保留" \
    '[ -f "$(sb_path '"$LEGACY_REL"')" ] && out_has "legacy file kept"' "$OUT"

run_target status
assert_case "status 提示旧文件不会被加载" 'out_has "NOT loaded by CodeBuddy"' "$OUT"

# ========================================================
# E. 卸载（仅删与源一致的文件）
# ========================================================
c_group "E. 卸载"

printf 'foreign content\n' > "$(sb_path .dsh/AGENTS.md)"
run_target unlink dsh
assert_case "改动过的目标不被删除" \
    '[ -f "$(sb_path .dsh/AGENTS.md)" ] && out_has "skipped"' "$OUT"

run_target unlink all
assert_case "unlink all 删除 4 个一致目标，保留改动过的 dsh" \
    '[ "$(present_count)" -eq 1 ] && [ -f "$(sb_path .dsh/AGENTS.md)" ]' "$OUT"
assert_case "unlink codebuddy 连同规则目录一并移除" \
    '[ ! -d "$(sb_path .codebuddy/rules/agents-rules)" ]'

run_target status
assert_case "status: 4 个 missing + dsh differs" \
    '[ "$(out_count "\[missing\]")" -eq 4 ] && out_has "\[differs\]"' "$OUT"

# ========================================================
# F. 边界与不变量
# ========================================================
c_group "F. 边界与不变量"

run_target install nosuchtool
assert_case "未知工具被拒绝且退出码非 0" '[ $RC -ne 0 ] && out_has "未知工具"' "$OUT"
assert_case "未知工具未新增任何目标" '[ "$(present_count)" -eq 1 ]'

run_target bogus
assert_case "未知命令被拒绝且打印帮助" '[ $RC -ne 0 ] && out_has "用法:"' "$OUT"

run_target -status
assert_case "兼容 PowerShell 版写法（-status）" '[ $RC -eq 0 ] && out_has "source:"' "$OUT"
run_target -install -f
assert_case "兼容 PowerShell 版写法（-install -f 可安装）" '[ $RC -eq 0 ] && out_has "installed"' "$OUT"
run_target -install -f
assert_case "兼容 PowerShell 版写法（-install -f 幂等）" '[ $RC -eq 0 ] && out_has "already up to date"' "$OUT"

assert_case "仓库规则源全程未被改动" '[ "$(md5short "$SRC")" = "'"$SRC_MD5"'" ]'
assert_case "真实用户目录零触碰（md5 快照一致）" \
    '[ "$(real_snapshot)" = "'"$REAL_BEFORE"'" ]' "$(real_snapshot)"

# ========================================================
# 汇总
# ========================================================
echo ""
echo "=============================================="
if [ $FAIL -eq 0 ]; then
    printf "  \e[32m结果: %d passed, %d failed\e[0m\n" "$PASS" "$FAIL"
else
    printf "  \e[31m结果: %d passed, %d failed\e[0m\n" "$PASS" "$FAIL"
    echo "  失败用例:"
    for c in "${FAIL_CASES[@]}"; do echo "    - $c"; done
fi
echo "=============================================="
echo ""

[ $FAIL -eq 0 ] && exit 0 || exit 1
