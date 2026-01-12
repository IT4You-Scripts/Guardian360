# Limpa o Cache do Windows Update 
function Clear-WindowsUpdateCache {
    Write-Host "Iniciando reset completo do Windows Update..." -ForegroundColor Cyan
    Write-Host ""
    Write-Log "Reset do Windows Update (SoftwareDistribution e Catroot2)."
    Write-Log ""

    $services = @("wuauserv", "cryptSvc", "bits", "msiserver")
    
    # 1. Parar todos os serviços primeiro
    foreach ($service in $services) {
        Write-Host "Parando serviço: $service" -ForegroundColor Yellow
        Write-Host ""
        Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
        # Aguarda o serviço parar de fato
        $timeout = 30
        while ((Get-Service $service).Status -ne 'Stopped' -and $timeout -gt 0) {
            Start-Sleep -Seconds 1
            $timeout--
        }
    }

    # 2. Limpar as pastas (Agora fora do loop de serviços)
    $folders = @(
        "$env:systemroot\SoftwareDistribution",
        "$env:systemroot\System32\catroot2"
    )

    foreach ($folder in $folders) {
        if (Test-Path $folder) {
            Write-Host "Limpando cache em: $folder" -ForegroundColor White
            Write-Host ""
            try {
                # Assume a propriedade da pasta (S-1-5-32-544 = Administradores)
                $acl = Get-Acl $folder
                $acl.SetOwner([System.Security.Principal.SecurityIdentifier]::new("S-1-5-32-544"))
                Set-Acl $folder $acl -ErrorAction SilentlyContinue
                
                Remove-Item "$folder\*" -Recurse -Force -ErrorAction SilentlyContinue
            } catch {
                Write-Log "Aviso: Não foi possível limpar totalmente $folder."
                Write-Log ""
            }
        }
    }

    # 3. Reiniciar todos os serviços
    foreach ($service in $services) {
        Write-Host "Reiniciando serviço: $service" -ForegroundColor Green
        Write-Host ""
        Start-Service -Name $service -ErrorAction SilentlyContinue
    }

    Write-Host "Windows Update resetado com Sucesso!" -ForegroundColor Green
    Write-Host ""
    Write-Log "Cache do Windows Update e Catroot2 limpos."
    Write-Log ""
}
