function Update-WindowsOS {
    [CmdletBinding()]
    param()

    Write-Host "Iniciando atualização do Windows (Windows Update)..." -ForegroundColor Cyan

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

            throw "Windows Update retornou erro. ExitCode=$($proc.ExitCode)"
        }

        Write-Host "Atualização do Windows concluída." -ForegroundColor Green

        return [PSCustomObject]@{
            MensagemTecnica = "Atualização do Windows concluída. ExitCode=$($proc.ExitCode)"
            ExitCode        = $proc.ExitCode
        }
    }
    catch {

        Write-Host "ERRO durante Update-WindowsOS: $_" -ForegroundColor Red

        throw
    }
}
