#!/bin/bash
# * =====================================================
# * Copyright © sumu. 2026-present. Tech. Co., Ltd. All rights reserved.
# * File name  : linux-skills.sh
# * Author     : 苏木
# * Date       : 2026/06/28
# * Version    : 1.1.0
# * Description: 在 Linux 下用「符号链接」安装 skills 到各 AI 扩展
# *
# * 拓扑（解耦仓库路径与 agent 链接）:
# *   仓库 skills/  ──[update 覆盖]──▶  ~/.smskills/  ──[link 软链接]──▶  各 agent 工具
# *
# *   - update : 把仓库 skills/ 镜像覆盖到 ~/.smskills/（真实拷贝）
# *   - link   : 把 ~/.smskills/<skill> 软链接到各 agent 工具
# *   - 仓库挪动/重命名只需重新 update，agent 链接不断
# * ======================================================

set -u

# ========================================================
# 脚本与目录
# ========================================================
SCRIPT_NAME=$(basename "$0")
SCRIPT_ABSOLUTE_PATH=$(cd "$(dirname "$0")" && pwd)

# 仓库 skills 源目录（update 的读取来源）
REPO_SKILLS_DIR="${SCRIPT_ABSOLUTE_PATH}/skills"

# 本地 skills 镜像目录（update 的目标，link 的来源）
# agent 工具全部链接到这里，而非仓库，实现路径解耦
SMSKILLS_DIR="${HOME}/.smskills"

# ========================================================
# 颜色与日志
# ========================================================
# |      ---       |Black |  Red | Green | Yellow | Blue | Magenta | Cyan | White |
# | Fore(Standard) |  30  |  31  |  32   |   33   |  34  |   35    |  36  |   37  |
# | Fore(light)    |  90  |  91  |  92   |   93   |  94  |   95    |  96  |   97  |
step()    { echo -e "\e[96m➤  $@\e[0m"; }
warning() { echo -e "⚠️  \e[33m$@\e[0m"; }
error()   { echo -e "❌ \e[31m$@\e[0m"; }
success() { echo -e "✅ \e[32m$@\e[0m"; }
info()    { echo -e "\e[32mℹ️ [INFO]\e[0m$@"; }
dim()     { echo -e "\e[90m$@\e[0m"; }

# ========================================================
# 工具配置表：键名 -> "安装路径|显示名称"
# 新增/删除工具只需改这里
# ========================================================
declare -A TOOLS
TOOLS[claude]="${HOME}/.claude/skills|Claude Code"
TOOLS[roo]="${HOME}/.roo/skills|RooCode"
TOOLS[zcode]="${HOME}/.zcode/skills|ZCode"
TOOLS[opencode]="${HOME}/.config/opencode/skills|OpenCode"
# 如需 CodeBuddy，取消下一行注释：
# TOOLS[codebuddy]="${HOME}/.codebuddy/skills|CodeBuddy"

# 工具标识顺序
TOOL_KEYS=("claude" "roo" "zcode" "opencode")

# 查表
get_tool_path() { local e="${TOOLS[$1]}"; echo "${e%%|*}"; }
get_tool_name() { local e="${TOOLS[$1]}"; echo "${e##*|}"; }

