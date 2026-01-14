function Update-WindowsOS {
    [CmdletBinding()]
    param()

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
    }
    catch {
        Write-Log ("Falha ao iniciar processo de Windows Update: {0}" -f $_.Exception.Message) 'ERROR'
        return
    }

    if ($proc.ExitCode -ne 0) {
        Write-Log 'Windows Update retornou erro.' 'ERROR'
        return
    }

    Write-Log 'Atualização do Windows concluída.' 'INFO'
}
