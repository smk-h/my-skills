#!/bin/bash
# * =====================================================
# * Copyright © sumu. 2026-present. Tech. Co., Ltd. All rights reserved.
# * File name  : linux-rules.sh
# * Author     : 苏木
# * Date       : 2026/10/16
# * Version    : 1.0.0
# * Description: 在 Linux / macOS 下把仓库 rules/AGENTS.md 安装到各 AI 扩展的全局规则
# *
# * 拓扑（两种目标形态，均为复制模式，无镜像层）:
# *   仓库 rules/AGENTS.md ──[cp]──▶ 各 agent 全局规则文件
# *   仓库 rules/AGENTS.md ──[front matter + cp]──▶ CodeBuddy 用户规则 RULE.mdc
# *
# *   复制而非软链的原因：目标多为「文件」，软链需要一个额外的链接层，
# *   且编辑器/工具重写源文件时容易断链；仓库改动后重跑 update 即可。
# *
# * CodeBuddy 说明：官方文档明确 CODEBUDDY.md 只在「项目根目录」被加载，
# *   ~/.codebuddy/CODEBUDDY.md 不是有效全局入口。其全局入口是用户规则
# *   ~/.codebuddy/rules/<规则>/RULE.mdc（front matter: description /
# *   alwaysApply / enabled）。仓库规则全文约 50 行，远低于官方 500 行/条
# *   的上限，故作为一条 always-apply 规则整体安装，不切片。
# *   旧版脚本残留的 ~/.codebuddy/CODEBUDDY.md 若与仓库源完全一致会被清理。
# *   规则只在「新开会话」后生效。
# *
# * 安全策略:
# *   install / update : 目标已存在且与仓库源不一致时逐个询问是否覆盖；
# *                      与源一致的跳过；不做备份，仓库 rules/AGENTS.md 即唯一源
# *   force            : 不询问，直接覆盖
# *   unlink           : 仅删除与仓库源一致的文件，改动过的一律不动
# *
# * 用法:
# *   ./linux-rules.sh install [工具] [force]   安装 / 刷新（省略工具 = 全部）
# *   ./linux-rules.sh update  [工具] [force]   同 install（肌肉记忆别名）
# *   ./linux-rules.sh unlink  [工具]           卸载（仅删与仓库源一致的文件）
# *   ./linux-rules.sh status                   查看安装状态
# *   ./linux-rules.sh help                     显示帮助
# *
# *   <工具> 取值: claude, zcode, opencode, codebuddy, dsh, all
# *   兼容 PowerShell 版写法：-install / -update / -link / -unlink / -status / -f
# * ======================================================

set -u

# ========================================================
# 脚本与路径
# ========================================================
SCRIPT_NAME=$(basename "$0")
SCRIPT_ABSOLUTE_PATH=$(cd "$(dirname "$0")" && pwd)

# 规则源文件（唯一真相）
SRC_FILE="${SCRIPT_ABSOLUTE_PATH}/rules/AGENTS.md"

# CodeBuddy 用户规则目标（单条 always-apply 规则）
CODEBUDDY_RULE_FILE="${HOME}/.codebuddy/rules/agents-rules/RULE.mdc"
# 旧版脚本残留的、CodeBuddy 从不加载的文件
CODEBUDDY_LEGACY_FILE="${HOME}/.codebuddy/CODEBUDDY.md"
# 规则描述（写入 front matter）
CODEBUDDY_RULE_DESC="工程规则：文件编码 / 画图技能选择 / 画图字号下限（源自仓库 rules/AGENTS.md，全文始终生效）"

# ========================================================
# 颜色与日志
# ========================================================
step()    { echo -e "\e[96m➤  $@\e[0m"; }
warning() { echo -e "⚠️  \e[33m$@\e[0m"; }
error()   { echo -e "❌ \e[31m$@\e[0m"; }
success() { echo -e "✅ \e[32m$@\e[0m"; }
info()    { echo -e "\e[32mℹ️ [INFO]\e[0m$@"; }
dim()     { echo -e "\e[90m$@\e[0m"; }

