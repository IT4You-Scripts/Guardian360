
<#
.SYNOPSIS
    Verifica e corrige Winget, instala PowerShell 7, ajusta PATH, cria alias, restaura políticas e associa .ps1 corretamente.
.DESCRIPTION
    Script corporativo para manutenção avançada com validação de administrador.
.NOTES
    Autor: [Seu Nome]
    Data: 16/01/2026
#>

function Show-Message {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

# ==========================
# Validação de Administrador
# ==========================
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Show-Message "❌ Este script precisa ser executado como ADMINISTRADOR para aplicar todas as configurações." "Red"
    Show-Message "➡ Clique com o botão direito no PowerShell e selecione 'Executar como administrador'." "Yellow"
    exit
}

# ==========================
# Funções Winget
# ==========================
function Test-Winget {
    try {
        $wingetVersion = winget --version 2>$null
        if (-not $wingetVersion) {
            Show-Message "❌ Winget não está funcional." "Red"
            return $false
        }
        Show-Message "✅ Winget encontrado. Versão: $wingetVersion" "Green"

        # Teste real
        try {
            $result = winget list --source winget 2>$null
            if ($result) {
                Show-Message "✅ Teste real OK: Winget list executado." "Green"
                return $true
            } else {
                Show-Message "⚠ Winget não conseguiu listar pacotes." "Yellow"
                return $false
            }
        } catch {
            Show-Message "❌ Erro no teste real: $_" "Red"
            return $false
        }
    } catch {
        Show-Message "❌ Erro ao executar Winget: $_" "Red"
        return $false
    }
}

function Remove-Winget {
    Show-Message "🔄 Removendo Winget e App Installer..." "Yellow"
    try {
        Get-AppxPackage Microsoft.DesktopAppInstaller | Remove-AppxPackage -ErrorAction SilentlyContinue
        Get-AppxPackage Microsoft.VCLibs* | Remove-AppxPackage -ErrorAction SilentlyContinue
        Remove-Item "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller*" -Recurse -Force -ErrorAction SilentlyContinue
        Show-Message "✅ Remoção completa." "Green"
    } catch {
        Show-Message "❌ Erro na remoção: $_" "Red"
    }
}

function Install-Winget {
    Show-Message "⬇ Baixando e instalando Winget mais recente..." "Yellow"
    $InstallerUrl = "https://aka.ms/getwinget"
    $InstallerPath = "$env:TEMP\AppInstaller.msixbundle"
    $retryCount = 0
    do {
        try {
            Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath -ErrorAction Stop
            Add-AppxPackage -Path $InstallerPath -ErrorAction Stop
            Show-Message "✅ Instalação concluída." "Green"
            return
        } catch {
            $retryCount++
            Show-Message "❌ Erro na instalação (tentativa $retryCount): $_" "Red"
            Start-Sleep -Seconds 5
        }
    } while ($retryCount -lt 3)
    Show-Message "❌ Falha após 3 tentativas." "Red"
}

# ==========================
# Execução Winget
# ==========================
Show-Message "===== Verificando Winget =====" "Cyan"
if (-not (Test-Winget)) {
    Show-Message "⚠ Winget com problemas. Iniciando reparo..." "Yellow"
    Remove-Winget
    Install-Winget
    if (Test-Winget) {
        Show-Message "✅ Winget reparado com sucesso!" "Green"
    } else {
        Show-Message "❌ Falha ao reparar Winget." "Red"
    }
}

# ==========================
# Instala PowerShell 7
# ==========================
Show-Message "===== Instalando PowerShell 7 =====" "Cyan"
winget install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements

$pwshPath = "C:\Program Files\PowerShell\7\pwsh.exe"
Start-Sleep -Seconds 5

if (Test-Path $pwshPath) {
    Show-Message "✅ PowerShell 7 instalado em $pwshPath" "Green"
} else {
    Show-Message "❌ Erro: PowerShell 7 não encontrado." "Red"
    exit
}

# ==========================
# Checagem da variável de ambiente
# ==========================
Show-Message "===== Checando variável de ambiente %ProgramFiles% =====" "Cyan"
$envProgramFiles = $env:ProgramFiles
$expectedPath = Join-Path $envProgramFiles "PowerShell\7\pwsh.exe"
if (Test-Path $expectedPath) {
    Show-Message "✅ Caminho encontrado: $expectedPath" "Green"
} else {
    Show-Message "❌ Caminho não encontrado: $expectedPath" "Red"
}

# ==========================
# Ajustes no PATH
# ==========================
Show-Message "🔄 Adicionando PowerShell 7 ao PATH..." "Yellow"
$envPath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
if ($envPath -notlike "*PowerShell\7*") {
    $newPath = "$envPath;$($pwshPath.Substring(0,$pwshPath.LastIndexOf('\')))"
    [System.Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
    Show-Message "✅ PATH atualizado." "Green"
} else {
    Show-Message "⚠ PowerShell 7 já está no PATH." "Yellow"
}

# Cria alias
Show-Message "🔄 Criando alias para usar PowerShell 7 como padrão..." "Yellow"
try {
    fsutil behavior set SymlinkEvaluation R2L:1 R2R:1
    New-Item -Path "C:\Windows\System32\powershell.exe" -ItemType SymbolicLink -Value $pwshPath -Force
    Show-Message "✅ Alias criado: 'powershell' agora abre PowerShell 7." "Green"
} catch {
    Show-Message "❌ Erro ao criar alias. Execute como administrador." "Red"
}

# ==========================
# Associação .ps1 corrigida
# ==========================
Show-Message "🔄 Associando arquivos .ps1 ao PowerShell 7..." "Yellow"
cmd /c assoc .ps1=Microsoft.PowerShellScript.1
cmd /c ftype Microsoft.PowerShellScript.1="\"$pwshPath\" -NoExit -Command \"%1\""
Show-Message "✅ Associação aplicada. Valide com 'assoc .ps1' e 'ftype Microsoft.PowerShellScript.1'." "Green"

# Restaurar políticas
Show-Message "🔄 Restaurando políticas de execução..." "Yellow"
Set-ExecutionPolicy Undefined -Scope LocalMachine -Force
Set-ExecutionPolicy Undefined -Scope CurrentUser -Force
Set-ExecutionPolicy Undefined -Scope Process -Force
Set-ExecutionPolicy RemoteSigned -Force

Show-Message "✅ Script concluído com sucesso!" "Green"

