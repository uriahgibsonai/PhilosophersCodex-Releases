# Update-PhilosophersCodex.ps1
# Installs or updates Philosopher's Codex for World of Warcraft: Forever.
# Reads latest.json from the public Releases repo, compares it to the
# installed TOC version, backs up the old addon folder, and extracts the
# new zip into Interface\AddOns. Optionally copies PhilosophersCodex
# SavedVariables into a reports folder and prints a short error summary.
# Never touches any other addon, WTF file, or game folder.

[CmdletBinding()]
param(
    [string]$WowRoot,
    [string]$AddOnsPath,
    [string]$ManifestUrl = "https://raw.githubusercontent.com/uriahgibsonai/PhilosophersCodex-Releases/main/latest.json",
    [switch]$CopyReports,
    [string]$ReportsDir,
    [switch]$SkipDownload
)

$ErrorActionPreference = "Stop"
$AddonName = "PhilosophersCodex"

function Write-Info($msg) { Write-Host $msg }
function Write-Warn($msg) { Write-Host "WARNING: $msg" -ForegroundColor Yellow }
function Write-Err($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red }

function Get-VersionParts([string]$ver) {
    $m = [regex]::Match([string]$ver, '(\d+)\.(\d+)(?:\.(\d+))?')
    if (-not $m.Success) { return @(0, 0, 0) }
    $a = [int]$m.Groups[1].Value
    $b = [int]$m.Groups[2].Value
    $c = 0
    if ($m.Groups[3].Success -and $m.Groups[3].Value -ne "") {
        $c = [int]$m.Groups[3].Value
    }
    return @($a, $b, $c)
}

function Compare-Versions([string]$left, [string]$right) {
    $l = Get-VersionParts $left
    $r = Get-VersionParts $right
    for ($i = 0; $i -lt 3; $i++) {
        if ($l[$i] -gt $r[$i]) { return 1 }
        if ($l[$i] -lt $r[$i]) { return -1 }
    }
    return 0
}

function Read-TocVersion([string]$tocPath) {
    if (-not (Test-Path -LiteralPath $tocPath)) { return $null }
    foreach ($line in Get-Content -LiteralPath $tocPath -ErrorAction SilentlyContinue) {
        $m = [regex]::Match($line, '##\s*Version:\s*(\S+)')
        if ($m.Success) { return $m.Groups[1].Value.Trim() }
    }
    return $null
}

function Test-ForeverRoot([string]$root) {
    if ([string]::IsNullOrWhiteSpace($root)) { return $false }
    if (-not (Test-Path -LiteralPath $root)) { return $false }
    $addons = Join-Path $root "Interface\AddOns"
    return (Test-Path -LiteralPath $addons)
}

function Find-WowForeverRoot {
    $candidates = @()
    if ($WowRoot) { $candidates += $WowRoot }
    if ($env:WOW_FOREVER_ROOT) { $candidates += $env:WOW_FOREVER_ROOT }
    $pf86 = ${env:ProgramFiles(x86)}
    $pf = $env:ProgramFiles
    foreach ($base in @($pf86, $pf, "C:\Program Files (x86)", "C:\Program Files", "D:\", "E:\", "F:\")) {
        if ([string]::IsNullOrWhiteSpace($base)) { continue }
        $candidates += (Join-Path $base "World of Warcraft\_forever_")
        $candidates += (Join-Path $base "World of Warcraft\_forever")
        $candidates += (Join-Path $base "_forever_")
    }
    $candidates += "C:\Program Files (x86)\World of Warcraft\_forever_"
    $candidates += "C:\Program Files\World of Warcraft\_forever_"
    $candidates += "D:\World of Warcraft\_forever_"
    $candidates += "E:\World of Warcraft\_forever_"

    $seen = @{}
    foreach ($c in $candidates) {
        if ([string]::IsNullOrWhiteSpace($c)) { continue }
        try {
            $full = [System.IO.Path]::GetFullPath($c)
        } catch {
            continue
        }
        if ($seen.ContainsKey($full.ToLowerInvariant())) { continue }
        $seen[$full.ToLowerInvariant()] = $true
        if (Test-ForeverRoot $full) { return $full }
    }
    return $null
}

function Get-JsonManifest([string]$url) {
    Write-Info "Reading $url"
    $resp = Invoke-WebRequest -Uri $url -UseBasicParsing
    $text = $resp.Content
    if ($PSVersionTable.PSVersion.Major -ge 5) {
        return $text | ConvertFrom-Json
    }
    throw "This script needs PowerShell 5 or later to read latest.json."
}

function Copy-SavedVariableReports([string]$root, [string]$dest) {
    $wtf = Join-Path $root "WTF\Account"
    if (-not (Test-Path -LiteralPath $wtf)) {
        Write-Info "No WTF\\Account folder found; skipping reports."
        return
    }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $copied = 0
    Get-ChildItem -LiteralPath $wtf -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $sv = Join-Path $_.FullName "SavedVariables"
        if (-not (Test-Path -LiteralPath $sv)) { return }
        Get-ChildItem -LiteralPath $sv -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "PhilosophersCodex*.lua" } |
            ForEach-Object {
                $account = $_.Directory.Parent.Name
                $targetDir = Join-Path $dest $account
                New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
                Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $targetDir $_.Name) -Force
                $copied++
                Write-Info "  Copied $($account)\$($_.Name)"
                Write-LogSummary $_.FullName
            }
    }
    if ($copied -eq 0) {
        Write-Info "No PhilosophersCodex SavedVariables files were found."
    } else {
        Write-Info "Copied $copied log file(s) to $dest"
    }
}