# ========================================================
# 工具配置表：键名 -> "目标路径|显示名称|模式"
#   模式 file  : 单个全局规则文件（整份 AGENTS.md 复制）
#   模式 rules : 目录形态的用户规则（RULE.mdc）
# 新增/删除工具只需改这里
# ========================================================
declare -A TOOLS
TOOLS[claude]="${HOME}/.claude/CLAUDE.md|Claude Code|file"
TOOLS[zcode]="${HOME}/.zcode/AGENTS.md|ZCode|file"
TOOLS[opencode]="${HOME}/.config/opencode/AGENTS.md|OpenCode|file"
TOOLS[codebuddy]="${CODEBUDDY_RULE_FILE}|CodeBuddy|rules"
TOOLS[dsh]="${HOME}/.dsh/AGENTS.md|DeepSeek Harness|file"

# 工具标识顺序（workbuddy 未查到全局规则文件的官方约定，暂不安装，skills 不受影响）
TOOL_KEYS=("claude" "zcode" "opencode" "codebuddy" "dsh")

get_tool_path() { local e="${TOOLS[$1]}"; echo "${e%%|*}"; }
get_tool_name() { local e="${TOOLS[$1]}"; local r="${e#*|}"; echo "${r%%|*}"; }
get_tool_mode() { local e="${TOOLS[$1]}"; echo "${e##*|}"; }

# ========================================================
# 前置校验
# ========================================================
check_source() {
    [ -f "${SRC_FILE}" ] && return 0
    error "规则源文件不存在: ${SRC_FILE}"
    return 1
}

validate_tool() {
    local t="$1"
    [ "$t" = "all" ] && return 0
    if [ -z "${TOOLS[$t]:-}" ]; then
        error "未知工具: ${t} (可用: ${TOOL_KEYS[*]}, all)"
        return 1
    fi
    return 0
}

# ========================================================
# CodeBuddy 用户规则：生成、比对、旧文件清理
# ========================================================

# 生成 RULE.mdc 内容到指定文件：front matter + AGENTS.md 全文（LF 归一）
write_codebuddy_rule() {
    local out="$1"
    {
        printf -- '---\n'
        printf 'description: %s\n' "${CODEBUDDY_RULE_DESC}"
        printf 'alwaysApply: true\n'
        printf 'enabled: true\n'
        printf -- '---\n\n'
        sed 's/\r$//' "${SRC_FILE}"
    } > "${out}"
}

# 已安装的 RULE.mdc 是否与仓库源一致（内容比对，按字节）
match_codebuddy_rule() {
    local dst="$1" tmp rc
    [ -f "${dst}" ] || return 1
    tmp=$(mktemp) || return 1
    write_codebuddy_rule "${tmp}"
    cmp -s "${tmp}" "${dst}"
    rc=$?
    rm -f "${tmp}"
    return ${rc}
}

# 旧版脚本把整份 AGENTS.md 写到 ~/.codebuddy/CODEBUDDY.md，
# 而 CodeBuddy 从不加载该路径。仅当文件与仓库源完全一致时删除。
remove_legacy_codebuddy_file() {
    [ -f "${CODEBUDDY_LEGACY_FILE}" ] || return 0
    if cmp -s "${SRC_FILE}" "${CODEBUDDY_LEGACY_FILE}"; then
        rm -f "${CODEBUDDY_LEGACY_FILE}"
        dim "    codebuddy : removed legacy file (never loaded by CodeBuddy): ${CODEBUDDY_LEGACY_FILE}"
    else
        warning "    codebuddy : legacy file kept (differs from repo source): ${CODEBUDDY_LEGACY_FILE}"
    fi
    return 0
}

# ========================================================
# 安装：单个工具的全局规则文件
#   不存在            -> 直接写入
#   与源一致          -> 静默跳过
#   不一致 + force    -> 直接覆盖
#   不一致 + 无 force -> 询问 [y/N]
# ========================================================
install_file_tool() {
    local key="$1" force="${2:-}"
    local dst; dst=$(get_tool_path "${key}")
    local dir; dir=$(dirname "${dst}")
    local answer

    mkdir -p "${dir}"

    if [ -f "${dst}" ]; then
        if cmp -s "${SRC_FILE}" "${dst}"; then
            dim "    ${key} : already up to date"
            return 0
        fi
        if [ "${force}" != "force" ]; then
            printf "    %s : exists and differs from repo source, overwrite? [y/N] " "${key}"
            read -r answer || answer=""
            if [[ ! "${answer}" =~ ^[Yy] ]]; then
                warning "    ${key} : skipped"
                return 0
            fi
        fi
        cp -f "${SRC_FILE}" "${dst}"
        success "    ${key} : updated  -> ${dst}"
        return 0
    fi

    cp -f "${SRC_FILE}" "${dst}"
    success "    ${key} : installed -> ${dst}"
    return 0
}

