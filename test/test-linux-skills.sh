#!/bin/bash
# * =====================================================
# * Copyright © sumu. 2026-present. Tech. Co., Ltd. All rights reserved.
# * File name  : test-linux-skills.sh
# * Author     : 苏木
# * Date       : 2026/06/28
# * Version    : 1.1.0
# * Description: linux-skills.sh 端到端测试（纯测试逻辑）
# *
# * 本脚本仅负责 Linux / 容器内的测试逻辑。
# *   - Linux 下直接运行:   ./test-linux-skills.sh
# *   - Windows 下由 test-linux-skills.ps1 通过 docker 调起本脚本，
# *     仓库挂载到容器 /workspace（无需 Git Bash 中转）。
# *
# * 设计原则 (与 test-windows-skills.ps1 对称):
# *   1. 自包含: 测试结束恢复成 install 完整可用态
# *   2. 不破坏仓库源: 校验仓库 skill 文件 md5 全程不变 (update 验证场景用 cp 备份还原)
# *   3. trap EXIT 兜底: 中途失败也执行 cleanup
# *   4. 断言式: 每个用例 PASS/FAIL, 最后汇总
# *
# * 用法:
# *   ./test-linux-skills.sh          # 直接运行（Linux 或容器内）
# *   ./test-linux-skills.sh -v       # 详细输出
# * ======================================================

set -u

# ========================================================
# 路径与配置
# ========================================================
SCRIPT_NAME=$(basename "$0")
# 脚本在 test/ 子目录下，仓库根 = 上一级
TEST_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "${TEST_DIR}/.." && pwd)
TARGET="${REPO_ROOT}/linux-skills.sh"
REPO_SKILLS="${REPO_ROOT}/skills"
MIRROR="${HOME}/.smskills"

declare -A TOOLS
TOOLS[claude]="${HOME}/.claude/skills"
TOOLS[roo]="${HOME}/.roo/skills"
TOOLS[zcode]="${HOME}/.zcode/skills"
TOOLS[opencode]="${HOME}/.config/opencode/skills"
TOOLS[codebuddy]="${HOME}/.codebuddy/skills"
TOOL_KEYS=("claude" "roo" "zcode" "opencode" "codebuddy")

