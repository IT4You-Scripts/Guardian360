function Update-WindowsOS {
    [CmdletBinding()]
    param()

    Write-Host "Iniciando atualização do Windows (Windows Update)..." -ForegroundColor Cyan
    Write-Log 'Iniciando atualização do Windows (Windows Update)...' 'INFO'

    $wuScript = @'
try {
    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        Install-Module PSWindowsUpdate -Force -Confirm:$false | Out-Null
    }

    Import-Module PSWindowsUpdate | Out-Null

    Get-WindowsUpdate `
        -Install `
        -AcceptAll `
        -IgnoreReboot `
        -MicrosoftUpdate `
        -ErrorAction Stop `
        -Verbose:$false `
        -Debug:$false `
    | Out-Null

    exit 0
}
catch {
    exit 1
}
'@

    try {

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

        if ($proc.ExitCode -ne 0) {
            Write-Host ("Windows Update retornou erro. ExitCode={0}" -f $proc.ExitCode) -ForegroundColor Red
            Write-Log ("Windows Update retornou erro. ExitCode={0}" -f $proc.ExitCode) 'ERROR'

            throw "Windows Update retornou erro. ExitCode=$($proc.ExitCode)"
        }

        Write-Host "Atualização do Windows concluída." -ForegroundColor Green
        Write-Log 'Atualização do Windows concluída.' 'INFO'

        return [PSCustomObject]@{
            MensagemTecnica = "Atualização do Windows concluída. ExitCode=$($proc.ExitCode)"
            ExitCode        = $proc.ExitCode
        }
    }
    catch {

        Write-Host "ERRO durante Update-WindowsOS: $_" -ForegroundColor Red
        Write-Log ("Falha durante Update-WindowsOS: {0}" -f $_) 'ERROR'

        throw
    }
}
