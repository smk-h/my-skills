# ========================================================
# Skills Manager for AI Extensions (Windows, Junction mode)
# Manage skills for Claude Code / RooCode / ZCode / OpenCode.
#
# Topology (decouples repo path from agent links):
#   repo skills/  ──[update copy]──▶  %USERPROFILE%\.smskills\  ──[link Junction]──▶  each agent tool
#
#   - update : mirror repo skills/ into ~/.smskills (real copies)
#   - link   : junction ~/.smskills/<skill> into each agent tool
#   - If the repo moves/renames, just re-run update; agent links stay intact.
#
# Why Junction (not symbolic link)?
#   - Junction needs NO administrator rights. Symbolic links (mklink /D) do.
#   - Junction works on local volumes across drive letters.
#
# Param reference:
#   -h              Show help
#   -l              List installed skills across all tools
#   -status         Show link matrix
#   -update         Mirror repo skills/ into ~/.smskills
#   -install        One-shot: update + link all (good for first setup)
#   -link   <tool>  Create junctions in a tool's skills dir (source = ~/.smskills)
#   -f              Force: replace existing real-dir copies when linking
#   -unlink <tool>  Remove junctions from a tool (link only, source safe)
#   -d      <tool>  Alias of -unlink
#
#   <tool> values: claude, roo, zcode, opencode, all
# ========================================================

[CmdletBinding()]
param(
    [switch]$h,
    [switch]$l,
    [switch]$status,
    [switch]$update,
    [switch]$install,
    [switch]$f,
    [ValidateSet("claude", "roo", "zcode", "opencode", "codebuddy", "all")]
    [string]$d,
    [ValidateSet("claude", "roo", "zcode", "opencode", "codebuddy", "all")]
    [string]$unlink,
    [ValidateSet("claude", "roo", "zcode", "opencode", "codebuddy", "all")]
    [string]$link
)

# ========================================================
# Global config
# ========================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Repo skills source (what update reads from)
$script:srcPath = if ($PSScriptRoot) { Join-Path $PSScriptRoot "skills" } elseif ($MyInvocation.MyCommand.Path) { Join-Path (Split-Path $MyInvocation.MyCommand.Path) "skills" } else { $null }
if ($script:srcPath -and (Test-Path -LiteralPath $script:srcPath)) {
    $script:srcPath = (Resolve-Path -LiteralPath $script:srcPath).Path
}

# Local skills mirror (update target / link source). Agents link here, not to the repo.
$script:mirrorPath = Join-Path $env:USERPROFILE ".smskills"

# Tool table: key -> @{ Path=install dir; Name=display name }
$script:tools = [ordered]@{
    claude    = @{ Path = Join-Path $env:USERPROFILE ".claude\skills";            Name = "Claude Code" }
    roo       = @{ Path = Join-Path $env:USERPROFILE ".roo\skills";               Name = "RooCode" }
    zcode     = @{ Path = Join-Path $env:USERPROFILE ".zcode\skills";             Name = "ZCode" }
    opencode  = @{ Path = Join-Path $env:USERPROFILE ".config\opencode\skills";   Name = "OpenCode" }
    codebuddy = @{ Path = Join-Path $env:USERPROFILE ".codebuddy\skills";         Name = "CodeBuddy" }
}

# ========================================================
# Helper: detect reparse point (junction/symlink)
# ========================================================
function Test-ReparsePoint {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return $false }
    return ($item.Attributes.ToString() -match 'ReparsePoint')
}

# ========================================================
# Helper: read description from SKILL.md front matter
# ========================================================
function Get-SkillDescription {
    param([string]$SkillFile)
    if (-not (Test-Path -LiteralPath $SkillFile)) { return "" }
    $content = Get-Content -LiteralPath $SkillFile -Encoding UTF8 -ErrorAction SilentlyContinue
    foreach ($line in $content) {
        if ($line -match '^\s*description:\s*(.+?)\s*(?:---\s*)?$') {
            return $Matches[1].Trim()
        }
    }
    return ""
}