# ========================================================
# 安装：CodeBuddy 用户规则（单条 RULE.mdc，覆盖策略同文件模式）
# ========================================================
install_codebuddy_rule() {
    local key="$1" force="${2:-}"
    local dst="${CODEBUDDY_RULE_FILE}" tmp answer

    mkdir -p "$(dirname "${dst}")"
    tmp=$(mktemp) || { error "无法创建临时文件"; return 1; }
    write_codebuddy_rule "${tmp}"

    if [ -f "${dst}" ]; then
        if cmp -s "${tmp}" "${dst}"; then
            dim "    ${key} : already up to date"
        else
            if [ "${force}" != "force" ]; then
                printf "    %s : exists and differs from repo source, overwrite? [y/N] " "${key}"
                read -r answer || answer=""
                if [[ ! "${answer}" =~ ^[Yy] ]]; then
                    warning "    ${key} : skipped"
                    rm -f "${tmp}"
                    remove_legacy_codebuddy_file
                    return 0
                fi
            fi
            cp -f "${tmp}" "${dst}"
            success "    ${key} : updated  -> ${dst}"
        fi
    else
        cp -f "${tmp}" "${dst}"
        success "    ${key} : installed -> ${dst}"
    fi

    rm -f "${tmp}"
    remove_legacy_codebuddy_file
    dim "    ${key} : note: rules are loaded into NEW chat sessions only"
    return 0
}

install_tool() {
    local key="$1" force="${2:-}"
    if [ "$(get_tool_mode "${key}")" = "rules" ]; then
        install_codebuddy_rule "${key}" "${force}"
        return $?
    fi
    install_file_tool "${key}" "${force}"
}

install_all() {
    local force="${1:-}" k
    check_source || return 1
    step "installing rules to all tools..."
    echo ""
    for k in "${TOOL_KEYS[@]}"; do
        install_tool "${k}" "${force}"
    done
    echo ""
}

# ========================================================
# 卸载：仅删除与仓库源一致的文件，改动过的一律不动
# ========================================================
uninstall_tool() {
    local key="$1"
    local dst; dst=$(get_tool_path "${key}")
    local mode; mode=$(get_tool_mode "${key}")

    # rules 模式：目标是规则目录中的 RULE.mdc，一致时删除整个规则目录
    if [ "${mode}" = "rules" ]; then
        if [ ! -f "${dst}" ]; then
            dim "    ${key} : not installed"
        elif match_codebuddy_rule "${dst}"; then
            rm -rf "$(dirname "${dst}")"
            success "    ${key} : removed"
        else
            warning "    ${key} : skipped: differs from repo source (not ours to delete)"
        fi
        remove_legacy_codebuddy_file
        return 0
    fi

    if [ ! -f "${dst}" ]; then
        dim "    ${key} : not installed"
        return 0
    fi
    if cmp -s "${SRC_FILE}" "${dst}"; then
        rm -f "${dst}"
        success "    ${key} : removed"
    else
        warning "    ${key} : skipped: differs from repo source (not ours to delete)"
    fi
    return 0
}

uninstall_all() {
    local k
    check_source || return 1
    step "removing installed rules..."
    echo ""
    for k in "${TOOL_KEYS[@]}"; do
        uninstall_tool "${k}"
    done
    echo ""
}

# ========================================================
# 状态：源文件 + 各工具目标状态
# ========================================================
codebuddy_state() {
    if [ ! -f "${CODEBUDDY_RULE_FILE}" ]; then
        echo "missing"; return
    fi
    if match_codebuddy_rule "${CODEBUDDY_RULE_FILE}"; then
        echo "ok"
    else
        echo "differs"
    fi
}

