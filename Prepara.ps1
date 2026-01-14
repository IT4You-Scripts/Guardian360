
# ============================================================================
# SCRIPT PARA RESTAURAR POLITICAS, LIMPAR PASTA E COPIAR ARQUIVOS
# ============================================================================

# Forcar saida com UTF-8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Instala a última versão do PowerShell via winget
Write-Host "Instalando PowerShell mais recente..." -ForegroundColor Cyan
winget install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements

# Caminho padrão do PowerShell 7
$pwshPath = "C:\Program Files\PowerShell\7\pwsh.exe"

# Aguarda instalação
Start-Sleep -Seconds 5

# Verifica se o executável existe
if (Test-Path $pwshPath) {
    Write-Host "PowerShell 7 instalado com sucesso em $pwshPath" -ForegroundColor Green
} else {
    Write-Host "Erro: PowerShell 7 não encontrado. Verifique a instalação." -ForegroundColor Red
    exit
}

# Adiciona ao PATH do sistema
Write-Host "Adicionando PowerShell 7 ao PATH..." -ForegroundColor Cyan
$envPath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
if ($envPath -notlike "*PowerShell\7*") {
    $newPath = "$envPath;$($pwshPath.Substring(0,$pwshPath.LastIndexOf('\')))"
    [System.Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
    Write-Host "PATH atualizado com sucesso." -ForegroundColor Green
} else {
    Write-Host "PowerShell 7 já está no PATH." -ForegroundColor Yellow
}

# Cria alias para substituir o comando 'powershell' pelo novo 'pwsh'
Write-Host "Criando alias para usar PowerShell 7 como padrão..." -ForegroundColor Cyan
try {
    # Habilita links simbólicos (necessário para criar alias)
    fsutil behavior set SymlinkEvaluation R2L:1 R2R:1
    # Cria link simbólico
    New-Item -Path "C:\Windows\System32\powershell.exe" -ItemType SymbolicLink -Value $pwshPath -Force
    Write-Host "Alias criado: 'powershell' agora abre PowerShell 7." -ForegroundColor Green
} catch {
    Write-Host "Erro ao criar alias. Execute como administrador e verifique permissões." -ForegroundColor Red
}

# Exibe versão instalada
Write-Host "Verificando versão do PowerShell..." -ForegroundColor Cyan
& $pwshPath -Command { $PSVersionTable.PSVersion }

# Caminho do PowerShell 7 (redundante, mas mantido)
$pwshPath = "C:\Program Files\PowerShell\7\pwsh.exe"

# Associa .ps1 ao PowerShell 7
cmd /c assoc .ps1=Microsoft.PowerShellScript.1
cmd /c ftype Microsoft.PowerShellScript.1="\"C:\Program Files\PowerShell\7\pwsh.exe\" -NoExit -Command \"%1\""

# Funcoes para mensagens
function Show-Info($text) { Write-Host $text }
function Show-Error($text) { Write-Host ($text.ToUpper()) -ForegroundColor White -BackgroundColor Red }

Show-Info "Iniciando script..."

# Restaurar politicas
Set-ExecutionPolicy Undefined -Scope LocalMachine -Force
Set-ExecutionPolicy Undefined -Scope CurrentUser -Force
Set-ExecutionPolicy Undefined -Scope Process -Force
Set-ExecutionPolicy RemoteSigned -Force

Get-ExecutionPolicy -List


Show-Info "Script concluido."