# ========================================================
# Helper: read reparse-point target (first Target entry)
# ========================================================
function Get-LinkTarget {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return $null }
    try { return ($item.Target | Select-Object -First 1) } catch { return $null }
}

# ========================================================
# Helper: list skill subdir names under a given directory
# ========================================================
function Get-SkillNamesFrom {
    param([string]$BasePath)
    if (-not (Test-Path -LiteralPath $BasePath)) { return @() }
    $dirs = Get-ChildItem -LiteralPath $BasePath -Directory -ErrorAction SilentlyContinue
    if (-not $dirs) { return @() }
    return $dirs | Select-Object -ExpandProperty Name
}

# ========================================================
# update: mirror repo skills/ into ~/.smskills (real copies).
# Adds/overwrites repo skills; removes orphans (in mirror but not in repo).
# ========================================================
function Update-Skills {
    if (-not $script:srcPath -or -not (Test-Path -LiteralPath $script:srcPath)) {
        Write-Host "  Repo skills source not found: $($script:srcPath)" -ForegroundColor Red
        return
    }
    Write-Host ""
    Write-Host "  Updating mirror from repo:" -ForegroundColor Cyan
    Write-Host "    repo  : $($script:srcPath)" -ForegroundColor DarkGray
    Write-Host "    mirror: $($script:mirrorPath)" -ForegroundColor DarkGray
    Write-Host ""

    if (-not (Test-Path -LiteralPath $script:mirrorPath)) {
        New-Item -Path $script:mirrorPath -ItemType Directory -Force | Out-Null
    }

    $updated = 0; $added = 0; $orphan = 0
    $repoSkills = Get-ChildItem -LiteralPath $script:srcPath -Directory -ErrorAction SilentlyContinue

    # 1) sync: copy/overwrite repo skills into mirror
    foreach ($dir in $repoSkills) {
        $src = $dir.FullName
        $dst = Join-Path $script:mirrorPath $dir.Name
        $existed = $false

        if (Test-Path -LiteralPath $dst) {
            if (Test-ReparsePoint -Path $dst) { [System.IO.Directory]::Delete($dst, $false) }
            else { Remove-Item -LiteralPath $dst -Recurse -Force }
            $existed = $true
        }

        Copy-Item -LiteralPath $src -Destination $script:mirrorPath -Recurse -Force | Out-Null
        if ($existed) {
            Write-Host ("    {0,-16} updated" -f $dir.Name) -ForegroundColor Green
            $updated++
        } else {
            Write-Host ("    {0,-16} added" -f $dir.Name) -ForegroundColor Green
            $added++
        }
    }

    # 2) orphan cleanup: in mirror but not in repo
    foreach ($name in (Get-SkillNamesFrom -BasePath $script:mirrorPath)) {
        $repoItem = Join-Path $script:srcPath $name
        if (-not (Test-Path -LiteralPath $repoItem)) {
            $m = Join-Path $script:mirrorPath $name
            if (Test-ReparsePoint -Path $m) { [System.IO.Directory]::Delete($m, $false) }
            else { Remove-Item -LiteralPath $m -Recurse -Force }
            Write-Host ("    {0,-16} removed (no longer in repo)" -f $name) -ForegroundColor Yellow
            $orphan++
        }
    }

    Write-Host ""
    Write-Host ("  Mirror ready: {0} added, {1} updated, {2} orphan removed." -f $added, $updated, $orphan) -ForegroundColor Green
    Write-Host ""
}

# ========================================================
# Ensure mirror exists/non-empty; otherwise tell user to update first.
# ========================================================
function Ensure-Mirror {
    $names = Get-SkillNamesFrom -BasePath $script:mirrorPath
    if ($names.Count -eq 0) {
        Write-Host "  Mirror is empty: $($script:mirrorPath)" -ForegroundColor Red
        Write-Host "  Run first: ./windows-skills.ps1 -update  (or -install)" -ForegroundColor Red
        return $false
    }
    return $true
}