# 技能列表：动态扫描仓库 skills/ 目录下的子目录（不硬编码）
# 每个子目录视为一个 skill
SKILL_LIST=()
if [ -d "${REPO_SKILLS}" ]; then
    for _d in "${REPO_SKILLS}"/*/; do
        [ -d "$_d" ] && SKILL_LIST+=("$(basename "$_d")")
    done
fi
SKILLS="${SKILL_LIST[*]}"          # 空格分隔，供 for s in $SKILLS 遍历
SKILL_COUNT=${#SKILL_LIST[@]}      # 技能总数

# 计数器
PASS=0
FAIL=0
FAIL_CASES=()
VERBOSE=0

for arg in "$@"; do
    case "$arg" in
        -v|--verbose) VERBOSE=1 ;;
    esac
done

# ========================================================
# 日志与断言
# ========================================================
c_pass()    { printf "  \e[32m[PASS]\e[0m %s\n" "$1"; }
c_fail()    { printf "  \e[31m[FAIL]\e[0m %s\n" "$1"; [ -n "$2" ] && printf "         \e[90m%s\e[0m\n" "$2"; }
c_group()   { printf "\n\e[36m━━━ %s ━━━\e[0m\n" "$1"; }
c_diag()    { [ $VERBOSE -eq 1 ] && printf "    \e[90m%s\e[0m\n" "$1" || true; }

assert_case() {
    local name="$1" check="$2" detail="${3:-}"
    local ok
    # 区分：可执行函数引用 vs 字符串条件。字符串条件用 eval。
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
# 取文件 md5 前 8 位
md5short() {
    [ -f "$1" ] || { echo "MISSING"; return; }
    if command -v md5sum >/dev/null 2>&1; then
        md5sum "$1" | cut -c1-8
    else
        md5 -q "$1" 2>/dev/null | cut -c1-8 || echo "NOMD5"
    fi
}

# 目录下文件数（递归）
file_count() {
    [ -d "$1" ] || { echo 0; return; }
    find "$1" -type f 2>/dev/null | wc -l
}

# 判断是否符号链接
is_link() { [ -L "$1" ]; }

# 判断是否为指向期望源的正确软链
is_correct_link() { [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ]; }

# 记录仓库 skill md5 基线（不变量：全程不变）
get_repo_baseline() {
    local s
    for s in $SKILLS; do
        echo "$s|$(md5short "${REPO_SKILLS}/${s}/SKILL.md")"
    done
}

# 调用被测脚本（静默，收集输出）
invoke_target() {
    bash "$TARGET" "$@" 2>&1
}

# ========================================================
# Cleanup
# ========================================================
cleanup() {
    echo ""
    echo "恢复环境 -> install ..." >&2
    invoke_target install >/dev/null 2>&1 || true
    echo "完成。" >&2
}

# ========================================================
# 主测试逻辑
# ========================================================
run_tests() {
    local repo_baseline
    repo_baseline=$(get_repo_baseline)

    # 解析基线到关联数组（bash 4+）
    declare -A baseline
    local line
    while IFS='|' read -r k v; do baseline[$k]=$v; done <<< "$repo_baseline"

    echo ""
    echo "=========================================="
    echo "  linux-skills.sh 端到端测试"
    echo "=========================================="
    echo "  target : $TARGET"
    echo "  repo   : $REPO_SKILLS"
    echo "  mirror : $MIRROR"
    echo "  tools  : ${TOOL_KEYS[*]}"
    echo "  host   : $(uname -s)"
    echo ""

    # --------------------------------------------------------
    # 0. 前置清理：干净起点
    # --------------------------------------------------------
    c_group "前置清理"
    invoke_target unlink all >/dev/null 2>&1 || true
    if [ -d "$MIRROR" ]; then
        rm -rf "${MIRROR:?}/"*  2>/dev/null || true
    fi
    echo "  (已清空 agent 链接与 mirror)"

    # --------------------------------------------------------
    # 1. help
    # --------------------------------------------------------
    c_group "1. help (帮助)"
    local out; out=$(invoke_target help)
    check_help_usage()    { echo "$out" | grep -q '用法'; }
    check_help_install()  { echo "$out" | grep -q 'install'; }
    check_help_update()   { echo "$out" | grep -q 'update'; }
    check_help_link()     { echo "$out" | grep -q 'link'; }
    check_help_unlink()   { echo "$out" | grep -q 'unlink'; }
    check_help_topology() { echo "$out" | grep -q '拓扑'; }
    assert_case "帮助菜单包含 用法"      check_help_usage
    assert_case "帮助菜单包含 install"   check_help_install
    assert_case "帮助菜单包含 update"    check_help_update
    assert_case "帮助菜单包含 link"      check_help_link
    assert_case "帮助菜单包含 unlink"    check_help_unlink
    assert_case "帮助菜单包含 拓扑说明"  check_help_topology

    # --------------------------------------------------------
    # 2. install (update + link all)
    # --------------------------------------------------------
    c_group "2. install (update + link all)"
    invoke_target install >/dev/null 2>&1

    check_mirror_count() {
        local cnt=0 n
        for n in $SKILLS; do [ -d "${MIRROR}/${n}" ] && cnt=$((cnt+1)); done
        c_diag "mirror skill 数: $cnt (期望 $SKILL_COUNT)"
        [ $cnt -eq $SKILL_COUNT ]
    }
    assert_case "mirror 已建立全部 skill ($SKILL_COUNT)" check_mirror_count "mirror skill 数应为 $SKILL_COUNT"

    check_mirror_content() {
        local s m ok=1
        for s in $SKILLS; do
            m=$(md5short "${MIRROR}/${s}/SKILL.md")
            [ "$m" = "${baseline[$s]}" ] || { c_diag "${s}: mirror=$m repo=${baseline[$s]}"; ok=0; }
        done
        [ $ok -eq 1 ]
    }
    assert_case "mirror 内容 = 仓库源 (逐个 md5)" check_mirror_content

    for tk in "${TOOL_KEYS[@]}"; do
        check_tool_links() {
            local _tk="$1" n linked=0 total=0
            for n in $SKILLS; do
                [ -e "${TOOLS[$_tk]}/${n}" ] && total=$((total+1))
                is_link "${TOOLS[$_tk]}/${n}" && linked=$((linked+1))
            done
            c_diag "${_tk}: $linked/$total linked (期望 $SKILL_COUNT)"
            [ $total -eq $SKILL_COUNT ] && [ $linked -eq $SKILL_COUNT ]
        }
        assert_case "${tk}: 全部 skill 为软链接 ($SKILL_COUNT)" "check_tool_links ${tk}"

        check_tool_content() {
            local _tk="$1" s a ok=1
            for s in $SKILLS; do
                a=$(md5short "${TOOLS[$_tk]}/${s}/SKILL.md")
                [ "$a" = "${baseline[$s]}" ] || ok=0
            done
            [ $ok -eq 1 ]
        }
        assert_case "${tk}: 链接内容 = 仓库源" "check_tool_content ${tk}"
    done

    # --------------------------------------------------------
    # 3. status
    # --------------------------------------------------------
    c_group "3. status (状态矩阵)"
    out=$(invoke_target status)
    check_status_mirror() { echo "$out" | grep -qF "$MIRROR"; }
    assert_case "status 含 mirror 路径" check_status_mirror
    check_status_skills() {
        local s ok=1
        for s in $SKILLS; do [[ "$out" == *"$s"* ]] || ok=0; done
        [ $ok -eq 1 ]
    }
    assert_case "status 含所有 skill 名" check_status_skills
    check_status_tools() {
        local tk ok=1
        for tk in "${TOOL_KEYS[@]}"; do [[ "$out" == *"$tk"* ]] || ok=0; done
        [ $ok -eq 1 ]
    }
    assert_case "status 含所有工具名" check_status_tools

    local tool_count=${#TOOL_KEYS[@]}
    check_status_links() {
        # 每个 skill 行应含 $tool_count 个 LINK
        local line ok=1 cnt s is_skill
        while IFS= read -r line; do
            # 判断是否为 skill 数据行（行首匹配某个 skill 名）
            is_skill=0
            for s in "${SKILL_LIST[@]}"; do
                case "$line" in
                    *"  $s "*|"  $s") is_skill=1; break ;;
                esac
            done
            [ $is_skill -eq 1 ] || continue
            cnt=$(echo "$line" | grep -o 'LINK' | wc -l)
            [ "$cnt" -eq $tool_count ] || { c_diag "行 LINK 数=$cnt (期望 $tool_count) : $line"; ok=0; }
        done <<< "$out"
        [ $ok -eq 1 ]
    }
    assert_case "status 每个 skill 行有 $tool_count 个 LINK" check_status_links

    # --------------------------------------------------------
    # 4. list
    # --------------------------------------------------------
    c_group "4. list (列表)"
    out=$(invoke_target list)
    DISPLAY_NAMES=("Claude Code" "RooCode" "ZCode" "OpenCode" "CodeBuddy")
    check_list_tools() {
        local n ok=1 lower
        lower=$(echo "$out" | tr 'A-Z' 'a-z')
        for n in "${DISPLAY_NAMES[@]}"; do
            echo "$lower" | grep -qi -- "$n" || ok=0
        done
        [ $ok -eq 1 ]
    }
    assert_case "list 含所有工具显示名" check_list_tools
    check_list_skills() {
        local s ok=1
        for s in $SKILLS; do [[ "$out" == *"$s"* ]] || ok=0; done
        [ $ok -eq 1 ]
    }
    assert_case "list 含所有 skill 名" check_list_skills
    check_list_tag() { echo "$out" | grep -q '\[link\]'; }
    assert_case "list 含 [link] 标记" check_list_tag

    # --------------------------------------------------------
    # 5. unlink + link 循环
    # --------------------------------------------------------
    c_group "5. unlink + link (循环)"
    local mirror_before; mirror_before=$(file_count "$MIRROR")
    invoke_target unlink claude >/dev/null 2>&1

    check_unlink_empty() {
        local cnt=0 n
        for n in $SKILLS; do [ -e "${TOOLS[claude]}/${n}" ] && cnt=$((cnt+1)); done
        c_diag "claude skill 数: $cnt"
        [ $cnt -eq 0 ]
    }
    assert_case "unlink claude 后 claude 目录空" check_unlink_empty

    check_unlink_mirror_safe() {
        local now; now=$(file_count "$MIRROR")
        c_diag "mirror 文件数: before=$mirror_before now=$now"
        [ "$now" -eq "$mirror_before" ]
    }
    assert_case "unlink claude 不影响 mirror 源 (文件数不变)" check_unlink_mirror_safe "mirror 文件数应保持 $mirror_before"

    check_unlink_repo_safe() {
        local s ok=1
        for s in $SKILLS; do
            [ "$(md5short "${REPO_SKILLS}/${s}/SKILL.md")" = "${baseline[$s]}" ] || ok=0
        done
        [ $ok -eq 1 ]
    }
    assert_case "unlink claude 不影响仓库源 (md5 不变)" check_unlink_repo_safe

    invoke_target link claude >/dev/null 2>&1
    check_relink() {
        local linked=0 n
        for n in $SKILLS; do is_link "${TOOLS[claude]}/${n}" && linked=$((linked+1)); done
        c_diag "claude linked: $linked (期望 $SKILL_COUNT)"
        [ $linked -eq $SKILL_COUNT ]
    }
    assert_case "link claude 后全部 skill 重新链接 ($SKILL_COUNT)" check_relink

    # --------------------------------------------------------
    # 6. update (仓库改动 -> 镜像同步)
    # --------------------------------------------------------
    c_group "6. update (仓库改动同步)"
    local marker="${REPO_SKILLS}/markdowncli/SKILL.md"
    local orig_md5; orig_md5=$(md5short "$marker")
    local backup; backup=$(mktemp)
    cp "$marker" "$backup"

    # 临时改动仓库文件
    printf '\n<!-- test-marker %s -->\n' "$(date +%s)" >> "$marker"
    local changed_md5; changed_md5=$(md5short "$marker")
    c_diag "仓库 markdowncli: $orig_md5 -> $changed_md5"

    invoke_target update >/dev/null 2>&1

    check_update_mirror() {
        local m; m=$(md5short "${MIRROR}/markdowncli/SKILL.md")
        c_diag "mirror markdowncli: $m (应=$changed_md5)"
        [ "$m" = "$changed_md5" ]
    }
    assert_case "update 后 mirror 同步仓库改动" check_update_mirror

    check_update_agent() {
        local a; a=$(md5short "${TOOLS[claude]}/markdowncli/SKILL.md")
        c_diag "claude markdowncli: $a (应=$changed_md5)"
        [ "$a" = "$changed_md5" ]
    }
    assert_case "update 后 agent 经链接即时读到新内容" check_update_agent

    # 还原仓库（cp 备份还原，不依赖 git；无论上面断言是否通过都执行）
    cp "$backup" "$marker"
    rm -f "$backup"
    c_diag "仓库已还原: $(md5short "$marker") (orig=$orig_md5)"
    # 同步 mirror 回干净状态
    invoke_target update >/dev/null 2>&1
    check_repo_restored() { [ "$(md5short "$marker")" = "$orig_md5" ]; }
    assert_case "仓库文件已还原" check_repo_restored

    # --------------------------------------------------------
    # 7. update (孤儿清理)
    # --------------------------------------------------------
    c_group "7. update (孤儿清理)"
    mkdir -p "${MIRROR}/__orphan_test__"
    echo "fake" > "${MIRROR}/__orphan_test__/SKILL.md"
    local before_cnt=0 n
    for n in $SKILLS; do [ -d "${MIRROR}/${n}" ] && before_cnt=$((before_cnt+1)); done
    before_cnt=$((before_cnt + 1))  # 含造的孤儿
    c_diag "造孤儿前 mirror skill 数: $before_cnt"

    out=$(invoke_target update)
    assert_case "update 清理了孤儿目录" "[ ! -d \"${MIRROR}/__orphan_test__\" ]"
    check_orphan_count() {
        local cnt=0 n
        for n in $SKILLS; do [ -d "${MIRROR}/${n}" ] && cnt=$((cnt+1)); done
        c_diag "mirror skill 数: $cnt (期望 $SKILL_COUNT)"
        [ $cnt -eq $SKILL_COUNT ]
    }
    assert_case "update 后 mirror skill 数 = $SKILL_COUNT" check_orphan_count

    # --------------------------------------------------------
    # 8. 仓库源完整性终检
    # --------------------------------------------------------
    c_group "8. 仓库源完整性终检"
    check_repo_intact() {
        local s now ok=1
        for s in $SKILLS; do
            now=$(md5short "${REPO_SKILLS}/${s}/SKILL.md")
            [ "$now" = "${baseline[$s]}" ] || { c_diag "${s}: $now != ${baseline[$s]}"; ok=0; }
        done
        [ $ok -eq 1 ]
    }
    assert_case "仓库全部 skill md5 全程未变 ($SKILL_COUNT)" check_repo_intact

    # --------------------------------------------------------
    # 汇总
    # --------------------------------------------------------
    echo ""
    echo "=========================================="
    echo "  测试汇总"
    echo "=========================================="
    printf "  PASS: %d\n" "$PASS"
    [ $FAIL -eq 0 ] && printf "  FAIL: %d\n" "$FAIL" || printf "  \e[31mFAIL: %d\e[0m\n" "$FAIL"
    if [ ${#FAIL_CASES[@]} -gt 0 ]; then
        echo ""
        echo "  失败用例:"
        for c in "${FAIL_CASES[@]}"; do printf "    - %s\n" "$c"; done
    fi
    echo ""

    [ $FAIL -eq 0 ]
}

# ========================================================
# 主入口
# ========================================================
trap cleanup EXIT
if run_tests; then
    printf "\n\e[32m✅ 全部测试通过\e[0m\n"
    exit 0
else
    printf "\n\e[31m❌ 存在失败用例\e[0m\n"
    exit 1
fi
