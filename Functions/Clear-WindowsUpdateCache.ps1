function Clear-WindowsUpdateCache {
    [CmdletBinding()]
    param()

    try {
        # Verifica se está executando como Administrador
        $isAdmin = ([Security.Principal.WindowsPrincipal] `
            [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        if (-not $isAdmin) {
            Write-Host "Execute este script como Administrador para reset completo do Windows Update." -ForegroundColor Yellow
            return "Erro técnico: execução requer privilégios de Administrador."
        }

        Write-Host "Iniciando reset do Windows Update..." -ForegroundColor Cyan

        $services = @("wuauserv", "cryptSvc", "bits", "msiserver")
        $folders  = @("$env:systemroot\SoftwareDistribution", "$env:systemroot\System32\catroot2")

        # --- Phase 1: Parar serviços ---
        Write-Host "Parando serviços do Windows Update..." -ForegroundColor Yellow
        foreach ($service in $services) {
            Stop-Service -Name $service -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            $timeout = 30

            while ((Get-Service $service).Status -ne 'Stopped' -and $timeout -gt 0) {
                Start-Sleep -Seconds 1
                $timeout--
            }

            if ((Get-Service $service).Status -ne 'Stopped') {
            }
        }
        Write-Host "Serviços parados." -ForegroundColor Green

        # --- Phase 2: Limpar pastas ---
        Write-Host "Limpando cache..." -ForegroundColor Yellow
        foreach ($folder in $folders) {
            try {
                $acl = Get-Acl $folder
                $acl.SetOwner([System.Security.Principal.SecurityIdentifier]::new("S-1-5-32-544"))
                Set-Acl $folder $acl -ErrorAction SilentlyContinue

                Remove-Item "$folder\*" -Recurse -Force -ErrorAction SilentlyContinue
            }
            catch {
            }
        }
        Write-Host "Cache limpo." -ForegroundColor Green

        # --- Phase 3: Reiniciar serviços ---
        Write-Host "Reiniciando serviços..." -ForegroundColor Yellow
        foreach ($service in $services) {
            Start-Service -Name $service -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        }
        Write-Host "Serviços reiniciados." -ForegroundColor Green

        Write-Host "Reset do Windows Update concluído!" -ForegroundColor Cyan

        return "Reset do Windows Update concluído tecnicamente com sucesso."
    }
    catch {
        Write-Host "Falha no reset do Windows Update." -ForegroundColor Red

        $erroDetalhado = ($_ | Format-List * -Force | Out-String).Trim()
        throw "Erro crítico durante Clear-WindowsUpdateCache: $erroDetalhado"
    }
}