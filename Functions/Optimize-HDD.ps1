# Desfragmenta todos os discos físicos disponíveis
function Optimize-HDD {
    Write-Host "Iniciando verificação de discos para desfragmentação..." -ForegroundColor Cyan
    Write-Log "Início do Optimize-HDD."

    try {
        # Obter todos os discos físicos
        $discos = Get-PhysicalDisk

        foreach ($disco in $discos) {
            $deviceID = $disco.DeviceID
            $mediaType = $disco.MediaType

            # Mensagem inicial resumida
            Write-Host ("Disco {0}: Tipo {1}" -f $deviceID, $mediaType) -ForegroundColor White

            switch ($mediaType) {
                "SSD" {
                    Write-Host "-> SSD detectado. Desfragmentação não necessária." -ForegroundColor Green
                    Write-Log ("Disco {0} é SSD. Desfragmentação não realizada." -f $deviceID)
                }
                "HDD" {
                    Write-Host "-> HDD detectado. Iniciando desfragmentação das unidades..." -ForegroundColor Yellow
                    Write-Log ("Disco {0} é HDD. Iniciando desfragmentação." -f $deviceID)

                    # Obter todas as partições com letra
                    $particoes = Get-Partition -DiskNumber $deviceID | Where-Object { $_.DriveLetter }

                    foreach ($particao in $particoes) {
                        $driveLetter = $particao.DriveLetter
                        try {
                            Write-Host ("   Desfragmentando unidade {0}..." -f $driveLetter) -ForegroundColor White
                            Write-Log ("Desfragmentando unidade {0} do disco {1}..." -f $driveLetter, $deviceID)

                            Optimize-Volume -DriveLetter $driveLetter -Defrag -ErrorAction Stop

                            Write-Host ("   Unidade {0} desfragmentada com sucesso." -f $driveLetter) -ForegroundColor Green
                            Write-Log ("Unidade {0} do disco {1} desfragmentada com sucesso." -f $driveLetter, $deviceID)
                        } catch {
                            Write-Host ("   Falha ao desfragmentar unidade {0}." -f $driveLetter) -ForegroundColor Yellow
                            Write-Log ("Erro ao desfragmentar unidade {0} do disco {1}: {2}" -f $driveLetter, $deviceID, $_)
                        }
                    }

                    if ($particoes.Count -eq 0) {
                        Write-Host "   Nenhuma partição com letra encontrada neste disco." -ForegroundColor Yellow
                        Write-Log ("Disco {0} não possui partições com letra atribuída." -f $deviceID)
                    }
                }
                default {
                    Write-Host "-> Tipo de disco não reconhecido. Ignorando." -ForegroundColor Yellow
                    Write-Log ("Disco {0} com tipo {1} não reconhecido. Ignorado." -f $deviceID, $mediaType)
                }
            }
        }
    } catch {
        Write-Host "ERRO crítico durante a desfragmentação: $_" -ForegroundColor Red
        Write-Log ("ERRO crítico durante Optimize-HDD: {0}" -f $_)
    }

    Write-Host "Otimização de discos concluída." -ForegroundColor Green
    Write-Log "Optimize-HDD finalizado."
}