# ========================================================
# Link: create junctions in a tool pointing to ~/.smskills.
# Safely replaces existing links/copies. NEVER deletes the mirror source.
# ========================================================
function Link-Tool {
    param([string]$ToolKey, [switch]$Force)

    if (-not (Ensure-Mirror)) { return }

    $tool = $script:tools[$ToolKey]
    $path = $tool.Path
    if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -ItemType Directory -Force | Out-Null }

    Write-Host ""
    Write-Host ("  Linking skills to {0} ({1}):" -f $tool.Name, $path) -ForegroundColor Cyan

    $created = 0; $skipped = 0
    foreach ($name in (Get-SkillNamesFrom -BasePath $script:mirrorPath)) {
        $src = Join-Path $script:mirrorPath $name
        $dst = Join-Path $path $name

        if (Test-ReparsePoint -Path $dst) {
            $tgt = Get-LinkTarget -Path $dst
            if ($tgt -and ($tgt -eq $src)) {
                Write-Host ("    {0,-16} already linked" -f $name) -ForegroundColor DarkGray
                $skipped++; continue
            }
            # Wrong target junction/symlink -> remove the link only (source untouched)
            [System.IO.Directory]::Delete($dst, $false)
        } elseif (Test-Path -LiteralPath $dst) {
            if ($Force) {
                Remove-Item -LiteralPath $dst -Recurse -Force
                Write-Host ("    {0,-16} existing copy removed (force)" -f $name) -ForegroundColor Yellow
            } else {
                Write-Host ("    {0,-16} is a real dir, skipped (use -f to replace)" -f $name) -ForegroundColor Yellow
                $skipped++; continue
            }
        }

        try {
            New-Item -ItemType Junction -Path $dst -Target $src -ErrorAction Stop | Out-Null
            Write-Host ("    {0,-16} linked -> {1}" -f $name, $src) -ForegroundColor Green
            $created++
        } catch {
            Write-Host ("    {0,-16} FAIL: {1}" -f $name, $_.Exception.Message) -ForegroundColor Red
        }
    }
    Write-Host ""
    Write-Host ("  {0}: {1} linked, {2} skipped" -f $tool.Name, $created, $skipped) -ForegroundColor Green
    Write-Host ""
}

# ========================================================
# Unlink: remove junctions from a tool. Link only; source safe.
# Real directories are skipped to avoid deleting user data.
# ========================================================
function Unlink-Tool {
    param([string]$ToolKey)

    $tool = $script:tools[$ToolKey]
    $path = $tool.Path
    Write-Host ""
    Write-Host ("  Unlinking skills from {0} ({1}):" -f $tool.Name, $path) -ForegroundColor Cyan

    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host "  Skills directory not found: $path" -ForegroundColor Yellow
        Write-Host ""; return
    }
    $dirs = Get-ChildItem -LiteralPath $path -Directory -Force -ErrorAction SilentlyContinue
    if (-not $dirs) { Write-Host "  No skills to remove." -ForegroundColor Yellow; Write-Host ""; return }

    $count = 0
    foreach ($dir in $dirs) {
        if (Test-ReparsePoint -Path $dir.FullName) {
            [System.IO.Directory]::Delete($dir.FullName, $false)
            Write-Host ("    {0,-16} unlinked" -f $dir.Name) -ForegroundColor Green
            $count++
        } else {
            Write-Host ("    {0,-16} is a real dir, skipped (not a link)" -f $dir.Name) -ForegroundColor Yellow
        }
    }
    Write-Host ""
    Write-Host ("  {0}: {1} link(s) removed" -f $tool.Name, $count) -ForegroundColor Green
    Write-Host ""
}