# ========================================================
# 获取指定目录下所有 skill 子目录名
# 参数: $1 - 要扫描的目录（仓库 或 ~/.smskills）
# ========================================================
get_skill_names() {
    local base="${1:-${SMSKILLS_DIR}}"
    [ -d "$base" ] || return 0
    local item n
    for item in "${base}"/*/; do
        [ -d "$item" ] || continue
        n=$(basename "$item")
        echo "$n"
    done
}

# 从 SKILL.md front matter 提取 description
get_skill_description() {
    local f="$1"
    [ -f "$f" ] || return 0
    sed -n '/^---$/,/^---$/ s/^[[:space:]]*description:[[:space:]]*\(.*\)[[:space:]]*$/\1/p' "$f" | head -1
}

# ========================================================
# update：把仓库 skills/ 镜像覆盖到 ~/.smskills/
# ~/.smskills 是仓库的本地镜像：仓库有的覆盖/新增，仓库没有的（孤儿）删除
# ========================================================
update_skills() {
    step "updating ${SMSKILLS_DIR} from repo (${REPO_SKILLS_DIR})..."

    if [ ! -d "${REPO_SKILLS_DIR}" ]; then
        error "仓库 skills 源目录不存在: ${REPO_SKILLS_DIR}"
        return 1
    fi

    mkdir -p "${SMSKILLS_DIR}"

    local updated=0 added=0 orphan=0 name repo_dir dst_dir

    # 1) 同步：仓库有的覆盖/新增到 ~/.smskills
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        repo_dir="${REPO_SKILLS_DIR}/${name}"
        dst_dir="${SMSKILLS_DIR}/${name}"

        local existed=0
        if [ -e "${dst_dir}" ] || [ -L "${dst_dir}" ]; then
            # ~/.smskills 下若意外存在软链接，先删链接；否则删真实目录
            rm -rf "${dst_dir}"
            existed=1
        fi

        if cp -r "${repo_dir}" "${dst_dir}"; then
            if [ ${existed} -eq 1 ]; then
                success "    ${name} updated"
                updated=$((updated + 1))
            else
                success "    ${name} added"
                added=$((added + 1))
            fi
        else
            error "    ${name} 拷贝失败"
        fi
    done < <(get_skill_names "${REPO_SKILLS_DIR}")

    # 2) 清理孤儿：~/.smskills 有但仓库已没有的
    for item in "${SMSKILLS_DIR}"/*/; do
        [ -d "$item" ] || continue
        name=$(basename "$item")
        if [ ! -d "${REPO_SKILLS_DIR}/${name}" ]; then
            rm -rf "${SMSKILLS_DIR}/${name}"
            warning "    ${name} removed (no longer in repo)"
            orphan=$((orphan + 1))
        fi
    done

    success "mirror done: ${added} added, ${updated} updated, ${orphan} orphan removed."
    dim "    ${SMSKILLS_DIR} 现为仓库的完整镜像。"
}

# ========================================================
# 判断路径是否为指向期望源的正确软链
# 参数: $1=目标路径 $2=期望源路径
# 返回: 0=正确软链, 1=否
# ========================================================
is_correct_symlink() {
    local p="$1" want="$2"
    [ -L "$p" ] || return 1
    [ "$(readlink "$p")" = "$want" ]
}

# ========================================================
# 确保本地镜像存在；不存在则提示先 update
# ========================================================
ensure_mirror() {
    if [ ! -d "${SMSKILLS_DIR}" ] || [ -z "$(get_skill_names "${SMSKILLS_DIR}")" ]; then
        error "本地镜像为空: ${SMSKILLS_DIR}"
        error "请先运行: ./${SCRIPT_NAME} update  (或 ./${SCRIPT_NAME} install)"
        return 1
    fi
    return 0
}

# ========================================================
# 为单个工具创建符号链接（源 = ~/.smskills）
# 参数: $1=工具标识  $2=force(可选, 覆盖真实目录)
# ========================================================
link_tool() {
    local tool_key="$1" force="${2:-}"
    local dst_dir src_skill dst_skill name
    dst_dir=$(get_tool_path "$tool_key")
    local tool_name; tool_name=$(get_tool_name "$tool_key")

    step "linking skills to ${tool_name} (${dst_dir})..."

    ensure_mirror || return 1

    mkdir -p "${dst_dir}"

    local created=0 skipped=0
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        src_skill="${SMSKILLS_DIR}/${name}"
        dst_skill="${dst_dir}/${name}"

        if is_correct_symlink "${dst_skill}" "${src_skill}"; then
            dim "    ${name} already linked"
            skipped=$((skipped + 1))
            continue
        fi

        # 已存在（错误软链 / 真实目录）
        if [ -e "${dst_skill}" ] || [ -L "${dst_skill}" ]; then
            if [ -L "${dst_skill}" ]; then
                # 错误目标的软链：删链接重建（不影响源）
                rm -f "${dst_skill}"
            elif [ "${force}" = "force" ]; then
                # 真实目录 + force：删除拷贝后建链
                rm -rf "${dst_skill}"
                warning "    ${name} existing copy removed (force)"
            else
                warning "    ${name} is a real dir, skipped (use force to replace)"
                skipped=$((skipped + 1))
                continue
            fi
        fi

        if ln -s "${src_skill}" "${dst_skill}"; then
            success "    ${name} linked -> ${src_skill}"
            created=$((created + 1))
        else
            error "    ${name} symlink 创建失败"
        fi
    done < <(get_skill_names "${SMSKILLS_DIR}")

    success "${tool_name}: ${created} linked, ${skipped} skipped."
}

