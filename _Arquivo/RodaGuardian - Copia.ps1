
# RodaGuardian.ps1
[CmdletBinding()]
param (
    # Caminho do PowerShell 7
    [string]$PwshPath = (Get-Command pwsh).Source,
    # Caminho do script principal Guardian
    [string]$ScriptPath = 'C:\Guardian\Guardian.ps1',

    # Opções de janela
    [switch]$NoWindow,
    [switch]$NonInteractive,
    [switch]$Maximized,

    # Parâmetros para Guardian.ps1
    [int[]]$ExecutaFases,
    [int[]]$PulaFases,

    [ValidateSet('INFO','WARN','ERROR','DEBUG')]
    [string]$LogLevel,
    [switch]$Simulado,
    [string]$FileServer,
    [string]$Cliente
)

# Oculta o console do proprio launcher na execucao normal.
# A LiveUI e uma janela WPF independente e permanece visivel.
if (-not $PSBoundParameters.ContainsKey('Debug') -and -not $Maximized) {
    try {
        if (-not ('GuardianLauncherConsoleVisibility' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class GuardianLauncherConsoleVisibility {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
'@ -ErrorAction Stop
        }
        $launcherConsole = [GuardianLauncherConsoleVisibility]::GetConsoleWindow()
        if ($launcherConsole -ne [IntPtr]::Zero) {
            [void][GuardianLauncherConsoleVisibility]::ShowWindow($launcherConsole, 0)
        }
    } catch { }
}

# -------------------------------
# Função para cabeçalho estilizado
# -------------------------------
function Show-Header {
    param(
        [string]$Text,
        [ConsoleColor]$Color = 'Cyan'
    )

    $bar = '─' * ($Text.Length + 2)
    Write-Host ""
    Write-Host ("┌$bar┐") -ForegroundColor $Color
    Write-Host ("│ $Text │") -ForegroundColor $Color
    Write-Host ("└$bar┘") -ForegroundColor $Color
    Write-Host ""
}

# -------------------------------
# Função de falha controlada
# -------------------------------
function Fail {
    param ([string]$Message)
    Show-Header $Message -Color Red
    Write-Host "O script será encerrado em 5 segundos..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    exit 1
}



# =========================================================================
# VERIFICAÇÃO SILENCIOSA — Já rodou neste mês?
# Se sim, aborta imediatamente sem atualizar nada, sem mostrar nada.
# =========================================================================
$guardianJsonPath = "C:\Guardian\guardian.json"
if (Test-Path $guardianJsonPath) {
    try {
        $guardianData = Get-Content $guardianJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($guardianData.ultima_execucao) {
            $ultimaExecucao = [datetime]::Parse($guardianData.ultima_execucao)
            $agora = Get-Date

            # Mesmo mês e mesmo ano: Guardian já executou, então encerra.
            if ($ultimaExecucao.Year -eq $agora.Year -and
                $ultimaExecucao.Month -eq $agora.Month) {
                exit 0
            }
        }
    }
    catch {}
}
# =========================================================================


# =========================================================================
# VERIFICACAO RAPIDA — Ja ha um Guardian em execucao neste computador?
# O Guardian.ps1 mantem C:\Guardian\guardian.lock aberto (acesso exclusivo) enquanto roda.
# Aqui apenas se testa se o arquivo esta em uso; nada e criado nem gravado.
# Somente "arquivo em uso" encerra: arquivo inexistente ou sem permissao seguem normalmente
# (a trava definitiva fica no Guardian.ps1).
# =========================================================================
try {
    $lockProbe = [System.IO.File]::Open(
        'C:\Guardian\guardian.lock',
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite)
    $lockProbe.Dispose()
} catch [System.IO.IOException] {
    # 32 = ERROR_SHARING_VIOLATION, 33 = ERROR_LOCK_VIOLATION
    if (($_.Exception.HResult -band 0xFFFF) -in @(32, 33)) { exit 0 }
} catch { }
# =========================================================================


# -------------------------------------------------------------------------------------------------------------------------
#region BootStrap - Atualiza somente o arquivo Update-GuardianFiles.ps1 — versão mínima e silenciosa
# -------------------------------------------------------------------------------------------------------------------------

$BaseUrl  = "https://raw.githubusercontent.com/IT4You-Scripts/Guardian360/main/Functions/Update-GuardianFiles.ps1"
$DestPath = "C:\Guardian\Functions\Update-GuardianFiles.ps1"
$NoCache  = "?nocache=$(Get-Date -Format 'yyyyMMddHHmmss')"

# Remove o arquivo antigo
# Remove-Item -Path $DestPath -Force -ErrorAction SilentlyContinue

# Baixa o novo arquivo
Invoke-WebRequest -Uri ($BaseUrl + $NoCache) `
                  -OutFile $DestPath `
                  -UseBasicParsing `
                  -ErrorAction SilentlyContinue


# Atualização dos arquivos do Guardian 360 usando a função Update-GuardianFiles.ps1, que foi atualizada no cod acima
$updater = "C:\Guardian\Functions\Update-GuardianFiles.ps1"
if (Test-Path $updater) {
    . $updater
    Update-GuardianFiles
}

#endregion






# -------------------------------
# Validações
# -------------------------------
if (-not (Test-Path -LiteralPath $PwshPath))   { Fail "PowerShell 7 não encontrado em: $PwshPath" }
if (-not (Test-Path -LiteralPath $ScriptPath)) { Fail "Guardian.ps1 não encontrado em: $ScriptPath" }

# Desbloqueia o script alvo
try { Unblock-File -Path $ScriptPath -ErrorAction SilentlyContinue } catch {}

# Diretório de trabalho
$workDir = Split-Path -Path $ScriptPath -Parent

# -------------------------------
# Montagem segura dos argumentos
# -------------------------------
$argList = @('-ExecutionPolicy','Bypass','-NoProfile','-File',$ScriptPath)
if ($NonInteractive) { $argList += '-NonInteractive' }
if ($ExecutaFases)   { $argList += '-ExecutaFases'; $argList += ($ExecutaFases -join ',') }
if ($PulaFases)      { $argList += '-PulaFases'; $argList += ($PulaFases -join ',') }
if ($LogLevel)       { $argList += '-LogLevel'; $argList += $LogLevel }
if ($Simulado)       { $argList += '-Simulado' }
if ($FileServer)     { $argList += '-FileServer'; $argList += $FileServer }
if ($Cliente)        { $argList += '-Cliente'; $argList += "`"$Cliente`"" }
if ($PSBoundParameters.ContainsKey('Debug')) { $argList += '-Debug' }

# -------------------------------
# Configuração da janela
# -------------------------------
$winStyle = if ($NoWindow) { 'Hidden' } elseif ($Maximized) { 'Maximized' } elseif ($PSBoundParameters.ContainsKey('Debug')) { 'Normal' } else { 'Hidden' }

# -------------------------------
# Log do comando final para debug
# -------------------------------
Show-Header "Comando final:" -Color Yellow
Write-Host "$PwshPath $($argList -join ' ')" -ForegroundColor Cyan

# -------------------------------
# Execução do Guardian
# -------------------------------
Push-Location $workDir
try {
    $argStringGuardian = ($argList | ForEach-Object {
        if ($_ -match '\s') { '"{0}"' -f ($_ -replace '"','\"') } else { $_ }
    }) -join ' '

    $procGuardian = Start-Process `
        -FilePath $PwshPath `
        -ArgumentList $argStringGuardian `
        -WorkingDirectory $workDir `
        -WindowStyle $winStyle `
        -PassThru

    # Aguarda apenas o processo Guardian iniciado, nao todos os descendentes.
    $procGuardian.WaitForExit()

    Show-Header "Guardian executado com sucesso!" -Color Green
} catch {
    Fail "Falha ao iniciar o Guardian.ps1: $($_.Exception.Message)"
}
Pop-Location
