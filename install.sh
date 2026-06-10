#!/bin/bash
# * =====================================================
# * Copyright © sumu. 2026-present. Tech. Co., Ltd. All rights reserved.
# * File name  : install.sh
# * Author     : 苏木
# * Date       : 2026/04/12
# * Version    : 2.0.0
# * Description: 安装 skills 到各 AI 扩展 (RooCode / Claude Code / CodeBuddy / OpenCode)
# * ======================================================

# ========================================================
# 脚本和工程路径
# ========================================================
SCRIPT_NAME=${0#*/}
SCRIPT_CURRENT_PATH=${0%/*}
SCRIPT_ABSOLUTE_PATH=$(cd $(dirname ${0}); pwd)

# ========================================================
# 颜色和日志标识
# ========================================================
# |      ---       |Black |  Red | Green | Yellow | Blue | Magenta | Cyan | White |
# | Fore(Standard) |  30  |  31  |  32   |   33   |  34  |   35    |  36  |   37  |
# | Fore(light)    |  90  |  91  |  92   |   93   |  94  |   95    |  96  |   97  |
# | Back(Standard) |  40  |  41  |  42   |   43   |  44  |   45    |  46  |   47  |
# | Back(light)    | 100  | 101  | 102   |  103   | 104  |  105    | 106  |  107  |
step() {
    echo -e "\e[96m➤  $@\e[0m"
}

warning() {
    echo -n "⚠️  "
    echo -e "\e[33m$@\e[0m"
}

error() {
    echo -n "❌ "
    echo -e "\e[31m$@\e[0m"
}

success() {
    echo -n "✅ "
    echo -e "\e[32m$@\e[0m"
}

info() {
    echo -ne "\e[32mℹ️ [INFO]\e[0m"
    echo -e "\e[0m$@\e[0m"
}

dim() {
    echo -e "\e[90m$@\e[0m"
}

# 目录切换函数定义
cdi() {
    if command -v pushd &>/dev/null; then
        pushd $1 >/dev/null || return 1
    else
        cd $1
    fi
}

cdo() {
    if command -v popd &>/dev/null; then
        popd >/dev/null || return 1
    else
        cd -
    fi
}

# ========================================================
# 全局配置
# ========================================================

# Skills 源目录 (脚本所在目录下的 skills/)
SKILLS_SRC_DIR="${SCRIPT_ABSOLUTE_PATH}/skills"

# ========================================================
# 工具配置表：键名为工具标识，值为 "安装路径|显示名称"
# 所有函数通过此表统一获取路径和名称，新增工具只需在此添加一行
# ========================================================
declare -A TOOLS
TOOLS[roocode]="${HOME}/.roo/skills|RooCode"
TOOLS[claude]="${HOME}/.claude/skills|Claude Code"
TOOLS[codebuddy]="${HOME}/.codebuddy/skills|CodeBuddy"
TOOLS[opencode]="${HOME}/.config/opencode/skills|OpenCode"

# 工具标识列表（保持顺序）
TOOL_KEYS=("roocode" "claude" "codebuddy" "opencode")

# ========================================================
# 工具配置查表函数
# ========================================================

# 根据工具标识获取安装路径
# 参数: $1 - 工具标识 (如 claude)
# 输出: 安装路径
get_tool_path() {
    local entry="${TOOLS[$1]}"
    echo "${entry%%|*}"
}

# 根据工具标识获取显示名称
# 参数: $1 - 工具标识 (如 claude)
# 输出: 显示名称
get_tool_name() {
    local entry="${TOOLS[$1]}"
    echo "${entry##*|}"
}

# ========================================================
# 获取所有技能目录名称列表 (仅返回子目录, 排除 skills/SKILL.md 等文件)
get_skill_names() {
    local names=()
    for item in "${SKILLS_SRC_DIR}"/*/; do
        [ ! -d "$item" ] && continue
        names+=("$(basename "$item")")
    done
    echo "${names[@]}"
}

# 从 SKILL.md 的 front matter 中提取 description 字段
# 参数: $1 - SKILL.md 文件路径
# 输出: description 内容
get_skill_description() {
    local skill_file="$1"
    if [ -f "${skill_file}" ]; then
        # 读取 front matter 中 description 行
        sed -n '/^---$/,/^---$/ s/^[[:space:]]*description:[[:space:]]*\(.*\)[[:space:]]*$/\1/p' "${skill_file}" | head -1
    fi
}

# ========================================================
# 安装技能到指定工具（通用函数，通过查表获取路径和名称）
# 参数: $1 - 工具标识 (如 claude)
#       $2 - 是否强制覆盖 (force)
# ========================================================
install_skills_to() {
    local tool_key="$1"
    local force="$2"
    local dst_dir=$(get_tool_path "${tool_key}")
    local tool_name=$(get_tool_name "${tool_key}")

    step "installing skills to ${tool_name} (${dst_dir})..."

    # 检查源目录
    if [ ! -d "${SKILLS_SRC_DIR}" ]; then
        error "skills source directory not found: ${SKILLS_SRC_DIR}"
        return 1
    fi

    # 创建目标目录
    mkdir -p "${dst_dir}"

    local skill_names=$(get_skill_names)
    local count=0
    local skipped=0

    for skill_name in ${skill_names}; do
        local src="${SKILLS_SRC_DIR}/${skill_name}"
        local dst="${dst_dir}/${skill_name}"

        # 跳过非目录项
        [ ! -d "${src}" ] && continue

        # 目标已存在
        if [ -d "${dst}" ]; then
            if [ "${force}" = "force" ]; then
                # 强制模式：直接覆盖
                rm -rf "${dst}"
                cp -rf "${src}" "${dst}"
                warning " ${skill_name} overwritten"
                count=$((count + 1))
            else
                # 交互模式：询问用户是否覆盖
                read -p "    ${skill_name} already exists, overwrite? [y/N] " answer
                if [ "${answer}" = "y" ] || [ "${answer}" = "Y" ]; then
                    rm -rf "${dst}"
                    cp -rf "${src}" "${dst}"
                    warning " ${skill_name} overwritten"
                    count=$((count + 1))
                else
                    dim "    ${skill_name} skipped"
                    skipped=$((skipped + 1))
                fi
            fi
        else
            # 目标不存在，直接安装
            cp -rf "${src}" "${dst}"
            success " ${skill_name} installed"
            count=$((count + 1))
        fi
    done

    local skip_info=""
    if [ ${skipped} -gt 0 ]; then
        skip_info=", ${skipped} skipped"
    fi
    success "${tool_name}: ${count} skill(s) installed${skip_info}."
}

# ========================================================
# 安装到所有 AI 扩展
# 参数: $1 - 是否强制覆盖 (force)
# ========================================================
install_to_all() {
    local force="${1:-}"
    for key in "${TOOL_KEYS[@]}"; do
        install_skills_to "${key}" "${force}" || return 1
        echo ""
    done
}

# ========================================================
# 删除指定工具下的所有技能（通用函数，通过查表获取路径和名称）
# 参数: $1 - 工具标识 (如 claude)
# ========================================================
remove_skills_from() {
    local tool_key="$1"
    local dst_dir=$(get_tool_path "${tool_key}")
    local tool_name=$(get_tool_name "${tool_key}")

    step "removing skills from ${tool_name} (${dst_dir})..."

    # 目录不存在则提示
    if [ ! -d "${dst_dir}" ]; then
        warning "skills directory not found: ${dst_dir}"
        return 0
    fi

    local count=0
    for item in "${dst_dir}"/*/; do
        [ ! -d "$item" ] && continue
        rm -rf "${item}"
        warning " removed $(basename "${item}")"
        count=$((count + 1))
    done

    if [ ${count} -eq 0 ]; then
        warning "no skills to remove in ${dst_dir}"
    else
        success "${tool_name}: ${count} skill(s) removed."
    fi
}

# ========================================================
# 删除所有工具下的技能
# ========================================================
remove_all() {
    for key in "${TOOL_KEYS[@]}"; do
        remove_skills_from "${key}"
        echo ""
    done
}

# ========================================================
# 显示已安装的技能状态（通用函数，通过查表获取路径和名称）
# ========================================================
show_status() {
    step "skills installation status"
    echo ""

    local skill_names=$(get_skill_names)

    # 源目录技能列表
    step "Available skills (${SKILLS_SRC_DIR}):"
    for skill_name in ${skill_names}; do
        local desc=$(get_skill_description "${SKILLS_SRC_DIR}/${skill_name}/SKILL.md")
        if [ -n "${desc}" ]; then
            printf "  %-16s %s\n" "${skill_name}" "${desc}"
        else
            printf "  %-16s (no description)\n" "${skill_name}"
        fi
    done
    echo ""

    # 各工具安装状态
    local total=0
    for key in "${TOOL_KEYS[@]}"; do
        local dst_dir=$(get_tool_path "${key}")
        local tool_name=$(get_tool_name "${key}")
        local installed=0

        step "${tool_name} (${dst_dir}):"
        for skill_name in ${skill_names}; do
            if [ -d "${dst_dir}/${skill_name}" ]; then
                success "${skill_name}"
                installed=$((installed + 1))
            else
                error "${skill_name} (not installed)"
            fi
        done
        total=$((total + installed))
        echo ""
    done

    success "Total: ${total} skill(s) installed across all tools."
}

# ========================================================
# 列出指定工具中已安装的技能（通用函数，通过查表获取路径和名称）
# 参数: $1 - 工具标识 (如 claude)
# ========================================================
list_skills_of() {
    local tool_key="$1"
    local dst_dir=$(get_tool_path "${tool_key}")
    local tool_name=$(get_tool_name "${tool_key}")

    info "${tool_name} (${dst_dir})"

    if [ ! -d "${dst_dir}" ]; then
        echo "  No skills found"
        return
    fi

    local count=0
    for item in "${dst_dir}"/*/; do
        [ ! -d "$item" ] && continue
        local skill_name=$(basename "${item}")
        local desc=$(get_skill_description "${item}/SKILL.md")
        if [ -n "${desc}" ]; then
            printf "  %-16s %s\n" "${skill_name}" "${desc}"
        else
            printf "  %-16s (no description)\n" "${skill_name}"
        fi
        count=$((count + 1))
    done

    if [ ${count} -eq 0 ]; then
        echo "  No skills found"
    else
        echo ""
        echo "  Total: ${count} skill(s)"
    fi
}

# ========================================================
# 列出所有工具中已安装的技能
# ========================================================
list_all_skills() {
    local total=0
    for key in "${TOOL_KEYS[@]}"; do
        echo ""
        list_skills_of "${key}"
        echo ""
    done
}

# ========================================================
# 打印菜单
do_echo_menu() {
    echo "================================================="
    echo -e "           Skills Installer for AI Extensions"
    echo "================================================="
    echo -e "SKILLS_SRC_DIR      :${SKILLS_SRC_DIR}"
    for key in "${TOOL_KEYS[@]}"; do
        local tool_name=$(get_tool_name "${key}")
        local dst_dir=$(get_tool_path "${key}")
        printf "%-20s:%s\n" "${tool_name}" "${dst_dir}"
    done
    echo -e "SCRIPT_ABSOLUTE_PATH:${SCRIPT_ABSOLUTE_PATH}"
    echo -e "SHELL_PARAM         :($# total)arg=$*"
    echo ""
    echo "================================================="
}

# ========================================================
# 用法说明
usage() {
    echo "用法: ${SCRIPT_NAME} <命令> [参数]"
    echo ""
    echo "命令:"
    echo "  install <tool> [force]  安装技能到指定工具 (加 force 强制覆盖)"
    echo "  remove <tool>           删除指定工具的所有技能"
    echo "  list [tool]             列出已安装的技能（不指定工具则列出全部）"
    echo "  status                  显示安装状态"
    echo "  help                    显示此帮助信息"
    echo ""
    echo "快捷命令 (兼容旧版):"
    echo "  <tool> [force]          安装技能到指定工具 (如 ./install.sh claude force)"
    echo "  all [force]             安装到所有工具"
    echo "  uninstall               卸载所有已安装的技能"
    echo ""
    echo "工具名:"
    for key in "${TOOL_KEYS[@]}"; do
        local tool_name=$(get_tool_name "${key}")
        local dst_dir=$(get_tool_path "${key}")
        printf "  %-12s %s\n" "${key}" "${dst_dir}"
    done
    echo ""
    echo "无参数运行时进入交互式菜单"
}

# ========================================================
# 验证工具标识是否有效
# 参数: $1 - 工具标识
# 返回: 0=有效, 1=无效
validate_tool() {
    local tool="$1"
    if [ "${tool}" = "all" ]; then
        return 0
    fi
    if [ -z "${TOOLS[$tool]}" ]; then
        error "未知工具: ${tool} (可用: ${TOOL_KEYS[*]}, all)"
        return 1
    fi
    return 0
}

# ========================================================
# 交互式菜单
interactive_menu() {
    do_echo_menu "$@"

    echo "请选择操作:"
    echo "  1) 安装到所有 AI 扩展"
    local idx=2
    for key in "${TOOL_KEYS[@]}"; do
        local tool_name=$(get_tool_name "${key}")
        echo "  ${idx}) 安装到 ${tool_name}"
        idx=$((idx + 1))
    done
    echo "  ${idx}) 列出已安装技能";  list_idx=${idx}; idx=$((idx + 1))
    echo "  ${idx}) 显示安装状态";    status_idx=${idx}; idx=$((idx + 1))
    echo "  ${idx}) 卸载所有技能";     uninstall_idx=${idx}; idx=$((idx + 1))
    echo "  0) 退出"
    echo ""
    read -p "请输入选项 [0-${idx}]: " choice

    case ${choice} in
        1) install_to_all ;;
        0) echo "退出"; exit 0 ;;
        ${list_idx}) list_all_skills ;;
        ${status_idx}) show_status ;;
        ${uninstall_idx}) remove_all ;;
        *)
            # 动态匹配各工具选项
            local tool_idx=2
            for key in "${TOOL_KEYS[@]}"; do
                if [ "${choice}" = "${tool_idx}" ]; then
                    install_skills_to "${key}" ""
                    exit $?
                fi
                tool_idx=$((tool_idx + 1))
            done
            error "无效选项: ${choice}"
            exit 1
            ;;
    esac
}

