# ========================================================
# Rules Installer for AI Extensions (Windows)
# Install repo rules/AGENTS.md into each agent's GLOBAL instruction file
# (user scope, loaded in every project).
#
# Topology (two target shapes, both copy mode — no mirror layer needed):
#   repo rules/AGENTS.md  ──[copy]──▶  each agent's global rules FILE
#   repo rules/AGENTS.md  ──[slice + copy]──▶  CodeBuddy user RULE.mdc files
#
# Why copy (not junction/link):
#   - Targets are FILES; junctions are dir-only, file symlinks need admin
#     rights, hardlinks break when editors/git replace the source file.
#   - Re-run -update after repo changes.
#
# CodeBuddy is the exception: per its docs, CODEBUDDY.md is only read from a
# PROJECT root, so ~/.codebuddy/CODEBUDDY.md is never loaded. Its global entry
# is user rules at ~/.codebuddy/rules/<rule>/RULE.mdc (front matter fields:
# description / alwaysApply / enabled). The repo rules total ~50 lines — well
# under the 500-line-per-rule guidance — so they ship as ONE always-apply rule
# (whole AGENTS.md verbatim) instead of being sliced. A legacy
# ~/.codebuddy/CODEBUDDY.md left by older script versions is auto-removed, but
# only while byte-identical to the repo source.
#
# Safety:
#   -install / -update : a target that exists and DIFFERS from the repo source
#                        asks for confirmation before being overwritten; a target
#                        already identical to the source is skipped silently.
#                        No backup is made — repo rules/AGENTS.md is the source of truth.
#   -f          : force — overwrite without asking
#   -unlink  : removes installed files ONLY if they match the repo source
#
# Target map (user-global scope, each path verified against agent docs):
#   claude     ~/.claude/CLAUDE.md               Claude Code user memory
#   zcode      ~/.zcode/AGENTS.md
#   opencode   ~/.config/opencode/AGENTS.md
#   codebuddy  ~/.codebuddy/rules/agents-rules/RULE.mdc  CodeBuddy user rule (whole AGENTS.md)
#   dsh        ~/.dsh/AGENTS.md                  DeepSeek Harness
#   workbuddy  — no documented global rules file, skipped (skills only)
#
# Param reference:
#   -h              Show help
#   -status         Show install status
#   -install        Copy to all tools (asks before overwriting differing targets)
#   -update         Same as -install (muscle-memory alias)
#   -link   <tool>  Copy to one tool (asks before overwriting differing targets)
#   -f              Force: overwrite without asking
#   -unlink <tool>  Remove installed file if it matches repo source
#   -d      <tool>  Alias of -unlink
#
#   <tool> values: claude, zcode, opencode, codebuddy, dsh, all
# ========================================================

[CmdletBinding()]
param(
    [switch]$h,
    [switch]$status,
    [switch]$install,
    [switch]$update,
    [switch]$f,
    [ValidateSet("claude", "zcode", "opencode", "codebuddy", "dsh", "all")]
    [string]$d,
    [ValidateSet("claude", "zcode", "opencode", "codebuddy", "dsh", "all")]
    [string]$unlink,
    [ValidateSet("claude", "zcode", "opencode", "codebuddy", "dsh", "all")]
    [string]$link
)

# ========================================================
# Global config
# ========================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Repo rules source (single file)
$script:srcFile = if ($PSScriptRoot) { Join-Path $PSScriptRoot "rules\AGENTS.md" } elseif ($MyInvocation.MyCommand.Path) { Join-Path (Split-Path $MyInvocation.MyCommand.Path) "rules\AGENTS.md" } else { $null }