# ========================================================
# install: one-shot update + link all
# ========================================================
function Install-All {
    param([switch]$Force)
    Update-Skills
    foreach ($key in $script:tools.Keys) {
        Link-Tool -ToolKey $key -Force:$Force
    }
}

# ========================================================
# List installed skills grouped by tool, with link/copy tag
# ========================================================
function Get-SkillList {
    $all = @()
    foreach ($key in $script:tools.Keys) {
        $tool = $script:tools[$key]
        if (-not (Test-Path -LiteralPath $tool.Path)) { continue }
        $skillDirs = Get-ChildItem -LiteralPath $tool.Path -Directory -Force -ErrorAction SilentlyContinue
        foreach ($dir in $skillDirs) {
            $isLink = Test-ReparsePoint -Path $dir.FullName
            $desc = Get-SkillDescription -SkillFile (Join-Path $dir.FullName "SKILL.md")
            $all += [PSCustomObject]@{
                Tool = $tool.Name; Name = $dir.Name; Description = $desc; Linked = $isLink
            }
        }
    }

    Write-Host ""
    if ($all.Count -eq 0) { Write-Host "  No skills found" -ForegroundColor Yellow; Write-Host ""; return }

    foreach ($group in ($all | Group-Object -Property Tool)) {
        Write-Host ("  {0} ({1})" -f $group.Name, $group.Count) -ForegroundColor Cyan
        foreach ($skill in $group.Group) {
            $tag = if ($skill.Linked) { "link" } else { "copy" }
            $tagColor = if ($skill.Linked) { 'Green' } else { 'Yellow' }
            $desc = if ($skill.Description) { $skill.Description } else { "(no description)" }
            Write-Host ("    {0,-16} " -f $skill.Name) -NoNewline
            Write-Host ("[{0}] " -f $tag) -ForegroundColor $tagColor -NoNewline
            Write-Host $desc
        }
        Write-Host ""
    }
    Write-Host ("  Total: {0} skills" -f $all.Count) -ForegroundColor Green
    Write-Host ""
}

# ========================================================
# Link status matrix (baseline = ~/.smskills)
# ========================================================
function Show-LinkStatus {
    Write-Host ""
    Write-Host "  repo  : $($script:srcPath)" -ForegroundColor DarkGray
    Write-Host "  mirror: $($script:mirrorPath)" -ForegroundColor Cyan
    $names = Get-SkillNamesFrom -BasePath $script:mirrorPath
    if ($names.Count -eq 0) {
        Write-Host "  Mirror is empty. Run: ./windows-skills.ps1 -update" -ForegroundColor Yellow
        Write-Host ""; return
    }

    Write-Host ""
    # Compute column widths: skill column = longest skill name + padding;
    # each tool column fixed width (>= longest tool key "opencode"=8).
    $skillW = 18
    foreach ($n in $names) { if ($n.Length -ge $skillW) { $skillW = $n.Length + 2 } }
    $colW = 10  # fits "opencode" + padding

    # Header
    $line = "  " + ("{0,-$skillW}" -f "skill")
    foreach ($key in $script:tools.Keys) { $line += ("{0,-$colW}" -f $key) }
    Write-Host $line -ForegroundColor White

    # Rows
    foreach ($skill in $names) {
        $line = "  " + ("{0,-$skillW}" -f $skill)
        foreach ($key in $script:tools.Keys) {
            $dst = Join-Path $script:tools[$key].Path $skill
            $cell = "-"; $color = 'DarkGray'
            if (Test-ReparsePoint -Path $dst) {
                $tgt = Get-LinkTarget -Path $dst
                $expected = Join-Path $script:mirrorPath $skill
                if ($tgt -and ($tgt -eq $expected)) { $cell = "LINK"; $color = 'Green' }
                else { $cell = "link?"; $color = 'Yellow' }
            } elseif (Test-Path -LiteralPath $dst) {
                $cell = "copy"; $color = 'Yellow'
            }
            $line += ("{0,-$colW}" -f $cell)
        }
        Write-Host $line
    }
    Write-Host ""
    Write-Host "  Legend: LINK=junction to mirror  link?=wrong target  copy=real dir  -=not installed" -ForegroundColor Green
    Write-Host ""
}