# ========================================================
# 主入口
do_echo_menu "$@"

# 解析命令：支持 "install claude" 和旧版 "claude" 两种风格
case "$1" in
    install|i)
        # 新版命令: install <tool> [force]
        if [ -z "$2" ]; then
            error "请指定工具名"
            usage
            exit 1
        fi
        validate_tool "$2" || exit 1
        if [ "$2" = "all" ]; then
            install_to_all "$3"
        else
            install_skills_to "$2" "$3"
        fi
        ;;
    remove|rm|uninstall|un)
        # 新版命令: remove <tool>
        if [ -z "$2" ]; then
            error "请指定工具名"
            usage
            exit 1
        fi
        validate_tool "$2" || exit 1
        if [ "$2" = "all" ]; then
            remove_all
        else
            remove_skills_from "$2"
        fi
        ;;
    list)
        # 新版命令: list [tool]
        if [ -z "$2" ] || [ "$2" = "all" ]; then
            list_all_skills
        else
            validate_tool "$2" || exit 1
            list_skills_of "$2"
        fi
        ;;
    status)
        show_status
        ;;
    help|--help|-h)
        usage
        ;;
    "")
        interactive_menu "$@"
        ;;
    roocode|claude|codebuddy|opencode|all)
        # 旧版命令兼容: 直接传工具名即为安装，可选 force 强制覆盖
        if [ "$1" = "all" ]; then
            install_to_all "$2"
        else
            install_skills_to "$1" "$2"
        fi
        ;;
    uninstall|un)
        # 旧版命令兼容: uninstall 卸载全部
        remove_all
        ;;
    *)
        error "未知选项: $1"
        usage
        exit 1
        ;;
esac

exit $?
