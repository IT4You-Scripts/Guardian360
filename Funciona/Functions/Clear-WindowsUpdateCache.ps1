# Limpa o Cache do Windows Update
function Clear-WindowsUpdateCache {
    # Checa se está executando como Administrador
    if (-not ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "Execute este script como Administrador para reset completo do Windows Update." -ForegroundColor Yellow
        return
    }

    Write-Host "Iniciando reset do Windows Update..." -ForegroundColor Cyan
    Write-Log "Início do reset do Windows Update (SoftwareDistribution e Catroot2)."

    $services = @("wuauserv", "cryptSvc", "bits", "msiserver")
    $folders  = @("$env:systemroot\SoftwareDistribution", "$env:systemroot\System32\catroot2")

    # --- ETAPA 1: Parar serviços ---
    Write-Host "Parando serviços do Windows Update..." -ForegroundColor Yellow
    foreach ($service in $services) {
        Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
        $timeout = 30
        while ((Get-Service $service).Status -ne 'Stopped' -and $timeout -gt 0) {
            Start-Sleep -Seconds 1
            $timeout--
        }
        if ((Get-Service $service).Status -ne 'Stopped') {
            Write-Log "Aviso: Serviço $service não parou dentro do timeout."
        }
    }
    Write-Host "Serviços parados." -ForegroundColor Green

    # --- ETAPA 2: Limpar pastas ---
    Write-Host "Limpando cache..." -ForegroundColor Yellow
    foreach ($folder in $folders) {
        try {
            # Assume propriedade da pasta para evitar falhas de permissão
            $acl = Get-Acl $folder
            $acl.SetOwner([System.Security.Principal.SecurityIdentifier]::new("S-1-5-32-544"))
            Set-Acl $folder $acl -ErrorAction SilentlyContinue

            Remove-Item "$folder\*" -Recurse -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-Log "Aviso: Não foi possível limpar totalmente $folder."
        }
    }
    Write-Host "Cache limpo." -ForegroundColor Green

    # --- ETAPA 3: Reiniciar serviços ---
    Write-Host "Reiniciando serviços..." -ForegroundColor Yellow
    foreach ($service in $services) {
        Start-Service -Name $service -ErrorAction SilentlyContinue
    }
    Write-Host "Serviços reiniciados." -ForegroundColor Green

    Write-Host "Reset do Windows Update concluído!" -ForegroundColor Cyan
    Write-Log "Cache do Windows Update e Catroot2 limpos com sucesso."
}
