#Requires -Version 7.0

<#
.SYNOPSIS
    Guardian Ghost - Fase 2 silenciosa (System Integrity)
.DESCRIPTION
    Executa o Repair-SystemIntegrity (DISM + SFC) de forma totalmente silenciosa,
    desvinculado do Guardian principal. Roda como SYSTEM via Agendador de Tarefas.
    Controle de execucao via guardian_ghost.json (1x por mes).
.AUTHOR
    Tato, IT4You Ltda
.VERSION
    1.0
#>

# ============================================================================
# CONFIGURACAO
# ============================================================================
$GhostJsonPath = "C:\Guardian\guardian_ghost.json"
$FuncDir       = "C:\Guardian\Functions"

# ============================================================================
# VERIFICACAO: ja rodou este mes?
# ============================================================================
if (Test-Path $GhostJsonPath) {
    try {
        $ghostData = Get-Content $GhostJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($ghostData.ultima_execucao) {
            $ultimaExecucao = [datetime]::Parse($ghostData.ultima_execucao)
            $agora = Get-Date

            # Se ja rodou no mesmo mes e ano, aborta
            if ($ultimaExecucao.Year -eq $agora.Year -and $ultimaExecucao.Month -eq $agora.Month) {
                exit 0
            }
        }
    }
    catch {
        # Se o JSON estiver corrompido, ignora e executa
    }
}

# ============================================================================
# ELEVACAO E POWERSHELL 7
# ============================================================================
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        $pwshPath = (Get-Command pwsh.exe -ErrorAction SilentlyContinue)?.Source
        if ($pwshPath) {
            Start-Process $pwshPath -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -WindowStyle Hidden
        }
        exit
    } catch {
        exit 1
    }
}

# ============================================================================
# FUNCAO WRITE-LOG SIMPLIFICADA (para compatibilidade com Repair-SystemIntegrity)
# ============================================================================
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )
    # Silencioso — nao grava nada, apenas satisfaz a chamada
}

# ============================================================================
# PADRONIZAR RETENCAO DO MACRIUM REFLECT
# Executado pelo Ghost como SYSTEM. Altera somente perfis reais que ja possuem
# a chave de Defaults do Macrium; nao altera definicoes XML de backup.
# ============================================================================
function Set-MacriumRetentionDefaults {
    $macriumExe = @(
        "$env:ProgramFiles\Macrium\Reflect\Reflect.exe",
        "${env:ProgramFiles(x86)}\Macrium\Reflect\Reflect.exe"
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } |
        Select-Object -First 1

    if (-not $macriumExe) { return }

    $desired = [ordered]@{
        FullRetention  = 1
        FullPeriod     = 0
        FullInterval   = 1
        DiffRetention  = 0
        PurgeBefore    = 1
        PurgeOldest    = 0
        PurgeThreshold = 5
    }

    $profileList = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    $profiles = Get-ChildItem -LiteralPath $profileList -ErrorAction Stop

    foreach ($profile in $profiles) {
        $sid = $profile.PSChildName

        # Mesma selecao de perfis humanos validada no teste isolado como SYSTEM.
        if ($sid -notmatch '^S-1-5-21-.+-\d+$') { continue }

        $loadedByUs = $false
        $tempHiveName = $null

        try {
            $profileInfo = Get-ItemProperty -LiteralPath $profile.PSPath -ErrorAction Stop
            $profilePath = [Environment]::ExpandEnvironmentVariables([string]$profileInfo.ProfileImagePath)

            if (-not (Test-Path -LiteralPath $profilePath -PathType Container)) { continue }

            $userRoot = "Registry::HKEY_USERS\$sid"

            if (-not (Test-Path -LiteralPath $userRoot)) {
                $ntUser = Join-Path $profilePath 'NTUSER.DAT'
                if (-not (Test-Path -LiteralPath $ntUser -PathType Leaf)) { continue }

                $safeSid = $sid -replace '[^A-Za-z0-9_-]', '_'
                $tempHiveName = "GuardianGhost_$safeSid"

                & reg.exe load "HKU\$tempHiveName" "$ntUser" 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { continue }

                $userRoot = "Registry::HKEY_USERS\$tempHiveName"
                $loadedByUs = $true
            }

            $defaultsPath = "$userRoot\SOFTWARE\Macrium\reflect\Defaults"

            # Nao cria Defaults em usuario que nunca teve configuracao do Macrium.
            if (-not (Test-Path -LiteralPath $defaultsPath)) { continue }

            # Gravacao direta: mesma forma validada no teste isolado como SYSTEM.
            foreach ($name in $desired.Keys) {
                New-ItemProperty `
                    -LiteralPath $defaultsPath `
                    -Name $name `
                    -Value ([int]$desired[$name]) `
                    -PropertyType DWord `
                    -Force `
                    -ErrorAction Stop | Out-Null
            }
        }
        catch {
            # Falha na configuracao do Macrium nao impede o restante do Ghost.
        }
        finally {
            if ($loadedByUs -and $tempHiveName) {
                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
                & reg.exe unload "HKU\$tempHiveName" 2>&1 | Out-Null
            }
        }
    }
}
try {
    Set-MacriumRetentionDefaults
}
catch {
    # Falha na configuracao do Macrium nao impede o Repair-SystemIntegrity.
}

# ============================================================================
# CARREGAR E EXECUTAR REPAIR-SYSTEMINTEGRITY
# ============================================================================
try {
    $repairPath = Join-Path $FuncDir "Repair-SystemIntegrity.ps1"
    if (-not (Test-Path $repairPath)) {
        exit 1
    }

    . $repairPath
    Repair-SystemIntegrity

    # ========================================================================
    # SUCESSO: Gravar guardian_ghost.json
    # ========================================================================
    $resultado = @{
        ultima_execucao = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    $resultado | ConvertTo-Json | Set-Content -Path $GhostJsonPath -Encoding UTF8 -Force

} catch {
    # Falha silenciosa — nao interrompe nada
    exit 1
}

exit 0
