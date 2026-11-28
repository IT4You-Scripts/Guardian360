# ============================================
# Função: Optimize-SSD
# ============================================
function Optimize-SSD {
    [CmdletBinding()]
    param()

    try {
        Write-Host "Iniciando otimização de unidades SSD (ReTrim)..." -ForegroundColor Cyan

        $fallbackSuccessDrives = @()
        $failedDrives = @()
        $ignoredDrives = @()
        $usePrimary = $true
        $volumes = @()

        # --- 1) Enumeração de volumes ---
        try {
            $volumes = Get-Volume -ErrorAction Stop |
                       Where-Object { $_.DriveLetter -and ($_.FileSystem -match '^(NTFS|ReFS)$') }

            if (-not $volumes -or @($volumes).Count -eq 0) {
                throw "Nenhum volume elegível"
            }
        }
        catch {
            $usePrimary = $false

            $volumes = Get-CimInstance -Class Win32_LogicalDisk `
                        -Filter "DriveType = 3" -ErrorAction SilentlyContinue

            if (-not $volumes -or @($volumes).Count -eq 0) {
                $msg = "Nenhuma unidade elegível encontrada para otimização."
                Write-Host "Nenhuma unidade SSD encontrada para otimização." -ForegroundColor Yellow
                return $msg
            }
        }

        # --- 1.1) Somente SSD: ignora volumes que SEGURAMENTE são HDD ou USB ---
        # (ReTrim não se aplica a HDD, e o fallback defrag.exe /O desfragmentaria o HDD;
        #  discos USB pertencem ao usuário.) Se o tipo do disco não puder ser determinado,
        # o volume é mantido, como era antes.
        $discosFisicos = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
        $elegiveis = @()

        foreach ($vol in @($volumes)) {
            $letra = if ($usePrimary) { [string]$vol.DriveLetter } else { ([string]$vol.DeviceID).TrimEnd(':') }

            $fisico = $null
            try {
                $particao = Get-Partition -DriveLetter $letra -ErrorAction Stop | Select-Object -First 1
                $fisico = $discosFisicos |
                    Where-Object { [string]$_.DeviceId -eq [string]$particao.DiskNumber } |
                    Select-Object -First 1
            } catch {
                $fisico = $null
            }

            if ($fisico -and [string]$fisico.BusType -eq 'USB') {
                Write-Host ("Unidade {0}: disco USB. Ignorando." -f $letra) -ForegroundColor Yellow
                $ignoredDrives += "${letra}: (USB)"
                continue
            }
            if ($fisico -and [string]$fisico.MediaType -eq 'HDD') {
                Write-Host ("Unidade {0}: disco HDD. Ignorando (não é SSD)." -f $letra) -ForegroundColor Yellow
                $ignoredDrives += "${letra}: (HDD)"
                continue
            }

            $elegiveis += $vol
        }

        if ($elegiveis.Count -eq 0) {
            $msg = "Nenhuma unidade SSD elegível para otimização."
            if ($ignoredDrives.Count -gt 0) { $msg += " Ignoradas: $($ignoredDrives -join ', ')." }
            Write-Host $msg -ForegroundColor Yellow
            return $msg
        }

        # --- 2) Processamento de cada unidade ---
        foreach ($vol in $elegiveis) {

            $success = $false
            $motivoPrimario = $null
            $driveArg = if ($usePrimary) { "$($vol.DriveLetter):" } else { $vol.DeviceID }

            Write-Host ("Otimizando unidade {0}..." -f $driveArg) -ForegroundColor White

            # Método principal (Optimize-Volume)
            if ($usePrimary) {
                try {
                    Optimize-Volume -DriveLetter $vol.DriveLetter -ReTrim -ErrorAction Stop -ProgressAction SilentlyContinue | Out-Null
                    Write-Host " -> Sucesso." -ForegroundColor Green
                    $success = $true
                }
                catch {
                    $motivoPrimario = ([string]$_.Exception.Message -replace '\s+', ' ').Trim()
                }
            }

            # Fallback (defrag.exe)
            if (-not $success) {
                try {
                    $processo = Start-Process defrag.exe `
                        -ArgumentList @($driveArg, "/O", "/L") `
                        -WindowStyle Hidden -Wait -PassThru -ErrorAction Stop

                    if ($processo.ExitCode -ne 0) {
                        throw "defrag.exe terminou com código $($processo.ExitCode)"
                    }

                    Write-Host " -> Fallback aplicado com sucesso." -ForegroundColor Green
                    $fallbackSuccessDrives += $driveArg
                }
                catch {
                    $motivoFallback = ([string]$_.Exception.Message -replace '\s+', ' ').Trim()
                    Write-Host " -> Falha ao otimizar." -ForegroundColor Yellow

                    if ($motivoPrimario) {
                        $failedDrives += "$driveArg ($motivoFallback; Optimize-Volume: $motivoPrimario)"
                    } else {
                        $failedDrives += "$driveArg ($motivoFallback)"
                    }
                }
            }
        }

        # --- 3) Resumo final ---
        $finalMsg = if ($failedDrives.Count -gt 0) {
            "Otimização concluída com falhas em: $($failedDrives -join '; ')."
        } elseif ($fallbackSuccessDrives.Count -gt 0) {
            "Otimização concluída. Fallback aplicado em: $($fallbackSuccessDrives -join ', ')."
        } else {
            "Otimização concluída com sucesso usando Optimize-Volume."
        }

        if ($ignoredDrives.Count -gt 0) {
            $finalMsg += " Ignoradas (não são SSD): $($ignoredDrives -join ', ')."
        }

        Write-Host $finalMsg -ForegroundColor Green

        return $finalMsg
    }
    catch {
        Write-Host "ERRO crítico durante a otimização de SSDs: $_" -ForegroundColor Red

        $erro = $_ | Format-List * -Force | Out-String
        throw $erro.Trim()
    }
}
