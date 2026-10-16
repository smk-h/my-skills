# ========================================================
# Rules Installer for AI Extensions (Windows)
# Install repo rules/AGENTS.md into each agent's GLOBAL instruction file
# (user scope, loaded in every project).
#
# Topology (single file, copy mode — no mirror layer needed):
#   repo rules/AGENTS.md  ──[copy]──▶  each agent's global rules file
#
# Why copy (not junction/link):
#   - Targets are FILES; junctions are dir-only, file symlinks need admin
#     rights, hardlinks break when editors/git replace the source file.
#   - Re-run -update after repo changes.
#
# Safety:
#   -install / -update : a target that exists and DIFFERS from the repo source
#                        asks for confirmation before being overwritten; a target
#                        already identical to the source is skipped silently.
#                        No backup is made — repo rules/AGENTS.md is the source of truth.
#   -f          : force — overwrite without asking
#   -unlink  : removes the file ONLY if it matches the repo source exactly
#
# Target map (user-global scope, each path verified against agent docs):
#   claude     ~/.claude/CLAUDE.md               Claude Code user memory
#   zcode      ~/.zcode/AGENTS.md
#   opencode   ~/.config/opencode/AGENTS.md
#   codebuddy  ~/.codebuddy/CODEBUDDY.md
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

# Tool table: key -> @{ Path=target file; Name=display name }
$script:tools = [ordered]@{
    claude    = @{ Path = Join-Path $env:USERPROFILE ".claude\CLAUDE.md";              Name = "Claude Code" }
    zcode     = @{ Path = Join-Path $env:USERPROFILE ".zcode\AGENTS.md";               Name = "ZCode" }
    opencode  = @{ Path = Join-Path $env:USERPROFILE ".config\opencode\AGENTS.md";     Name = "OpenCode" }
    codebuddy = @{ Path = Join-Path $env:USERPROFILE ".codebuddy\CODEBUDDY.md";        Name = "CodeBuddy" }
    dsh       = @{ Path = Join-Path $env:USERPROFILE ".dsh\AGENTS.md";                 Name = "DeepSeek Harness" }
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
# Uninstall one tool's file. Only removes a file that still matches the
# repo source exactly; user-modified or foreign files are never touched.
# ========================================================
function Uninstall-Tool {
    param([string]$ToolKey)

    $tool = $script:tools[$ToolKey]
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
# Status: source + per-tool file state
# ========================================================
function Show-RulesStatus {
    Write-Host ""
    Write-Host "  source: $($script:srcFile)" -ForegroundColor Cyan
    Write-Host ""
    foreach ($key in $script:tools.Keys) {
        $dst = $script:tools[$key].Path
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
