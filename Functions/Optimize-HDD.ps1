function Optimize-HDD {
    [CmdletBinding()]
    param()

    try {
        Write-Host "Iniciando verificação de discos para desfragmentação..." -ForegroundColor Cyan

        $mensagens = @()

        # Obter todos os discos físicos
        $discos = Get-PhysicalDisk

        foreach ($disco in $discos) {
            $deviceID = $disco.DeviceID
            $mediaType = $disco.MediaType

            Write-Host ("Disco {0}: Tipo {1}" -f $deviceID, $mediaType) -ForegroundColor White
            $mensagens += "Disco $deviceID Tipo $mediaType"

            # Discos externos USB nao sao desfragmentados (pertencem ao usuario e podem ser lentos).
            if ($disco.BusType -eq 'USB') {
                Write-Host " -> Disco USB detectado. Ignorando." -ForegroundColor Yellow
                $mensagens += "Disco $deviceID USB ignorado"
                continue
            }

            switch ($mediaType) {

                "SSD" {
                    Write-Host " -> SSD detectado. Desfragmentação não necessária." -ForegroundColor Green
                    $mensagens += "Disco $deviceID SSD ignorado"
                }

                "HDD" {
                    Write-Host " -> HDD detectado. Iniciando desfragmentação das unidades..." -ForegroundColor Yellow

                    $particoes = Get-Partition -DiskNumber $deviceID | Where-Object { $_.DriveLetter }

                    foreach ($particao in $particoes) {
                        $driveLetter = $particao.DriveLetter
                        try {
                            Write-Host ("   Desfragmentando unidade {0}..." -f $driveLetter) -ForegroundColor White

                            Optimize-Volume -DriveLetter $driveLetter -Defrag -ErrorAction Stop -ProgressAction SilentlyContinue

                            Write-Host ("   Unidade {0} desfragmentada com sucesso." -f $driveLetter) -ForegroundColor Green

                            $mensagens += "Unidade $driveLetter desfragmentada"
                        }
                        catch {
                            $motivo = ([string]$_.Exception.Message -replace '\s+', ' ').Trim()
                            if ([string]::IsNullOrWhiteSpace($motivo)) { $motivo = 'motivo nao informado' }

                            Write-Host ("   Falha ao desfragmentar unidade {0}: {1}" -f $driveLetter, $motivo) -ForegroundColor Yellow

                            $mensagens += "Falha unidade ${driveLetter}: $motivo"
                        }
                    }

                    if ($particoes.Count -eq 0) {
                        Write-Host "   Nenhuma partição com letra encontrada neste disco." -ForegroundColor Yellow
                        $mensagens += "Disco $deviceID sem partições"
                    }
                }

                default {
                    Write-Host " -> Tipo de disco não reconhecido. Ignorando." -ForegroundColor Yellow
                    $mensagens += "Disco $deviceID tipo desconhecido"
                }
            }
        }

        Write-Host "Otimização de discos concluída." -ForegroundColor Green

        return ($mensagens -join " | ")
    }
    catch {
        Write-Host "ERRO crítico durante a desfragmentação: $_" -ForegroundColor Red

        throw
    }
}
