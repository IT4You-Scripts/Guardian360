# Cria regras no Firewall do Windows para bloquear atualização do QGIS 
function Block-AppUpdates {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string[]]$ExecutablePaths,
        [Parameter(Mandatory = $false)]
        [switch]$AlsoInbound
    )

    # Helper function to add firewall rule
    function Add-BlockRule {
        param (
            [string]$DisplayName,
            [string]$Program,
            [string]$Direction
        )

        # Check if rule already exists
        $existingRule = Get-NetFirewallRule -DisplayName $DisplayName -ErrorAction SilentlyContinue
        if ($existingRule) {
            Write-Host "Regra '$DisplayName' já existe. Pulando criação."
            return
        }

        # Try New-NetFirewallRule
        try {
            New-NetFirewallRule -DisplayName $DisplayName -Direction $Direction -Action Block -Program $Program -Profile Any -ErrorAction Stop
            Write-Host "Regra '$DisplayName' criada com sucesso."
        }
        catch {
            # Fallback to netsh
            Write-Host "Tentando fallback para netsh para '$DisplayName'..."
            $netshDirection = if ($Direction -eq 'Outbound') { 'out' } else { 'in' }
            $netshCommand = "netsh advfirewall firewall add rule name=""$DisplayName"" dir=$netshDirection action=block program=""$Program"" profile=any"
            Invoke-Expression $netshCommand
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Regra '$DisplayName' criada via netsh."
            } else {
                Write-Host "Falha ao criar regra '$DisplayName' via netsh."
            }
        }
    }

    # Define Write-Log fallback
    if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
        function Write-Log { param([string]$Message) }
    }

    # Check if running as Administrator
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "Aviso: Este script deve ser executado como Administrador para criar regras de firewall."
        return
    }

    # Ensure Windows Firewall service is running
    $firewallService = Get-Service -Name MpsSvc -ErrorAction SilentlyContinue
    if ($firewallService.Status -ne 'Running') {
        Start-Service -Name MpsSvc
        Write-Host "Serviço de Firewall do Windows iniciado."
    }

    # Collect candidate paths
    $candidatePaths = @()

    # Discover via registry
    $registryRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    foreach ($root in $registryRoots) {
        try {
            $subkeys = Get-ChildItem -Path $root -ErrorAction SilentlyContinue
            foreach ($subkey in $subkeys) {
                $displayName = (Get-ItemProperty -Path $subkey.PSPath -Name DisplayName -ErrorAction SilentlyContinue).DisplayName
                if ($displayName -and $displayName -like '*QGIS*') {
                    $installLocation = (Get-ItemProperty -Path $subkey.PSPath -Name InstallLocation -ErrorAction SilentlyContinue).InstallLocation
                    if (-not $installLocation) {
                        $displayIcon = (Get-ItemProperty -Path $subkey.PSPath -Name DisplayIcon -ErrorAction SilentlyContinue).DisplayIcon
                        if ($displayIcon) {
                            $installLocation = Split-Path -Path $displayIcon -Parent
                        } else {
                            $uninstallString = (Get-ItemProperty -Path $subkey.PSPath -Name UninstallString -ErrorAction SilentlyContinue).UninstallString
                            if ($uninstallString -and -not ($uninstallString -like 'msiexec*')) {
                                if ($uninstallString.StartsWith('"')) {
                                    $uninstallString = $uninstallString.TrimStart('"').Split('"')[0]
                                }
                                $installLocation = Split-Path -Path $uninstallString -Parent
                                if ($installLocation.EndsWith('uninstall')) {
                                    $installLocation = Split-Path -Path $installLocation -Parent
                                }
                            }
                        }
                    }
                    if ($installLocation -and (Test-Path -Path $installLocation)) {
                        $candidatePaths += $installLocation
                    }
                }
            }
        } catch {
            Write-Log "Erro ao acessar registro: $_"
        }
    }

    # Add default search roots
    $defaultRoots = @(
        "$env:ProgramFiles\QGIS*",
        "$env:ProgramFiles(x86)\QGIS*",
        'C:\OSGeo4W64',
        'C:\OSGeo4W'
    )
    foreach ($root in $defaultRoots) {
        if (Test-Path -Path $root) {
            $candidatePaths += $root
        }
    }

    # If ExecutablePaths provided, add them
    if ($ExecutablePaths) {
        foreach ($path in $ExecutablePaths) {
            if (Test-Path -Path $path -PathType Leaf) {
                $candidatePaths += Split-Path -Path $path -Parent
            } elseif (Test-Path -Path $path -PathType Container) {
                $candidatePaths += $path
            }
        }
    }

    # Deduplicate paths
    $candidatePaths = $candidatePaths | Select-Object -Unique

    # Find executables
    $executables = @()
    $patterns = @('qgis*-bin.exe', 'maintenancetool.exe', 'osgeo4w-setup*.exe')

    foreach ($path in $candidatePaths) {
        $binPath = Join-Path -Path $path -ChildPath 'bin'
        if (Test-Path -Path $binPath) {
            $searchPath = $binPath
        } else {
            $searchPath = $path
        }
        foreach ($pattern in $patterns) {
            $found = Get-ChildItem -Path $searchPath -Filter $pattern -Recurse -ErrorAction SilentlyContinue
            foreach ($file in $found) {
                $executables += $file.FullName
            }
        }
    }

    # Deduplicate executables
    $executables = $executables | Select-Object -Unique

    # Create rules
    foreach ($exe in $executables) {
        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($exe)
        $outboundName = "Bloqueio_Update_QGIS_$fileName"
        Add-BlockRule -DisplayName $outboundName -Program $exe -Direction 'Outbound'
        if ($AlsoInbound) {
            $inboundName = "Bloqueio_Update_QGIS_IN_$fileName"
            Add-BlockRule -DisplayName $inboundName -Program $exe -Direction 'Inbound'
        }
    }

    #Write-Host "Processo concluído. Verifique as regras de firewall criadas."
}