# ========================================================
# Apply a tool-scoped action across 'all' tools
# ========================================================
function Invoke-All {
    param([string]$Action)
    foreach ($key in $script:tools.Keys) {
        switch ($Action) {
            'link'   { Link-Tool -ToolKey $key -Force:$f }
            'unlink' { Unlink-Tool -ToolKey $key }
        }
    }
}

# ========================================================
# Help
# ========================================================
function Show-Help {
    Write-Host ""
    Write-Host "  Skills Manager for AI Extensions (Windows / Junction mode)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Topology:" -ForegroundColor DarkGray
    Write-Host "    repo skills/  --[update]-->  ~/.smskills  --[link]-->  each agent tool" -ForegroundColor DarkGray
    Write-Host "    If the repo moves, re-run -update; agent links stay intact." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Usage: ./windows-skills.ps1 [option] [argument]" -ForegroundColor White
    Write-Host ""
    Write-Host "  Options:" -ForegroundColor White
    Write-Host "    -h                Show this help"
    Write-Host "    -l                List installed skills (with link/copy tag)"
    Write-Host "    -status           Show link matrix"
    Write-Host "    -update           Mirror repo skills/ into ~/.smskills"
    Write-Host "    -install          One-shot: -update + link all (good for first setup)"
    Write-Host "    -link   <tool>    Create junctions in a tool (source = ~/.smskills)"
    Write-Host "    -f                Force replace existing real-dir copies (with -link)"
    Write-Host "    -unlink <tool>    Remove junctions from a tool (link only, source safe)"
    Write-Host "    -d      <tool>    Alias of -unlink"
    Write-Host ""
    Write-Host "  Tools: claude, roo, zcode, opencode, codebuddy, all"
    Write-Host ""
    Write-Host "  Examples:" -ForegroundColor White
    Write-Host "    ./windows-skills.ps1 -install         # first setup: mirror + link all"
    Write-Host "    ./windows-skills.ps1 -update          # after repo changes, refresh mirror"
    Write-Host "    ./windows-skills.ps1 -link all -f     # force replace existing copies"
    Write-Host "    ./windows-skills.ps1 -status          # see link matrix"
    Write-Host "    ./windows-skills.ps1 -unlink roo      # remove RooCode links"
    Write-Host ""
}

# ========================================================
# Validate tool key
# ========================================================
function Test-ToolKey {
    param([string]$Key)
    if ($Key -eq "all") { return $true }
    if ($script:tools.Contains($Key)) { return $true }
    Write-Host ("  Unknown tool: {0} (available: {1}, all)" -f $Key, ($script:tools.Keys -join ', ')) -ForegroundColor Red
    return $false
}

# ========================================================
# Main entry
# ========================================================
if ($h) {
    Show-Help
}
elseif ($l) {
    Get-SkillList
}
elseif ($status) {
    Show-LinkStatus
}
elseif ($update) {
    Update-Skills
}
elseif ($install) {
    Install-All -Force:$f
}
elseif ($link) {
    if (-not (Test-ToolKey -Key $link)) { exit 1 }
    if ($link -eq "all") { Invoke-All -Action 'link' } else { Link-Tool -ToolKey $link -Force:$f }
}
elseif ($unlink -or $d) {
    $t = if ($unlink) { $unlink } else { $d }
    if (-not (Test-ToolKey -Key $t)) { exit 1 }
    if ($t -eq "all") { Invoke-All -Action 'unlink' } else { Unlink-Tool -ToolKey $t }
}
else {
    Show-Help
}