# Tool table: key -> @{ Path=target; Name=display name; Mode=file|rules }
#   Mode "file"  : single global instruction file (whole copy of rules/AGENTS.md)
#   Mode "rules" : per-rule folders with RULE.mdc (CodeBuddy user rules)
$script:tools = [ordered]@{
    claude    = @{ Path = Join-Path $env:USERPROFILE ".claude\CLAUDE.md";          Name = "Claude Code";      Mode = "file" }
    zcode     = @{ Path = Join-Path $env:USERPROFILE ".zcode\AGENTS.md";           Name = "ZCode";            Mode = "file" }
    opencode  = @{ Path = Join-Path $env:USERPROFILE ".config\opencode\AGENTS.md"; Name = "OpenCode";         Mode = "file" }
    codebuddy = @{ Path = Join-Path $env:USERPROFILE ".codebuddy\rules\agents-rules"; Name = "CodeBuddy";      Mode = "rules" }
    dsh       = @{ Path = Join-Path $env:USERPROFILE ".dsh\AGENTS.md";             Name = "DeepSeek Harness"; Mode = "file" }
}

# ========================================================
# Helper: byte-exact file comparison via hash (used by -status / -unlink)
# ========================================================
function Test-FileSame {
    param([string]$A, [string]$B)
    if (-not (Test-Path -LiteralPath $A) -or -not (Test-Path -LiteralPath $B)) { return $false }
    $ha = Get-FileHash -LiteralPath $A -Algorithm SHA256
    $hb = Get-FileHash -LiteralPath $B -Algorithm SHA256
    return ($ha.Hash -eq $hb.Hash)
}

# ========================================================
# CodeBuddy user rule: the WHOLE rules/AGENTS.md as ONE always-apply rule.
# CodeBuddy docs: user rules live at ~/.codebuddy/rules/<rule>/RULE.mdc with
# front matter (description / alwaysApply / enabled). The repo rules total
# ~50 lines — far below the 500-line-per-rule guidance, and the "3-5 core
# rules" advice targets large rule sets — so a single rule wins: no slicing
# anchors to drift, AGENTS.md stays the exact source of truth.
# ========================================================
$script:codebuddyRuleFile = Join-Path $script:tools["codebuddy"].Path "RULE.mdc"

# Full RULE.mdc text: front matter + verbatim AGENTS.md body, LF endings.
# Deterministic (no timestamps) so -status / -unlink can compare content
# against what was installed.
function Get-CodeBuddyRuleContent {
    $body = [System.IO.File]::ReadAllText($script:srcFile, [System.Text.Encoding]::UTF8)
    $body = $body -replace "`r`n", "`n" -replace "`r", "`n"
    $desc = "工程规则：文件编码 / 画图技能选择 / 画图字号下限（源自仓库 rules/AGENTS.md，全文始终生效）"
    return "---`ndescription: $desc`nalwaysApply: true`nenabled: true`n---`n`n$body"
}

# Write text as UTF-8 without BOM, LF endings (per the repo's own encoding rules).
function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

# Compare an installed file against expected content (EOL-insensitive).
function Test-ContentSame {
    param([string]$Path, [string]$Expected)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $actual = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    $actual = $actual -replace "`r`n", "`n" -replace "`r", "`n"
    $expect = $Expected -replace "`r`n", "`n" -replace "`r", "`n"
    return $actual -eq $expect
}

# Legacy cleanup: older script versions wrote the whole AGENTS.md to
# ~/.codebuddy/CODEBUDDY.md, which CodeBuddy never loads (CODEBUDDY.md is only
# read from a project root). Remove it — but only while byte-identical to the
# repo source; anything else is not ours to delete.
function Remove-LegacyCodebuddyFile {
    $legacy = Join-Path $env:USERPROFILE ".codebuddy\CODEBUDDY.md"
    if (-not (Test-Path -LiteralPath $legacy)) { return }
    if (Test-FileSame -A $script:srcFile -B $legacy) {
        Remove-Item -LiteralPath $legacy -Force
        Write-Host ("    {0,-10} removed legacy file (never loaded by CodeBuddy): {1}" -f "codebuddy", $legacy) -ForegroundColor DarkGray
    } else {
        Write-Host ("    {0,-10} legacy file kept (differs from repo source): {1}" -f "codebuddy", $legacy) -ForegroundColor Yellow
    }
}

