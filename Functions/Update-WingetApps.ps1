function Update-WingetApps {
    [CmdletBinding()]
    param()

    # Local, safe logger: uses Write-Log if available; otherwise, does nothing
    function Invoke-Log {
        param([string]$Message)
        try {
            $logger = Get-Command -Name Write-Log -ErrorAction SilentlyContinue
            if ($logger) { Write-Log $Message }
        } catch {}
    }

    # Save original preferences
    $origErr  = $ErrorActionPreference
    $origProg = $ProgressPreference
    $origInfo = $InformationPreference

    # Silent execution
    $ErrorActionPreference = 'Stop'
    $ProgressPreference    = 'SilentlyContinue'
    $InformationPreference = 'SilentlyContinue'

    # Blocked packages (case-insensitive)
    $blockedRegex = '(?i)QGIS|TeamViewer|GoodSync|MiniTool'

    try {
        # Verify winget exists
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Invoke-Log "Winget not found; skipping updates."
            return
        }

        # Maintain msstore source; reset on 0x8a15000f
        try {
            & winget source update -n msstore *> $null
            $srcCode = $LASTEXITCODE
            if ($srcCode -eq 0x8a15000f) {
                & winget source reset --force -n msstore *> $null
                & winget source update -n msstore *> $null
                $srcCode = $LASTEXITCODE
            }
            if ($srcCode -ne 0) {
                Invoke-Log ("Warning: msstore sync failed (0x{0:x})." -f $srcCode)
            }
        } catch {
            Invoke-Log ("Warning: exception updating 'msstore': {0}" -f $_.Exception.Message)
        }

        # Query available upgrades (JSON)
        $upgradeListJson = $null
        try {
            $upgradeListJson = (& winget upgrade --include-unknown --disable-interactivity --output json) 2>$null
        } catch {
            Invoke-Log ("Winget: 'upgrade' did not return JSON: {0}" -f $_.Exception.Message)
        }
        if (-not $upgradeListJson) {
            Invoke-Log "Winget: no upgrades available or no output."
            return
        }

        # Parse JSON (support multiple shapes)
        $parsed = $null
        try {
            $parsed = $upgradeListJson | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Invoke-Log "Winget: failed to parse upgrades JSON; exiting silently."
            return
        }

        $candidates = @()
        if ($parsed) {
            if ($parsed.PSObject.Properties.Name -contains 'Upgrades') {
                if ($parsed.Upgrades -and ($parsed.Upgrades.PSObject.Properties.Name -contains 'Items')) {
                    $candidates = $parsed.Upgrades.Items
                } else {
                    $candidates = $parsed.Upgrades
                }
            } elseif ($parsed.PSObject.Properties.Name -contains 'Items') {
                $candidates = $parsed.Items
            } elseif ($parsed -is [array]) {
                $candidates = $parsed
            } else {
                $candidates = @($parsed)
            }
        }

        if (-not $candidates -or $candidates.Count -eq 0) {
            Invoke-Log "Winget: empty upgrades list."
            return
        }

        # Filter blocked (by identifier and name)
        $toUpdate = $candidates | Where-Object {
            ($_.PackageIdentifier -notmatch $blockedRegex) -and ($_.PackageName -notmatch $blockedRegex)
        }
        if (-not $toUpdate -or $toUpdate.Count -eq 0) {
            Invoke-Log "Winget: only blocked packages found (QGIS/TeamViewer/GoodSync/MiniTool)."
            return
        }

        # Apply upgrades silently
        foreach ($pkg in $toUpdate) {
            try {
                $wingetArgs = @(
                    'upgrade',
                    '--accept-source-agreements',
                    '--accept-package-agreements',
                    '--include-unknown',
                    '--disable-interactivity',
                    '--force'
                )

                if ($pkg.PackageIdentifier) {
                    $wingetArgs += @('--id', $pkg.PackageIdentifier, '-e')
                } elseif ($pkg.PackageName) {
                    $wingetArgs += @('--name', $pkg.PackageName, '-e')
                } else {
                    continue
                }

                if ($pkg.Source) {
                    $wingetArgs += @('--source', $pkg.Source)
                }

                & winget @wingetArgs *> $null
                $exit = $LASTEXITCODE

                # 0 = success; 0x8a150037 = nothing to update
                if (($exit -ne 0) -and ($exit -ne 0x8a150037)) {
                    $n = if ($pkg.PackageName) { $pkg.PackageName } else { $pkg.PackageIdentifier }
                    Invoke-Log ("Winget: failed to update '{0}' (id: {1}) code 0x{2:x}" -f $n, $pkg.PackageIdentifier, $exit)
                }
            } catch {
                $n = if ($pkg.PackageName) { $pkg.PackageName } else { $pkg.PackageIdentifier }
                Invoke-Log ("Winget: exception updating '{0}' (id: {1}) - {2}" -f $n, $pkg.PackageIdentifier, $_.Exception.Message)
            }
        }
    } catch {
        Invoke-Log ("Winget: general exception in Update-WingetApps - {0}" -f $_.Exception.Message)
    } finally {
        # Restore original preferences
        $ErrorActionPreference = $origErr
        $ProgressPreference    = $origProg
        $InformationPreference = $origInfo
    }
}