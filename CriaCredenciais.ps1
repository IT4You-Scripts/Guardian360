
# Script: CriaCredenciais_DPAPI.ps1
# Descrição: Criptografa credenciais usando DPAPI (sem chave manual) e salva em XML.

# Caminhos
$Folder   = 'C:\Guardian'
$CredPath = 'C:\Guardian\credenciais.xml'

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

# Criptografa a senha usando DPAPI (escopo: usuário atual)
try {
    $encryptedPassword = ConvertFrom-SecureString -SecureString $cred.Password -Scope LocalMachine
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
