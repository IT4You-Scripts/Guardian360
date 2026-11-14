
# Script: CriaCredenciais_AES.ps1
# Descrição: Criptografa credenciais usando AES (com chave) e salva em XML.

# Caminhos
$Folder   = 'C:\Guardian'
$CredPath = 'C:\Guardian\credenciais.xml'
$KeyPath  = 'C:\Guardian\chave.key'

# Garante que a pasta existe
if (-not (Test-Path $Folder)) {
    try {
        New-Item -ItemType Directory -Path $Folder -Force | Out-Null
        Write-Host "Pasta $Folder criada."
    } catch {
        Write-Host "Falha ao criar pasta: $($_.Exception.Message)"
        exit 1
    }
}

# Solicita credenciais do usuário
try {
    $cred = Get-Credential -Message "Digite usuário e senha"
    if (-not $cred) {
        Write-Host "Credenciais não fornecidas."
        exit 1
    }
} catch {
    Write-Host "Erro ao coletar credenciais: $($_.Exception.Message)"
    exit 1
}

# Gera chave AES (32 bytes) se não existir
if (-not (Test-Path $KeyPath)) {
    $key = New-Object Byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($key)
    [IO.File]::WriteAllBytes($KeyPath, $key)
    Write-Host "Chave AES gerada e salva em $KeyPath."
} else {
    $key = [IO.File]::ReadAllBytes($KeyPath)
}

# Criptografa a senha usando AES
try {
    $encryptedPassword = ConvertFrom-SecureString -SecureString $cred.Password -Key $key
} catch {
    Write-Host "Erro ao criptografar senha: $($_.Exception.Message)"
    exit 1
}

# Monta XML com usuário e senha criptografada
$xml = @"
<Credenciais>
  <UserName>$($cred.UserName)</UserName>
  <EncryptedPassword>$encryptedPassword</EncryptedPassword>
</Credenciais>
"@

# Salva o XML no arquivo
try {
    [IO.File]::WriteAllText($CredPath, $xml, [Text.Encoding]::UTF8)
    Write-Host "Credenciais criptografadas salvas em $CredPath."
} catch {
    Write-Host "Falha ao salvar credenciais: $($_.Exception.Message)"
    exit 1
}