link_all() {
    local force="${1:-}"
    for k in "${TOOL_KEYS[@]}"; do
        link_tool "$k" "$force" || return 1
        echo ""
    done
}

# ========================================================
# install：一键 = update + link all（首次安装便捷命令）
# ========================================================
install_all() {
    local force="${1:-}"
    update_skills || return 1
    echo ""
    link_all "$force"
}

# ========================================================
# 删除工具下的 skills 软链接（仅删链接，不动 ~/.smskills 源）
# 真实目录一律跳过，避免误删用户数据
# ========================================================
unlink_tool() {
    local tool_key="$1"
    local dst_dir name dst_skill
    dst_dir=$(get_tool_path "$tool_key")
    local tool_name; tool_name=$(get_tool_name "$tool_key")

    step "unlinking skills from ${tool_name} (${dst_dir})..."

    if [ ! -d "${dst_dir}" ]; then
        warning "skills directory not found: ${dst_dir}"
        return 0
    fi

    local count=0
    for item in "${dst_dir}"/*/; do
        [ -d "$item" ] || [ -L "${item%/}" ] || continue
        name=$(basename "${item%/}")
        dst_skill="${dst_dir}/${name}"
        if [ -L "${dst_skill}" ]; then
            rm -f "${dst_skill}"
            success "    ${name} unlinked"
            count=$((count + 1))
        else
            warning "    ${name} is a real dir, skipped (not a link)"
        fi
    done

    if [ ${count} -eq 0 ]; then
        warning "no symlinks to remove in ${dst_dir}"
    else
        success "${tool_name}: ${count} symlink(s) removed."
    fi
}

unlink_all() {
    for k in "${TOOL_KEYS[@]}"; do
        unlink_tool "$k"
        echo ""
    done
}

# ========================================================
# 链接状态矩阵（基准 = ~/.smskills）
# ========================================================
show_status() {
    step "skills status"
    echo ""
    dim "  repo source : ${REPO_SKILLS_DIR}"
    dim "  local mirror: ${SMSKILLS_DIR}"
    echo ""

    local names
    names=$(get_skill_names "${SMSKILLS_DIR}")
    if [ -z "${names}" ]; then
        warning "本地镜像为空，请先运行: ./${SCRIPT_NAME} update"
        return 0
    fi

    # 动态计算 skill 列宽：最长 skill 名 + 余量；工具列固定宽
    local skill_w=18 col_w=10 nlen
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        nlen=${#name}
        [ $nlen -ge $skill_w ] && skill_w=$((nlen + 2))
    done <<< "${names}"

    printf "  %-${skill_w}s" "skill"
    for k in "${TOOL_KEYS[@]}"; do printf "%-${col_w}s" "$k"; done
    printf "\n"

    while IFS= read -r name; do
        [ -z "$name" ] && continue
        printf "  %-${skill_w}s" "${name}"
        for k in "${TOOL_KEYS[@]}"; do
            local dst; dst=$(get_tool_path "$k")"/${name}"
            local src="${SMSKILLS_DIR}/${name}"
            local cell="-"
            if is_correct_symlink "${dst}" "${src}"; then
                cell="LINK"
            elif [ -L "${dst}" ]; then
                cell="link?"
            elif [ -d "${dst}" ]; then
                cell="copy"
            fi
            printf "%-${col_w}s" "${cell}"
        done
        printf "\n"
    done <<< "${names}"

    echo ""
    success "Legend: LINK=正确软链  link?=软链但目标错  copy=真实目录  -=未安装"
}

# ========================================================
# 列出工具已安装的 skills
# ========================================================
list_tool() {
    local tool_key="$1"
    local dst_dir; dst_dir=$(get_tool_path "$tool_key")
    local tool_name; tool_name=$(get_tool_name "$tool_key")

    info "${tool_name} (${dst_dir})"
    if [ ! -d "${dst_dir}" ]; then
        echo "  No skills found"
        return
    fi

    local count=0 tag desc
    for item in "${dst_dir}"/*/; do
        [ -d "$item" ] || [ -L "${item%/}" ] || continue
        local n; n=$(basename "${item%/}")
        if [ -L "${dst_dir}/${n}" ]; then tag="[link] "; else tag="[copy] "; fi
        desc=$(get_skill_description "${dst_dir}/${n}/SKILL.md")
        if [ -n "${desc}" ]; then
            printf "  %-16s %s%s\n" "$n" "$tag" "$desc"
        else
            printf "  %-16s %s(no description)\n" "$n" "$tag"
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

list_all() {
    for k in "${TOOL_KEYS[@]}"; do
        echo ""
        list_tool "$k"
        echo ""
    done
}

# ========================================================
# 帮助
# ========================================================
usage() {
    cat <<EOF
用法: ./${SCRIPT_NAME} <命令> [工具] [选项]

命令:
  install [force]         一键安装：update + link all（推荐首次使用）
  update                  把仓库 skills/ 镜像覆盖到 ${SMSKILLS_DIR}
  link   [tool] [force]   把 ${SMSKILLS_DIR}/<skill> 软链接到各 agent 工具
                          不指定工具则全部；真实目录需加 force 才替换
  unlink [tool]           删除工具的符号链接（仅删链接，源不动）
  list   [tool]           列出已安装 skills（带 link/copy 标记）
  status                 显示链接状态矩阵
  help                   显示此帮助

工具: ${TOOL_KEYS[*]}, all

拓扑:
  仓库 skills/ ──[update]──▶ ${SMSKILLS_DIR} ──[link]──▶ 各 agent 工具
  仓库挪动后只需重新 update，agent 链接不会断。

示例:
  ./${SCRIPT_NAME} install         # 首次：镜像 + 全员链接
  ./${SCRIPT_NAME} update          # 仓库改动后，刷新本地镜像（agent 即时生效）
  ./${SCRIPT_NAME} link all force  # 强制用软链替换已存在的真实目录
  ./${SCRIPT_NAME} status          # 查看链接矩阵
  ./${SCRIPT_NAME} unlink roo      # 删除 RooCode 的软链接
EOF
}

# ========================================================
# 校验工具标识
# ========================================================
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
# 主入口
# ========================================================
case "${1:-}" in
    install)
        install_all "${2:-}"
        ;;
    update)
        update_skills
        ;;
    link)
        if [ -z "${2:-}" ] || [ "${2:-}" = "all" ]; then
            link_all "${3:-}"
        else
            validate_tool "$2" || exit 1
            link_tool "$2" "${3:-}"
        fi
        ;;
    unlink)
        if [ -z "${2:-}" ] || [ "${2:-}" = "all" ]; then
            unlink_all
        else
            validate_tool "$2" || exit 1
            unlink_tool "$2"
        fi
        ;;
    list)
        if [ -z "${2:-}" ] || [ "${2:-}" = "all" ]; then
            list_all
        else
            validate_tool "$2" || exit 1
            list_tool "$2"
        fi
        ;;
    status)
        show_status
        ;;
    help|--help|-h|"")
        usage
        ;;
    *)
        error "未知选项: ${1:-}"
        usage
        exit 1
        ;;
esac

exit $?
