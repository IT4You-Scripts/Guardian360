# Script para Restaurar Politicas e Limpar pastas

Show-Info "Iniciando script..."

# Instala a Ultima versao do PowerShell via winget
Write-Host "Instalando PowerShell mais recente..." -ForegroundColor Cyan
winget install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements

# Caminho padrao do PowerShell 7
$pwshPath = "C:\Program Files\PowerShell\7\pwsh.exe"

# Aguarda instalacao
Start-Sleep -Seconds 5

# Verifica se o executavel existe
if (Test-Path $pwshPath) {
    Write-Host "PowerShell 7 instalado com sucesso em $pwshPath" -ForegroundColor Green
} else {
    Write-Host "Erro: PowerShell 7 nao encontrado. Verifique a instalacao." -ForegroundColor Red
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
    Write-Host "PowerShell 7 ja esta no PATH." -ForegroundColor Yellow
}

# Cria alias para substituir o comando 'powershell' pelo novo 'pwsh'
Write-Host "Criando alias para usar PowerShell 7 como padrao..." -ForegroundColor Cyan
try {
    # Habilita links simbolicos (necessario para criar alias)
    fsutil behavior set SymlinkEvaluation R2L:1 R2R:1
    # Cria link simbolico
    New-Item -Path "C:\Windows\System32\powershell.exe" -ItemType SymbolicLink -Value $pwshPath -Force
    Write-Host "Alias criado: 'powershell' agora abre PowerShell 7." -ForegroundColor Green
} catch {
    Write-Host "Erro ao criar alias. Execute como administrador e verifique permissoes." -ForegroundColor Red
}

# Exibe versao instalada
Write-Host "Verificando versao do PowerShell..." -ForegroundColor Cyan
& $pwshPath -Command { $PSVersionTable.PSVersion }

# Caminho do PowerShell 7 (redundante, mas mantido)
$pwshPath = "C:\Program Files\PowerShell\7\pwsh.exe"

# Associa .ps1 ao PowerShell 7
cmd /c assoc .ps1=Microsoft.PowerShellScript.1
cmd /c ftype Microsoft.PowerShellScript.1="\"C:\Program Files\PowerShell\7\pwsh.exe\" -NoExit -Command \"%1\""

# Funcoes para mensagens
function Show-Info($text) { Write-Host $text }
function Show-Error($text) { Write-Host ($text.ToUpper()) -ForegroundColor White -BackgroundColor Red }

# Restaurar politicas
Set-ExecutionPolicy Undefined -Scope LocalMachine -Force
Set-ExecutionPolicy Undefined -Scope CurrentUser -Force
Set-ExecutionPolicy Undefined -Scope Process -Force
Set-ExecutionPolicy RemoteSigned -Force
Show-Info "Script concluido."
