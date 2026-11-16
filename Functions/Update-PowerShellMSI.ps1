# IT4YOU - Atualizacao silenciosa do PowerShell 7 por MSI (Windows x64)
# Executar como Administrador ou SYSTEM. -Silent oculta mensagens do script.
# Sem Winget, logs proprios ou reinicializacao automatica.
[CmdletBinding()]
param([switch]$Silent)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$msi = $null
$exitCode = 1
function Say([string]$message) { if (-not $Silent) { Write-Host $message } }
try {
    if (-not [Environment]::Is64BitProcess) { throw 'Execute no PowerShell x64.' }
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Execute com privilegios de Administrador ou SYSTEM.'
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $pwsh = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
    $installed = [version]'0.0.0'
    if (Test-Path -LiteralPath $pwsh) {
        $found = (Get-Item -LiteralPath $pwsh).VersionInfo.ProductVersion
        if ($found -notmatch '(\d+\.\d+\.\d+)') { throw "Versao instalada desconhecida: $found" }
        $installed = [version]$Matches[1]
    }

    # Fallback verificado no release oficial v7.6.10, caso o GitHub API nao forneca assets.
    $candidate = [pscustomobject]@{
        Version = [version]'7.6.10'
        Url = 'https://github.com/PowerShell/PowerShell/releases/download/v7.6.10/PowerShell-7.6.10-win-x64.msi'
        Sha256 = '7D8DAEA48B450D4D62FCD1AC4D6FAA7AC2DB5E11ABA5061EE81B7496ADCA8C07'
    }

    # Procura nas releases publicadas o MSI x64 da versao mais nova (sem prerelease).
    try {
        $headers = @{ 'User-Agent' = 'IT4YOU-PowerShell-MSI'; 'Accept' = 'application/vnd.github+json' }
        $releases = @(Invoke-RestMethod -Uri 'https://api.github.com/repos/PowerShell/PowerShell/releases?per_page=100' -Headers $headers -TimeoutSec 30)
        foreach ($release in $releases) {
            if ($release.draft -or $release.prerelease -or [string]$release.tag_name -notmatch '^v(\d+\.\d+\.\d+)$') { continue }
            $ver = [version]$Matches[1]
            if ($ver -le $candidate.Version) { continue }
            $name = "PowerShell-$ver-win-x64.msi"
            $asset = @($release.assets | Where-Object { $_.name -ceq $name } | Select-Object -First 1)
            if ($asset.Count -eq 0) { continue }
            $url = [string]$asset[0].browser_download_url
            if ($url -ne "https://github.com/PowerShell/PowerShell/releases/download/$($release.tag_name)/$name") { continue }
            $digest = [string]$asset[0].digest
            if ($digest -notmatch '^sha256:([a-fA-F0-9]{64})$') { continue }
            $candidate = [pscustomobject]@{ Version=$ver; Url=$url; Sha256=$Matches[1].ToUpperInvariant() }
        }
    } catch {
        Say 'Consulta dinamica indisponivel; usando release MSI conhecido do GitHub.'
    }

    Say "Instalada: $installed | MSI disponivel: $($candidate.Version)"
    if ($installed -ge $candidate.Version) {
        Say 'Nenhuma atualizacao MSI necessaria.'
        $exitCode = 0
    } else {
        $msi = Join-Path $env:TEMP ('IT4YOU-PowerShell-' + [guid]::NewGuid().ToString('N') + '.msi')
        Say "Baixando MSI $($candidate.Version)..."
        Invoke-WebRequest -Uri $candidate.Url -OutFile $msi -UseBasicParsing -TimeoutSec 600
        $hash = (Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash
        if ($hash -ine $candidate.Sha256) { throw 'SHA-256 do MSI nao confere com o GitHub.' }
        $signature = Get-AuthenticodeSignature -LiteralPath $msi
        if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate -or
            $signature.SignerCertificate.Subject -notmatch 'Microsoft') {
            throw 'Assinatura Microsoft do MSI nao validada.'
        }
        Say 'Instalando MSI silenciosamente...'
        $p = Start-Process -FilePath "$env:WINDIR\System32\msiexec.exe" -ArgumentList "/i `"$msi`" /qn /norestart" -Wait -PassThru
        if ($p.ExitCode -notin @(0,3010)) { throw "Instalador retornou $($p.ExitCode)" }
        $afterInfo = (Get-Item -LiteralPath $pwsh -ErrorAction Stop).VersionInfo.ProductVersion
        if ($afterInfo -notmatch '(\d+\.\d+\.\d+)' -or [version]$Matches[1] -lt $candidate.Version) {
            throw "MSI finalizou, mas a versao instalada nao foi confirmada: $afterInfo"
        }
        Say "PowerShell atualizado para $($candidate.Version)."
        $exitCode = 0
    }
} catch {
    if (-not $Silent) { Write-Warning ("ERRO: " + $_.Exception.Message) }
    $exitCode = 1
} finally {
    if ($msi -and (Test-Path -LiteralPath $msi)) { Remove-Item -LiteralPath $msi -Force -ErrorAction SilentlyContinue }
}
exit $exitCode