# ========================================================
# Install one tool's target file.
#   missing            -> write directly
#   identical to source-> skip silently (nothing to overwrite)
#   differs + $Force   -> overwrite without asking
#   differs + no Force -> ask [y/N]; anything but y/Y skips
# Copy-Item preserves bytes exactly — encoding (UTF-8 no BOM) and EOL (LF)
# travel with the copy, per the rules in the file itself.
# ========================================================
function Install-Tool {
    param([string]$ToolKey, [switch]$Force)

    $tool = $script:tools[$ToolKey]
    if ($tool.Mode -eq "rules") { Install-RulesTool -ToolKey $ToolKey -Tool $tool -Force:$Force; return }

    $dst = $tool.Path

    $parent = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -Path $parent -ItemType Directory -Force | Out-Null }

    if (Test-Path -LiteralPath $dst) {
        if (Test-FileSame -A $script:srcFile -B $dst) {
            Write-Host ("    {0,-10} already up to date" -f $ToolKey) -ForegroundColor DarkGray
            return
        }
        if (-not $Force) {
            $answer = Read-Host ("    {0,-10} exists and differs from repo source, overwrite? [y/N]" -f $ToolKey)
            if ($answer -notmatch '^[Yy]') {
                Write-Host ("    {0,-10} skipped" -f $ToolKey) -ForegroundColor Yellow
                return
            }
        }
        Copy-Item -LiteralPath $script:srcFile -Destination $dst -Force
        Write-Host ("    {0,-10} updated -> {1}" -f $ToolKey, $dst) -ForegroundColor Green
        return
    }

    Copy-Item -LiteralPath $script:srcFile -Destination $dst -Force
    Write-Host ("    {0,-10} installed -> {1}" -f $ToolKey, $dst) -ForegroundColor Green
}

# ========================================================
# Install the CodeBuddy user rule: a single RULE.mdc (whole AGENTS.md).
# Same overwrite policy as file mode (ask unless -f, skip when identical).
# ========================================================
function Install-RulesTool {
    param([string]$ToolKey, [hashtable]$Tool, [switch]$Force)

    if (-not (Test-Path -LiteralPath $Tool.Path)) {
        New-Item -Path $Tool.Path -ItemType Directory -Force | Out-Null
    }

    $expected = Get-CodeBuddyRuleContent
    $dst = $script:codebuddyRuleFile

    if (Test-Path -LiteralPath $dst) {
        if (Test-ContentSame -Path $dst -Expected $expected) {
            Write-Host ("    {0,-10} already up to date" -f $ToolKey) -ForegroundColor DarkGray
        } else {
            if (-not $Force) {
                $answer = Read-Host ("    {0,-10} exists and differs from repo source, overwrite? [y/N]" -f $ToolKey)
                if ($answer -notmatch '^[Yy]') {
                    Write-Host ("    {0,-10} skipped" -f $ToolKey) -ForegroundColor Yellow
                    Remove-LegacyCodebuddyFile
                    return
                }
            }
            Write-Utf8NoBom -Path $dst -Content $expected
            Write-Host ("    {0,-10} updated -> {1}" -f $ToolKey, $dst) -ForegroundColor Green
        }
    } else {
        Write-Utf8NoBom -Path $dst -Content $expected
        Write-Host ("    {0,-10} installed -> {1}" -f $ToolKey, $dst) -ForegroundColor Green
    }
    Remove-LegacyCodebuddyFile
    Write-Host ("    {0,-10} note: rules are loaded into NEW chat sessions only" -f $ToolKey) -ForegroundColor DarkGray
}

# ========================================================
# Uninstall one tool's file. Only removes a file that still matches the
# repo source exactly; user-modified or foreign files are never touched.
# ========================================================
function Uninstall-Tool {
    param([string]$ToolKey)

    $tool = $script:tools[$ToolKey]
    if ($tool.Mode -eq "rules") { Uninstall-RulesTool -ToolKey $ToolKey -Tool $tool; return }

    $dst = $tool.Path

    if (-not (Test-Path -LiteralPath $dst)) {
        Write-Host ("    {0,-10} not installed" -f $ToolKey) -ForegroundColor DarkGray
        return
    }
    if (Test-FileSame -A $script:srcFile -B $dst) {
        Remove-Item -LiteralPath $dst -Force
        Write-Host ("    {0,-10} removed" -f $ToolKey) -ForegroundColor Green
    } else {
        Write-Host ("    {0,-10} skipped: differs from repo source (not ours to delete)" -f $ToolKey) -ForegroundColor Yellow
    }
}