function Write-LogSummary([string]$path) {
    $raw = Get-Content -LiteralPath $path -Raw -ErrorAction SilentlyContinue
    if (-not $raw) { return }
    $errMatches = [regex]::Matches($raw, '\["message"\]\s*=\s*"((?:\\.|[^"\\])*)"')
    $countMatches = [regex]::Matches($raw, '\["count"\]\s*=\s*(\d+)')
    $kindMatches = [regex]::Matches($raw, '\["kind"\]\s*=\s*"((?:\\.|[^"\\])*)"')
    $errorsBlock = $false
    if ($raw -match 'PhilosophersCodexLog') {
        Write-Info "  Summary for $(Split-Path $path -Leaf):"
        $msgs = @()
        foreach ($m in $errMatches) {
            $text = $m.Groups[1].Value
            if ($text) { $msgs += $text }
        }
        if ($msgs.Count -eq 0) {
            Write-Info "    No error messages found in this file."
        } else {
            $unique = $msgs | Select-Object -First 8
            foreach ($u in $unique) {
                Write-Info "    - $u"
            }
            if ($msgs.Count -gt 8) {
                Write-Info "    ... and $($msgs.Count - 8) more recorded lines"
            }
        }
    }
}

try {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    if (-not $ReportsDir) {
        $ReportsDir = Join-Path $scriptDir "reports"
    }

    $root = $null
    if ($AddOnsPath) {
        $root = Split-Path (Split-Path $AddOnsPath -Parent) -Parent
    } else {
        $root = Find-WowForeverRoot
    }
    if (-not $root -or -not (Test-ForeverRoot $root)) {
        Write-Err "Could not find a World of Warcraft\_forever_ folder."
        Write-Info "Pass one, for example:"
        Write-Info "  .\\Update-PhilosophersCodex.ps1 -WowRoot 'C:\\Program Files (x86)\\World of Warcraft\\_forever_'"
        Write-Info "  .\\Update-PhilosophersCodex.ps1 -AddOnsPath 'C:\\Program Files (x86)\\World of Warcraft\\_forever_\\Interface\\AddOns'"
        exit 1
    }

    if (-not $AddOnsPath) {
        $AddOnsPath = Join-Path $root "Interface\AddOns"
    }
    if (-not (Test-Path -LiteralPath $AddOnsPath)) {
        Write-Err "AddOns folder not found: $AddOnsPath"
        exit 1
    }

    $addonDir = Join-Path $AddOnsPath $AddonName
    $tocPath = Join-Path $addonDir "$AddonName.toc"
    $installed = Read-TocVersion $tocPath
    if ($installed) {
        Write-Info "Installed version: $installed"
        Write-Info "Install path: $addonDir"
    } else {
        Write-Info "No existing $AddonName folder was found. A new copy will be installed into:"
        Write-Info "  $addonDir"
        $installed = "0.0.0"
    }

    $manifest = Get-JsonManifest $ManifestUrl
    $latest = [string]$manifest.version
    $zipUrl = [string]$manifest.zipUrl
    $date = [string]$manifest.date
    $changelog = [string]$manifest.changelog
    if (-not $latest -or -not $zipUrl) {
        Write-Err "latest.json is missing version or zipUrl."
        exit 1
    }
    Write-Info "Latest version: $latest  ($date)"
    if ($changelog) { Write-Info "Changes: $changelog" }

    $cmp = Compare-Versions $installed $latest
    if ($cmp -ge 0 -and (Test-Path -LiteralPath $tocPath)) {
        Write-Info "You already have $installed at $addonDir, which is current (latest is $latest). Nothing to install."
        Write-Info "If the game still shows an older version, type /reload in game or restart WoW. /codex version prints what loaded."
        if ($CopyReports -or (Test-Path -LiteralPath (Join-Path $root "WTF\Account"))) {
            if ($CopyReports) {
                Copy-SavedVariableReports $root $ReportsDir
            }
        }
        exit 0
    }

    $temp = Join-Path $env:TEMP ("PhilosophersCodex-update-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $temp | Out-Null
    $zipPath = Join-Path $temp "PhilosophersCodex.zip"
    $extractDir = Join-Path $temp "extract"
    New-Item -ItemType Directory -Force -Path $extractDir | Out-Null

    try {
        Write-Info "Downloading $zipUrl"
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
        if (-not (Test-Path -LiteralPath $zipPath) -or ((Get-Item $zipPath).Length -lt 1000)) {
            Write-Err "The download was empty or too small."
            exit 1
        }

        Write-Info "Extracting zip..."
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractDir)

        $srcAddon = Join-Path $extractDir $AddonName
        if (-not (Test-Path -LiteralPath (Join-Path $srcAddon "$AddonName.toc"))) {
            $found = Get-ChildItem -Path $extractDir -Filter "$AddonName.toc" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                $srcAddon = $found.DirectoryName
            }
        }
        if (-not (Test-Path -LiteralPath (Join-Path $srcAddon "$AddonName.toc"))) {
            Write-Err "The zip did not contain a PhilosophersCodex folder with a TOC file."
            exit 1
        }

        $newVer = Read-TocVersion (Join-Path $srcAddon "$AddonName.toc")
        Write-Info "Zip TOC version: $newVer"

        if (Test-Path -LiteralPath $addonDir) {
            $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
            # Keep backups outside AddOns so the game never sees a second copy.
            $backupRoot = Join-Path (Split-Path $AddOnsPath -Parent) "PhilosophersCodex-backups"
            New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
            $backup = Join-Path $backupRoot ($AddonName + ".bak-" + $stamp)
            Write-Info "Backing up current folder to $backup"
            Move-Item -LiteralPath $addonDir -Destination $backup
        }

        Write-Info "Installing into $addonDir"
        Copy-Item -LiteralPath $srcAddon -Destination $addonDir -Recurse

        # If the zip shipped the updater scripts, refresh the copies next to this script
        # and also leave a copy in the AddOns folder for convenience. Nothing else is copied.
        foreach ($name in @("Update-PhilosophersCodex.ps1", "Update-PhilosophersCodex.bat")) {
            $from = Join-Path $extractDir $name
            if (Test-Path -LiteralPath $from) {
                $beside = Join-Path $scriptDir $name
                if ($from -ne $beside) {
                    Copy-Item -LiteralPath $from -Destination $beside -Force
                }
            }
        }

        $finalVer = Read-TocVersion (Join-Path $addonDir "$AddonName.toc")
        if (-not $finalVer) {
            Write-Err "After install there is no readable TOC at $addonDir\$AddonName.toc."
            exit 1
        }
        if ((Compare-Versions $finalVer $latest) -ne 0) {
            Write-Err "Installed TOC says $finalVer but the latest release is $latest. The install did not take."
            exit 1
        }
        Write-Info "Verified: $addonDir\$AddonName.toc is version $finalVer."

        # A zip unpacked by hand into the addon folder leaves AddOns\PhilosophersCodex\PhilosophersCodex.
        $nested = Join-Path $addonDir $AddonName
        if (Test-Path -LiteralPath (Join-Path $nested "$AddonName.toc")) {
            Write-Warn "Found a nested copy at $nested. The game ignores it; delete it to avoid confusion."
        }

        $running = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^Wow' }
        if ($running) {
            Write-Warn "WoW is running. Type /reload in game (or restart) so it loads $finalVer."
        } else {
            Write-Info "Start WoW Forever to load $finalVer."
        }
        Write-Info "In game, the main window header should read 'Alchemists - v$finalVer'. /codex version also prints it."

        if ($CopyReports) {
            Copy-SavedVariableReports $root $ReportsDir
        }
    }
    finally {
        if (Test-Path -LiteralPath $temp) {
            Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
catch {
    Write-Err $_.Exception.Message
    exit 1
}
