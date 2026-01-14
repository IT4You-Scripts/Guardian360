# Otimiza todos os SSDs disponíveis
function Optimize-SSD {
    Write-Host "Iniciando otimização de unidades SSD (ReTrim)..." -ForegroundColor Cyan
    Write-Log "Iniciando Optimize-SSD."

    $fallbackSuccessDrives = @()
    $failedDrives = @()
    $usePrimary = $true
    $volumes = @()

    # --- 1) Enumeração de volumes ---
    try {
        $volumes = Get-Volume -ErrorAction Stop | Where-Object { $_.DriveLetter -and ($_.FileSystem -match '^(NTFS|ReFS)$') }
        if (-not $volumes -or $volumes.Count -eq 0) { throw "Nenhum volume elegível" }
    } catch {
        Write-Log "Get-Volume falhou; usando fallback WMI."
        $usePrimary = $false
        $volumes = Get-CimInstance -Class Win32_LogicalDisk -Filter "DriveType = 3" -ErrorAction SilentlyContinue
        if (-not $volumes -or $volumes.Count -eq 0) {
            Write-Host "Nenhuma unidade SSD encontrada para otimização." -ForegroundColor Yellow
            Write-Log "Nenhuma unidade encontrada após fallback WMI."
            Write-Host "Otimização de SSDs finalizada." -ForegroundColor Green
            Write-Log "Otimização de SSDs finalizada."
            return
        }
    }

    # --- 2) Processamento de cada unidade ---
    foreach ($vol in $volumes) {
        $success = $false
        $driveArg = if ($usePrimary) { "$($vol.DriveLetter):" } else { $vol.DeviceID }

        Write-Host ("Otimizando unidade {0}..." -f $driveArg) -ForegroundColor White

        # 2.1) Método principal (Optimize-Volume)
        if ($usePrimary) {
            try {
                Optimize-Volume -DriveLetter $vol.DriveLetter -ReTrim -ErrorAction Stop | Out-Null
                Write-Host "-> Sucesso." -ForegroundColor Green
                $success = $true
            } catch {
                Write-Log ("Falha no Optimize-Volume para {0}. Tentando fallback Defrag." -f $driveArg)
            }
        }

        # 2.2) Fallback (Defrag.exe)
        if (-not $success) {
            try {
                Start-Process -FilePath "defrag.exe" -ArgumentList @($driveArg, "/O", "/L") -WindowStyle Hidden -Wait -PassThru | Out-Null
                Write-Host "-> Fallback aplicado com sucesso." -ForegroundColor Green
                $fallbackSuccessDrives += $driveArg
            } catch {
                Write-Host "-> Falha ao otimizar." -ForegroundColor Yellow
                Write-Log ("Erro no fallback para {0}: {1}" -f $driveArg, $_)
                $failedDrives += $driveArg
            }
        }
    }

    # --- 3) Resumos finais ---
    if ($fallbackSuccessDrives.Count -gt 0) {
        $msg = "Aviso: fallback aplicado com sucesso em $($fallbackSuccessDrives -join ', ')."
        Write-Host $msg -ForegroundColor White
        Write-Log $msg
    }
    if ($failedDrives.Count -gt 0) {
        $msg = "Atenção: unidades não otimizadas: $($failedDrives -join ', ')."
        Write-Host $msg -ForegroundColor White
        Write-Log $msg
    }

    Write-Host "Otimização de SSDs finalizada." -ForegroundColor Green
    Write-Log "Otimização de SSDs finalizada."
}