show_status() {
    check_source || return 1
    step "rules status"
    echo ""
    dim "  source: ${SRC_FILE}"
    echo ""

    local k dst mode state
    for k in "${TOOL_KEYS[@]}"; do
        dst=$(get_tool_path "${k}")
        mode=$(get_tool_mode "${k}")

        if [ "${mode}" = "rules" ]; then
            state=$(codebuddy_state)
        elif [ ! -f "${dst}" ]; then
            state="missing"
        elif cmp -s "${SRC_FILE}" "${dst}"; then
            state="ok"
        else
            state="differs"
        fi

        printf "    %-10s " "${k}"
        case "${state}" in
            ok)      printf "\e[32m[ok]\e[0m" ;;
            differs) printf "\e[33m[differs]\e[0m" ;;
            missing) printf "\e[33m[missing]\e[0m" ;;
        esac
        printf " %s\n" "${dst}"
    done

    if [ -f "${CODEBUDDY_LEGACY_FILE}" ]; then
        printf "    %-10s " "codebuddy"
        printf "\e[90m[note]\e[0m"
        printf " %s exists but is NOT loaded by CodeBuddy (legacy single-file install)\n" "${CODEBUDDY_LEGACY_FILE}"
    fi

    echo ""
    success "Legend: ok=matches repo  differs=exists but not current  missing=not installed"
    dim "  codebuddy target is one user rule: ~/.codebuddy/rules/agents-rules/RULE.mdc"
    dim "  rules are loaded into NEW chat sessions only"
    echo ""
}

# ========================================================
# 帮助
# ========================================================
usage() {
    cat <<EOF
用法: ./${SCRIPT_NAME} <命令> [工具] [force]

命令:
  install [工具] [force]   安装 / 刷新全局规则（省略工具 = 全部）
  update  [工具] [force]   同 install（仓库改动后重跑即可重新分发）
  unlink  [工具]           卸载（仅删与仓库源一致的文件）
  status                   查看安装状态
  help                     显示此帮助

工具: ${TOOL_KEYS[*]}, all
  claude     ~/.claude/CLAUDE.md
  zcode      ~/.zcode/AGENTS.md
  opencode   ~/.config/opencode/AGENTS.md
  codebuddy  ~/.codebuddy/rules/agents-rules/RULE.mdc  (用户规则, 非 CODEBUDDY.md)
  dsh        ~/.dsh/AGENTS.md

说明:
  - 复制模式，无镜像层；已存在且与仓库源不一致的目标会逐个询问，force 跳过询问
  - 不做备份，仓库 rules/AGENTS.md 即唯一源
  - CodeBuddy 的 ~/.codebuddy/CODEBUDDY.md 不是可加载的全局路径，
    旧版残留文件（与仓库源一致时）会被自动清理；规则只在新会话生效
  - 兼容 PowerShell 版写法: -install / -update / -link / -unlink / -status / -f

示例:
  ./${SCRIPT_NAME} install          # 安装 / 刷新全部
  ./${SCRIPT_NAME} install -f       # 不询问，直接覆盖
  ./${SCRIPT_NAME} link claude      # 仅安装 Claude Code
  ./${SCRIPT_NAME} unlink codebuddy # 卸载 CodeBuddy 用户规则
  ./${SCRIPT_NAME} status           # 查看状态
EOF
}

# ========================================================
# 参数解析
#   - 任意位置的 force / -f / --force 视为强制覆盖
#   - 命令兼容带前导 '-' 的 PowerShell 写法（-install -> install）
# ========================================================
FORCE=""
POSITIONAL=()
for arg in "$@"; do
    case "${arg}" in
        -f|--force|force) FORCE="force" ;;
        *) POSITIONAL+=("${arg}") ;;
    esac
done

CMD="${POSITIONAL[0]:-help}"
CMD="${CMD#-}"
ARG="${POSITIONAL[1]:-}"

# ========================================================
# 主入口
# ========================================================
case "${CMD}" in
    install|update)
        if [ -z "${ARG}" ] || [ "${ARG}" = "all" ]; then
            install_all "${FORCE}"
        else
            validate_tool "${ARG}" || exit 1
            check_source || exit 1
            echo ""
            step "installing rules..."
            echo ""
            install_tool "${ARG}" "${FORCE}"
            echo ""
        fi
        ;;
    link)
        if [ -z "${ARG}" ] || [ "${ARG}" = "all" ]; then
            install_all "${FORCE}"
        else
            validate_tool "${ARG}" || exit 1
            check_source || exit 1
            echo ""
            step "installing rules..."
            echo ""
            install_tool "${ARG}" "${FORCE}"
            echo ""
        fi
        ;;
    unlink|remove|rm|d)
        if [ -z "${ARG}" ] || [ "${ARG}" = "all" ]; then
            uninstall_all
        else
            validate_tool "${ARG}" || exit 1
            check_source || exit 1
            echo ""
            step "removing rules..."
            echo ""
            uninstall_tool "${ARG}"
            echo ""
        fi
        ;;
    status)
        show_status
        ;;
    help|h|"")
        usage
        ;;
    *)
        error "未知命令: ${CMD}"
        usage
        exit 1
        ;;
esac

exit $?
