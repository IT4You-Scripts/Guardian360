
<#
.SYNOPSIS
    Verifica e corrige Winget, instala PowerShell 7, ajusta PATH, cria alias, restaura políticas e valida associação .ps1.
.DESCRIPTION
    Script corporativo com saída limpa e resumo final.
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

# Variáveis de status
$WingetStatus = $PowerShellStatus = $PathStatus = $AliasStatus = $AssocStatus = $PolicyStatus = "❌"

# ==========================
# Funções Winget
# ==========================
function Test-Winget {
    try {
        $wingetVersion = winget --version 2>$null
        if (-not $wingetVersion) { return $false }
        try {
            $result = winget list --source winget 2>$null
            return $result -ne $null
        } catch { return $false }
    } catch { return $false }
}

function Remove-Winget {
    Get-AppxPackage Microsoft.DesktopAppInstaller | Remove-AppxPackage -ErrorAction SilentlyContinue
    Get-AppxPackage Microsoft.VCLibs* | Remove-AppxPackage -ErrorAction SilentlyContinue
    Remove-Item "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller*" -Recurse -Force -ErrorAction SilentlyContinue
}

function Install-Winget {
    $InstallerUrl = "https://aka.ms/getwinget"
    $InstallerPath = "$env:TEMP\AppInstaller.msixbundle"
    Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath -ErrorAction Stop
    Add-AppxPackage -Path $InstallerPath -ErrorAction Stop
}

# ==========================
# Execução Winget
# ==========================
Show-Message "===== Verificando Winget =====" "Cyan"
if (-not (Test-Winget)) {
    Show-Message "⚠ Winget com problemas. Reparando..." "Yellow"
    Remove-Winget
    Install-Winget
}
if (Test-Winget) {
    Show-Message "✅ Winget OK" "Green"
    $WingetStatus = "✔ Winget OK"
} else {
    Show-Message "❌ Winget falhou" "Red"
}

# ==========================
# Instala PowerShell 7
# ==========================
Show-Message "===== Instalando PowerShell 7 =====" "Cyan"
winget install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements
$pwshPath = "C:\Program Files\PowerShell\7\pwsh.exe"
Start-Sleep -Seconds 5
if (Test-Path $pwshPath) {
    Show-Message "✅ PowerShell 7 OK" "Green"
    $PowerShellStatus = "✔ PowerShell 7 OK"
} else {
    Show-Message "❌ PowerShell não encontrado" "Red"
}

# ==========================
# Checagem variável ambiente
# ==========================
$expectedPath = Join-Path $env:ProgramFiles "PowerShell\7\pwsh.exe"
if (Test-Path $expectedPath) {
    Show-Message "✅ Caminho verificado: $expectedPath" "Green"
}

# ==========================
# Ajustes no PATH
# ==========================
$envPath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
if ($envPath -notlike "*PowerShell\7*") {
    $newPath = "$envPath;$($pwshPath.Substring(0,$pwshPath.LastIndexOf('\')))"
    [System.Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
    Show-Message "✅ PATH atualizado" "Green"
    $PathStatus = "✔ PATH OK"
} else {
    Show-Message "⚠ PATH já contém PowerShell 7" "Yellow"
    $PathStatus = "✔ PATH OK"
}

# ==========================
# Alias
# ==========================
try {
    fsutil behavior set SymlinkEvaluation R2L:1 R2R:1
    New-Item -Path "C:\Windows\System32\powershell.exe" -ItemType SymbolicLink -Value $pwshPath -Force
    Show-Message "✅ Alias criado" "Green"
    $AliasStatus = "✔ Alias OK"
} catch {
    Show-Message "❌ Erro ao criar alias" "Red"
}

# ==========================
# Associação .ps1 + validação (sem mensagem indesejada)
# ==========================
Show-Message "🔄 Associando arquivos .ps1 ao PowerShell 7..." "Yellow"
cmd /c assoc .ps1=Microsoft.PowerShellScript.1 > nul 2>&1
cmd /c ftype Microsoft.PowerShellScript.1="\"$pwshPath\" -NoExit -Command \"%1\"" > nul 2>&1

# Validação da associação
$assocResult = cmd /c assoc .ps1
$ftypeResult = cmd /c ftype Microsoft.PowerShellScript.1
if ($assocResult -like "*.ps1=*Microsoft.PowerShellScript.1*" -and $ftypeResult -like "*pwsh.exe*") {
    Show-Message "✅ Associação .ps1 OK" "Green"
    $AssocStatus = "✔ Associação .ps1 OK"
} else {
    Show-Message "❌ Associação falhou" "Red"
}

# ==========================
# Restaurar políticas
# ==========================
Set-ExecutionPolicy Undefined -Scope LocalMachine -Force
Set-ExecutionPolicy Undefined -Scope CurrentUser -Force
Set-ExecutionPolicy Undefined -Scope Process -Force
Set-ExecutionPolicy RemoteSigned -Force
Show-Message "✅ Políticas restauradas" "Green"
$PolicyStatus = "✔ Políticas OK"

# ==========================
# Resumo Final
# ==========================
Show-Message "`n===== RESUMO FINAL =====" "Cyan"
Show-Message "$WingetStatus" "Green"
Show-Message "$PowerShellStatus" "Green"
Show-Message "$PathStatus" "Green"
Show-Message "$AliasStatus" "Green"
Show-Message "$AssocStatus" "Green"
Show-Message "$PolicyStatus" "Green"
Show-Message "✅ Script concluído com sucesso!" "Green"