# ========================================================
# Uninstall the CodeBuddy user rule. The rule folder is removed only when
# its RULE.mdc still matches the repo-derived content exactly.
# ========================================================
function Uninstall-RulesTool {
    param([string]$ToolKey, [hashtable]$Tool)
    $dst = $script:codebuddyRuleFile
    if (-not (Test-Path -LiteralPath $dst)) {
        Write-Host ("    {0,-10} not installed" -f $ToolKey) -ForegroundColor DarkGray
    } elseif (Test-ContentSame -Path $dst -Expected (Get-CodeBuddyRuleContent)) {
        Remove-Item -LiteralPath $Tool.Path -Recurse -Force
        Write-Host ("    {0,-10} removed" -f $ToolKey) -ForegroundColor Green
    } else {
        Write-Host ("    {0,-10} skipped: differs from repo source (not ours to delete)" -f $ToolKey) -ForegroundColor Yellow
    }
    Remove-LegacyCodebuddyFile
}

# ========================================================
# Status: source + per-tool file state
# ========================================================
function Show-RulesToolStatus {
    param([string]$ToolKey, [hashtable]$Tool)
    $dst = $script:codebuddyRuleFile
    if (-not (Test-Path -LiteralPath $dst)) {
        $state = "missing"; $color = "Yellow"
    } elseif (Test-ContentSame -Path $dst -Expected (Get-CodeBuddyRuleContent)) {
        $state = "ok";      $color = "Green"
    } else {
        $state = "differs"; $color = "Yellow"
    }
    Write-Host ("    {0,-10} " -f $ToolKey) -NoNewline
    Write-Host ("[{0}]" -f $state) -ForegroundColor $color -NoNewline
    Write-Host (" {0}" -f $dst)
    $legacy = Join-Path $env:USERPROFILE ".codebuddy\CODEBUDDY.md"
    if (Test-Path -LiteralPath $legacy) {
        Write-Host ("    {0,-10} " -f $ToolKey) -NoNewline
        Write-Host "[note]" -ForegroundColor DarkGray -NoNewline
        Write-Host (" {0} exists but is NOT loaded by CodeBuddy (legacy single-file install)" -f $legacy)
    }
}

function Show-RulesStatus {
    Write-Host ""
    Write-Host "  source: $($script:srcFile)" -ForegroundColor Cyan
    Write-Host ""
    foreach ($key in $script:tools.Keys) {
        $tool = $script:tools[$key]
        if ($tool.Mode -eq "rules") { Show-RulesToolStatus -ToolKey $key -Tool $tool; continue }
        $dst = $tool.Path
        if (-not (Test-Path -LiteralPath $dst)) {
            $state = "missing"; $color = "Yellow"
        } elseif (Test-FileSame -A $script:srcFile -B $dst) {
            $state = "ok";      $color = "Green"
        } else {
            $state = "differs"; $color = "Yellow"
        }
        Write-Host ("    {0,-10} " -f $key) -NoNewline
        Write-Host ("[{0}]" -f $state) -ForegroundColor $color -NoNewline
        Write-Host (" {0}" -f $dst)
    }
    Write-Host ""
    Write-Host "  Legend: ok=matches repo  differs=exists but not current  missing=not installed" -ForegroundColor Green
    Write-Host "  codebuddy target is one user rule: ~/.codebuddy/rules/agents-rules/RULE.mdc" -ForegroundColor Green
    Write-Host ""
}

