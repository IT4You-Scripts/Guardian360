# Otimiza todos os SSDs disponíveis
function Optimize-SSD {
    Write-Host "Iniciando otimização de unidades SSD (ReTrim)..." -ForegroundColor Cyan
    Write-Log "Iniciando Optimize-SSD."

    $fallbackSuccessDrives = @()
    $failedDrives = @()
    $usePrimary = $true
    $volumes = @()

    # 1) Enumeração primária (Get-Volume) com fallback para WMI se necessário
    try {
        $volumes = Get-Volume -ErrorAction Stop | Where-Object { $_.DriveLetter -and ($_.FileSystem -match '^(NTFS|ReFS)$') }
        if (-not $volumes -or $volumes.Count -eq 0) { throw "Nenhum volume elegível" }
    } catch {
        Write-Log "Primeiro método de enumeração falhou (Get-Volume). Utilizando método alternativo por WMI." -ForegroundColor White -BackgroundColor DarkBlue
        $usePrimary = $false
        $volumes = Get-CimInstance -Class Win32_LogicalDisk -Filter "DriveType = 3" -ErrorAction SilentlyContinue
        if (-not $volumes -or $volumes.Count -eq 0) {
            Write-Host "SSD não reconhecido e, portanto, não foi possível a sua otimização." -ForegroundColor White -BackgroundColor DarkBlue
            Write-Log "Nenhuma unidade encontrada para otimização após falha do método principal e fallback WMI."
            Write-Host "Otimização de SSDs finalizada." -ForegroundColor Green
            Write-Log "Otimização de SSDs finalizada."
            return
        }
    }

    # 2) Processamento por unidade
    foreach ($vol in $volumes) {
        $success = $false
        $driveArg = if ($usePrimary) { "$($vol.DriveLetter):" } else { $vol.DeviceID }  # Evita 'C::'

        Write-Host ("Otimizando unidade {0}" -f $driveArg) -ForegroundColor White

        # 2.1) Método principal (Optimize-Volume)
        if ($usePrimary) {
            try {
                Optimize-Volume -DriveLetter $vol.DriveLetter -ReTrim -ErrorAction Stop | Out-Null
                Write-Host "-> Sucesso." -ForegroundColor Green
                $success = $true
            } catch {
                Write-Host "SSD não reconhecido e, portanto, não foi possível a sua otimização." -ForegroundColor White
                Write-Log ("SSD não reconhecido pelo primeiro método (Optimize-Volume) na unidade {0}. Tentando método mais resiliente (Defrag)." -f $driveArg)
            }
        }

        # 2.2) Fallback (Defrag.exe) se necessário
        if (-not $success) {
            try {
                $proc = Start-Process -FilePath "defrag.exe" -ArgumentList @($driveArg, "/O", "/L") -WindowStyle Hidden -Wait -PassThru
                if ($proc.ExitCode -eq 0) {
                    Write-Host "-> Sucesso." -ForegroundColor Green
                    Write-Log ("Fallback concluído com sucesso para {0}." -f $driveArg)
                    $fallbackSuccessDrives += $driveArg
                } else {
                    Write-Host "SSD não reconhecido e, portanto, não foi possível a sua otimização." -ForegroundColor White
                    Write-Log ("Fallback falhou para {0} (ExitCode={1})." -f $driveArg, $proc.ExitCode)
                    $failedDrives += $driveArg
                }
            } catch {
                Write-Host "SSD não reconhecido e, portanto, não foi possível a sua otimização." -ForegroundColor White
                Write-Log ("Erro ao executar fallback para {0}: {1}" -f $driveArg, $_)
                $failedDrives += $driveArg
            }
        }

        Write-Host ""
    }

    # 3) Resumos finais (mensagens curtas e amigáveis)
    if ($fallbackSuccessDrives.Count -gt 0) {
        $msg = "Aviso: SSD não reconhecido pelo primeiro método em $($fallbackSuccessDrives -join ', '); método resiliente aplicado com sucesso."
        Write-Host $msg -ForegroundColor White
        Write-Log $msg
    }
    if ($failedDrives.Count -gt 0) {
        $msg = "Atenção: unidades não otimizadas: $($failedDrives -join ', ')"
        Write-Host $msg -ForegroundColor White
        Write-Log $msg
    }

    Write-Host "Otimização de SSDs finalizada." -ForegroundColor Green
    Write-Log "Otimização de SSDs finalizada."
}
