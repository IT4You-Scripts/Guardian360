# Script: CriaCredenciais_AES.ps1
# Descrição: Gera chave AES, aplica ACLs e salva credenciais criptografadas.

param (
    [bool]$GrantUsersRead = $true,
    [switch]$ForceRepair
)

# Função para reparar ACL da chave
function Repair-KeyAcl {
    param ([string]$Path)
    try {
        # Toma posse com takeown (define owner para Administrators)
        & takeown /A "$Path" 2>$null

        # Cria novo objeto de segurança sem herança
        $fileSecurity = New-Object System.Security.AccessControl.FileSecurity
        $fileSecurity.SetAccessRuleProtection($true, $false)

        # Define owner por SID (S-1-5-32-544 = Administrators)
        try {
            $adminSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
            $fileSecurity.SetOwner($adminSid)
        } catch {
            # Se SetOwner falhar, prossegue — takeown já definiu o proprietário
        }

        # Regras: Administrators e SYSTEM FullControl
        if (-not $adminSid) { $adminSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544") }
        $systemSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")

        $ruleAdmins = New-Object System.Security.AccessControl.FileSystemAccessRule($adminSid, "FullControl", "Allow")
        $ruleSystem = New-Object System.Security.AccessControl.FileSystemAccessRule($systemSid, "FullControl", "Allow")
        $fileSecurity.AddAccessRule($ruleAdmins)
        $fileSecurity.AddAccessRule($ruleSystem)

        # Opcional: Users Read (S-1-5-32-545)
        if ($GrantUsersRead) {
            $usersSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-545")
            $ruleUsers = New-Object System.Security.AccessControl.FileSystemAccessRule($usersSid, "Read", "Allow")
            $fileSecurity.AddAccessRule($ruleUsers)
        }

        # Aplica ACL
        Set-Acl -Path $Path -AclObject $fileSecurity

        # Remove atributo ReadOnly se existir
        $item = Get-Item $Path
        if ($item.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
            $item.Attributes = $item.Attributes -bxor [System.IO.FileAttributes]::ReadOnly
        }

        Write-Host "ACL reparada com sucesso."
    } catch {
        Write-Host "Falha ao reparar ACL: $($_.Exception.Message)"
        exit 1
    }
}

# Verifica execução como Administrador
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Este script deve ser executado como administrador."
    exit 1
}

# Caminhos
$Folder   = 'C:\IT4You'
$KeyPath  = 'C:\IT4You\key.bin'
$CredPath = 'C:\IT4You\credenciais.xml'

# Garante pasta
if (-not (Test-Path $Folder)) {
    try {
        New-Item -ItemType Directory -Path $Folder -Force | Out-Null
        Write-Host "Pasta $Folder criada."
    } catch {
        Write-Host "Falha ao criar pasta: $($_.Exception.Message)"
        exit 1
    }
}

# Gera chave se não existir
if (-not (Test-Path $KeyPath)) {
    try {
        $keyBytes = New-Object byte[] 32
        [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($keyBytes)
        [IO.File]::WriteAllBytes($KeyPath, $keyBytes)
        Write-Host "Chave AES gerada."
    } catch {
        Write-Host "Falha ao gerar chave: $($_.Exception.Message)"
        exit 1
    }

    # Aplica ACL inicial
    Repair-KeyAcl -Path $KeyPath
}

# Força reparo manual se solicitado
if ($ForceRepair) {
    Repair-KeyAcl -Path $KeyPath
}

# Lê a chave, tenta reparar ACL em caso de Access Denied
try {
    $keyBytes = [IO.File]::ReadAllBytes($KeyPath)
} catch {
    Write-Host "Erro ao ler chave. Tentando reparar ACL..."
    Repair-KeyAcl -Path $KeyPath
    try {
        $keyBytes = [IO.File]::ReadAllBytes($KeyPath)
    } catch {
        Write-Host "Falha ao ler chave após reparo: $($_.Exception.Message)"
        exit 1
    }
}

# Coleta credenciais e salva XML
try {
    $cred = Get-Credential -Message "Digite as credenciais para criptografar"
    if (-not $cred) { Write-Host "Credenciais não fornecidas."; exit 1 }

    $encryptedPassword = ConvertFrom-SecureString -SecureString $cred.Password -Key $keyBytes

    # Salva em XML simples (sem depender de Export-Clixml do objeto PSCustomObject)
    $xml = @"
<Credenciais>
  <UserName>$($cred.UserName)</UserName>
  <EncryptedPassword>$encryptedPassword</EncryptedPassword>
</Credenciais>
"@
    [IO.File]::WriteAllText($CredPath, $xml, [Text.Encoding]::UTF8)

    Write-Host "Credenciais criptografadas salvas em $CredPath."
} catch {
    Write-Host "Falha ao salvar credenciais: $($_.Exception.Message)"
    exit 1
}