# ========================================================
# Help
# ========================================================
function Show-Help {
    Write-Host ""
    Write-Host "  Rules Installer for AI Extensions (Windows)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Installs repo rules/AGENTS.md into each agent's GLOBAL rules file." -ForegroundColor DarkGray
    Write-Host "  Copy mode: re-run -update after repo changes." -ForegroundColor DarkGray
    Write-Host "  CodeBuddy gets 1 user rule (whole AGENTS.md) at" -ForegroundColor DarkGray
    Write-Host "  ~/.codebuddy/rules/agents-rules/RULE.mdc; ~/.codebuddy/CODEBUDDY.md" -ForegroundColor DarkGray
    Write-Host "  is not a loadable global path — legacy copies are auto-removed." -ForegroundColor DarkGray
    Write-Host "  New rules apply to NEW chat sessions only." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Usage: ./windows-rules.ps1 [option] [argument]" -ForegroundColor White
    Write-Host ""
    Write-Host "  Options:" -ForegroundColor White
    Write-Host "    -h                Show this help"
    Write-Host "    -status           Show install status"
    Write-Host "    -install          Copy to all tools (asks before overwriting differing targets)"
    Write-Host "    -update           Same as -install (muscle-memory alias)"
    Write-Host "    -link   <tool>    Copy to one tool (asks before overwriting differing targets)"
    Write-Host "    -f                Force: overwrite without asking"
    Write-Host "    -unlink <tool>    Remove installed file if it matches repo source"
    Write-Host "    -d      <tool>    Alias of -unlink"
    Write-Host ""
    Write-Host "  Tools: claude, zcode, opencode, codebuddy, dsh, all" -ForegroundColor White
    Write-Host "  (workbuddy has no documented global rules file — skills only)"
    Write-Host ""
    Write-Host "  Examples:" -ForegroundColor White
    Write-Host "    ./windows-rules.ps1 -install         # install / refresh all targets"
    Write-Host "    ./windows-rules.ps1 -install -f       # force: overwrite without asking"
    Write-Host "    ./windows-rules.ps1 -status          # see what is where"
    Write-Host "    ./windows-rules.ps1 -unlink claude   # remove Claude Code's copy"
    Write-Host ""
}

# ========================================================
# Validate prerequisites and tool key
# ========================================================
function Test-ToolKey {
    param([string]$Key)
    if ($Key -eq "all") { return $true }
    if ($script:tools.Contains($Key)) { return $true }
    Write-Host ("  Unknown tool: {0} (available: {1}, all)" -f $Key, ($script:tools.Keys -join ', ')) -ForegroundColor Red
    return $false
}

function Test-Source {
    if ($script:srcFile -and (Test-Path -LiteralPath $script:srcFile)) { return $true }
    Write-Host "  Rules source not found: $($script:srcFile)" -ForegroundColor Red
    return $false
}

# ========================================================
# Main entry
# ========================================================
if ($h) {
    Show-Help
}
elseif ($status) {
    if (Test-Source) { Show-RulesStatus }
}
elseif ($install -or $update) {
    if (-not (Test-Source)) { exit 1 }
    Write-Host ""
    Write-Host "  Installing rules to all tools:" -ForegroundColor Cyan
    foreach ($key in $script:tools.Keys) {
        Install-Tool -ToolKey $key -Force:$f
    }
    Write-Host ""
}
elseif ($link) {
    if (-not (Test-Source)) { exit 1 }
    if (-not (Test-ToolKey -Key $link)) { exit 1 }
    Write-Host ""
    Write-Host "  Installing rules:" -ForegroundColor Cyan
    if ($link -eq "all") {
        foreach ($key in $script:tools.Keys) { Install-Tool -ToolKey $key -Force:$f }
    } else {
        Install-Tool -ToolKey $link -Force:$f
    }
    Write-Host ""
}
elseif ($unlink -or $d) {
    $t = if ($unlink) { $unlink } else { $d }
    if (-not (Test-Source)) { exit 1 }
    if (-not (Test-ToolKey -Key $t)) { exit 1 }
    Write-Host ""
    Write-Host "  Removing rules:" -ForegroundColor Cyan
    if ($t -eq "all") {
        foreach ($key in $script:tools.Keys) { Uninstall-Tool -ToolKey $key }
    } else {
        Uninstall-Tool -ToolKey $t
    }
    Write-Host ""
}
else {
    Show-Help
}
