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

    foreach ($profile in (Get-ChildItem -LiteralPath $profileList -ErrorAction SilentlyContinue)) {
        $sid = $profile.PSChildName

        # SIDs de usuarios locais/dominio; ignora SYSTEM, LocalService etc.
        if ($sid -notmatch '^S-1-5-21-.+-\d+$') { continue }

        $loadedHere = $false
        $tempHiveName = $null

        try {
            $profilePath = (Get-ItemProperty -LiteralPath $profile.PSPath -Name ProfileImagePath -ErrorAction Stop).ProfileImagePath
            $profilePath = [Environment]::ExpandEnvironmentVariables($profilePath)
            if (-not (Test-Path -LiteralPath $profilePath -PathType Container)) { continue }

            $userRoot = "Registry::HKEY_USERS\$sid"

            if (-not (Test-Path -LiteralPath $userRoot)) {
                $ntUser = Join-Path $profilePath 'NTUSER.DAT'
                if (-not (Test-Path -LiteralPath $ntUser -PathType Leaf)) { continue }

                $tempHiveName = "GuardianGhost_$($sid -replace '[^A-Za-z0-9_]', '_')"
                & reg.exe load "HKU\$tempHiveName" "$ntUser" 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { continue }

                $loadedHere = $true
                $userRoot = "Registry::HKEY_USERS\$tempHiveName"
            }

            $defaultsPath = "$userRoot\SOFTWARE\Macrium\reflect\Defaults"

            # Nao cria Defaults em usuario que nunca teve configuracao do Macrium.
            if (Test-Path -LiteralPath $defaultsPath) {
                foreach ($item in $desired.GetEnumerator()) {
                    $current = (Get-ItemProperty -LiteralPath $defaultsPath -Name $item.Key -ErrorAction SilentlyContinue).($item.Key)

                    if ($null -eq $current -or [int64]$current -ne [int64]$item.Value) {
                        New-ItemProperty -LiteralPath $defaultsPath `
                            -Name $item.Key `
                            -Value ([int]$item.Value) `
                            -PropertyType DWord `
                            -Force `
                            -ErrorAction Stop | Out-Null
                    }
                }
            }
        }
        catch {
            # Falha na configuracao do Macrium nao impede o restante do Ghost.
        }
        finally {
            if ($loadedHere -and $tempHiveName) {
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
