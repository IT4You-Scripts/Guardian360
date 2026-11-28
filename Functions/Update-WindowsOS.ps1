function Update-WindowsOS {
    [CmdletBinding()]
    param()

    Write-Host "Iniciando atualização do Windows (Windows Update)..." -ForegroundColor Cyan

    # O processo filho grava um pequeno resumo (JSON) no arquivo indicado pela variável de
    # ambiente GUARDIAN_WU_RESULT. O código de saída continua sendo 0 (ok) ou 1 (erro).
    $wuScript = @'
$resultado = [ordered]@{ total = 0; instaladas = 0; falhas = 0; reiniciar = $null; erro = $null }

function Save-WuResult {
    if ($env:GUARDIAN_WU_RESULT) {
        try {
            ($resultado | ConvertTo-Json -Compress) |
                Set-Content -LiteralPath $env:GUARDIAN_WU_RESULT -Encoding UTF8 -ErrorAction Stop
        } catch { }
    }
}

try {
    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        Install-Module PSWindowsUpdate -Force -Confirm:$false | Out-Null
    }

    Import-Module PSWindowsUpdate | Out-Null

    $atualizacoes = @(Get-WindowsUpdate `
        -Install `
        -AcceptAll `
        -IgnoreReboot `
        -MicrosoftUpdate `
        -ErrorAction Stop `
        -Verbose:$false `
        -Debug:$false)

    $resultado.total = $atualizacoes.Count
    $resultado.instaladas = @($atualizacoes | Where-Object { ([string]$_.Result + ' ' + [string]$_.Status) -match 'Install' }).Count
    $resultado.falhas = @($atualizacoes | Where-Object { ([string]$_.Result + ' ' + [string]$_.Status) -match 'Fail' }).Count
    try { $resultado.reiniciar = [bool](Get-WURebootStatus -Silent) } catch { }

    Save-WuResult
    exit 0
}
catch {
    $resultado.erro = [string]$_.Exception.Message
    Save-WuResult
    exit 1
}
'@

    $arquivoResultado = Join-Path $env:TEMP ('guardian-wu-' + [guid]::NewGuid().ToString('N') + '.json')

    try {

        $env:GUARDIAN_WU_RESULT = $arquivoResultado

        $proc = Start-Process pwsh `
            -ArgumentList @(
                '-Version 5.1',
                '-NoProfile',
                '-NonInteractive',
                '-Command', $wuScript
            ) `
            -WindowStyle Hidden `
            -Wait `
            -PassThru

        # Resumo gravado pelo processo filho (se existir e estiver legível)
        $resumoWu = $null
        if (Test-Path -LiteralPath $arquivoResultado) {
            try {
                $resumoWu = Get-Content -LiteralPath $arquivoResultado -Raw -ErrorAction Stop |
                    ConvertFrom-Json -ErrorAction Stop
            } catch { $resumoWu = $null }
        }

        if ($proc.ExitCode -ne 0) {
            Write-Host ("Windows Update retornou erro. ExitCode={0}" -f $proc.ExitCode) -ForegroundColor Red

            $msgErro = "Windows Update retornou erro. ExitCode=$($proc.ExitCode)"
            if ($resumoWu -and $resumoWu.erro) {
                $motivo = ([string]$resumoWu.erro -replace '\s+', ' ').Trim()
                if ($motivo.Length -gt 200) { $motivo = $motivo.Substring(0, 200) + '...' }
                $msgErro += ". Motivo: $motivo"
            }
            throw $msgErro
        }

        Write-Host "Atualização do Windows concluída." -ForegroundColor Green

        # "ExitCode=N" fica no início do texto: o Optimize-JsonReport lê esse valor e a
        # tabela de saída pode truncar o final de mensagens longas.
        $mensagemTecnica = "Atualização do Windows concluída. ExitCode=$($proc.ExitCode)"
        if ($resumoWu) {
            $reinicio = if ($null -eq $resumoWu.reiniciar) { 'não verificado' }
                        elseif ($resumoWu.reiniciar) { 'sim' }
                        else { 'não' }
            $mensagemTecnica += ". Processadas: $($resumoWu.total), instaladas: $($resumoWu.instaladas), falhas: $($resumoWu.falhas), reinício: $reinicio."
        }

        return [PSCustomObject]@{
            MensagemTecnica = $mensagemTecnica
            ExitCode        = $proc.ExitCode
        }
    }
    catch {

        Write-Host "ERRO durante Update-WindowsOS: $_" -ForegroundColor Red

        throw
    }
    finally {
        Remove-Item Env:\GUARDIAN_WU_RESULT -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $arquivoResultado -Force -ErrorAction SilentlyContinue
    }
}
