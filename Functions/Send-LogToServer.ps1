function Send-LogToServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Server
    )

    $ErrorActionPreference = 'Stop'

    # ===== CREDENCIAIS (AES) =====
    $keyPath  = "C:\Guardian\chave.key"
    $credPath = "C:\Guardian\credenciais.xml"
    $usuario  = "SERVIDOR\Administrador"

    if (-not (Test-Path $keyPath) -or -not (Test-Path $credPath)) {
        Write-Host "Credenciais AES não encontradas." -ForegroundColor Red
        return
    }

    $key = Get-Content $keyPath
    $securePassword = Get-Content $credPath | ConvertTo-SecureString -Key $key
    $credential = New-Object System.Management.Automation.PSCredential ($usuario, $securePassword)

    # ===== LOG LOCAL =====
    $agora = Get-Date
    $ano   = $agora.Year
    $mes   = $agora.Month
    $mesNome = (Get-Culture).DateTimeFormat.MonthNames[$mes - 1]
    $mesNomeFormatado = (Get-Culture).TextInfo.ToTitleCase($mesNome)
    $mesFormatado = "{0:D2}. {1}" -f $mes, $mesNomeFormatado
    $diretorioLogLocal = "C:\Guardian\Logs\$ano\$mesFormatado"

    $arquivo = Get-ChildItem `
        -Path $diretorioLogLocal `
        -Filter *.log `
        -File `
        -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $arquivo) {
        Write-Host "Nenhum log encontrado." -ForegroundColor Yellow
        return
    }

    # ===== DESTINO =====
    $drive   = "G"
    $share   = "\\$Server\TI"
    $destino = "$drive`:\$ano\$mesFormatado"
    $final   = "$($env:COMPUTERNAME).log"

    Write-Host "Centralizando log no servidor..." -ForegroundColor Cyan

    try {
        if (Get-PSDrive $drive -ErrorAction SilentlyContinue) {
            Remove-PSDrive $drive -Force
        }

        New-PSDrive `
            -Name $drive `
            -PSProvider FileSystem `
            -Root $share `
            -Credential $credential `
            -ErrorAction Stop | Out-Null

        if (-not (Test-Path $destino)) {
            New-Item -ItemType Directory -Path $destino -Force | Out-Null
        }

        Copy-Item `
            -Path $arquivo.FullName `
            -Destination "$destino\$final" `
            -Force `
            -ErrorAction Stop

        Write-Host "Log enviado com sucesso." -ForegroundColor Green

    } catch {
        Write-Host "ERRO AO ENVIAR LOG: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        if (Get-PSDrive $drive -ErrorAction SilentlyContinue) {
            Remove-PSDrive $drive -Force
        }
    }
}
