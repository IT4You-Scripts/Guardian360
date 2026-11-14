# ============================================
# Função: Optimize-SSD
# ============================================
function Optimize-SSD {
    [CmdletBinding()]
    param()

    try {
        Write-Host "Iniciando otimização de unidades SSD (ReTrim)..." -ForegroundColor Cyan
        Write-Log "Iniciando Optimize-SSD."

        $fallbackSuccessDrives = @()
        $failedDrives = @()
        $usePrimary = $true
        $volumes = @()

        # --- 1) Enumeração de volumes ---
        try {
            $volumes = Get-Volume -ErrorAction Stop |
                       Where-Object { $_.DriveLetter -and ($_.FileSystem -match '^(NTFS|ReFS)$') }

            if (-not $volumes -or $volumes.Count -eq 0) {
                throw "Nenhum volume elegível"
            }
        }
        catch {
            Write-Log "Get-Volume falhou; usando fallback WMI."
            $usePrimary = $false

            $volumes = Get-CimInstance -Class Win32_LogicalDisk `
                        -Filter "DriveType = 3" -ErrorAction SilentlyContinue

            if (-not $volumes -or $volumes.Count -eq 0) {
                $msg = "Nenhuma unidade elegível encontrada para otimização."
                Write-Host "Nenhuma unidade SSD encontrada para otimização." -ForegroundColor Yellow
                Write-Log "Nenhuma unidade encontrada após fallback WMI."
                return $msg
            }
        }

        # --- 2) Processamento de cada unidade ---
        foreach ($vol in $volumes) {

            $success = $false
            $driveArg = if ($usePrimary) { "$($vol.DriveLetter):" } else { $vol.DeviceID }

            Write-Host ("Otimizando unidade {0}..." -f $driveArg) -ForegroundColor White

            # Método principal (Optimize-Volume)
            if ($usePrimary) {
                try {
                    Optimize-Volume -DriveLetter $vol.DriveLetter -ReTrim -ErrorAction Stop | Out-Null
                    Write-Host " -> Sucesso." -ForegroundColor Green
                    $success = $true
                }
                catch {
                    Write-Log ("Falha no Optimize-Volume para {0}. Tentando fallback Defrag." -f $driveArg)
                }
            }

            # Fallback (defrag.exe)
            if (-not $success) {
                try {
                    Start-Process defrag.exe `
                        -ArgumentList @($driveArg, "/O", "/L") `
                        -WindowStyle Hidden -Wait | Out-Null

                    Write-Host " -> Fallback aplicado com sucesso." -ForegroundColor Green
                    $fallbackSuccessDrives += $driveArg
                }
                catch {
                    Write-Host " -> Falha ao otimizar." -ForegroundColor Yellow
                    Write-Log ("Erro no fallback para {0}: {1}" -f $driveArg, $_)
                    $failedDrives += $driveArg
                }
            }
        }

        # --- 3) Resumo final ---
        $finalMsg = if ($failedDrives.Count -gt 0) {
            "Otimização concluída com falhas em: $($failedDrives -join ', ')."
        } elseif ($fallbackSuccessDrives.Count -gt 0) {
            "Otimização concluída. Fallback aplicado em: $($fallbackSuccessDrives -join ', ')."
        } else {
            "Otimização concluída com sucesso usando Optimize-Volume."
        }

        Write-Host $finalMsg -ForegroundColor Green
        Write-Log $finalMsg

        return $finalMsg
    }
    catch {
        Write-Host "ERRO crítico durante a otimização de SSDs: $_" -ForegroundColor Red
        Write-Log ("ERRO crítico durante Optimize-SSD: {0}" -f $_)

        $erro = $_ | Format-List * -Force | Out-String
        throw $erro.Trim()
    }
}
