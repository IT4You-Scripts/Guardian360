# Desfragmenta todos os discos físicos disponíveis 
function Optimize-HDD {
    Write-Host "Iniciando verificação do tipo de disco para desfragmentação..."
    Write-Host ""

    try {
        # Obter todos os discos físicos
        $discos = Get-PhysicalDisk

        foreach ($disco in $discos) {
            Write-Host "Verificando disco com DeviceID $($disco.DeviceID)..."
            Write-Host ""

            # Verificar o tipo de mídia do disco
            switch ($disco.MediaType) {
                "SSD" {
                    Write-Host "O disco com DeviceID $($disco.DeviceID) é um SSD. A desfragmentação não é necessária."
                    Write-Host ""
                    Write-Log "O disco com DeviceID $($disco.DeviceID) é um SSD. A desfragmentação não é necessária."
                    Write-Log ""
                }
                "HDD" {
                    Write-Host "O disco com DeviceID $($disco.DeviceID) é um HDD. Iniciando desfragmentação das unidades associadas..."
                    Write-Host ""
                    Write-Log "O disco com DeviceID $($disco.DeviceID) é um HDD. Iniciando desfragmentação das unidades associadas..."
                    Write-Log ""

                    # Obter todas as unidades lógicas associadas ao disco físico
                    $particoes = Get-Partition -DiskNumber $disco.DeviceID

                    foreach ($particao in $particoes) {
                        $driveLetter = $particao.DriveLetter
                        if ($driveLetter) {
                            Write-Host "Desfragmentando unidade $driveLetter..."
                            Write-Host ""
                            Write-Log "Desfragmentando unidade $driveLetter..."
                            Write-Log ""
                            Optimize-Volume -DriveLetter $driveLetter -Defrag -ErrorAction Stop
                            Write-Host "Desfragmentação da unidade $driveLetter concluída com Sucesso!"
                            Write-Host ""
                            Write-Log "Desfragmentação da unidade $driveLetter concluída com Sucesso!"
                            Write-Log ""
                        } else {
                            Write-Host "A partição não possui uma letra de unidade atribuída."
                            Write-Host ""
                        }
                    }
                }
                default {
                    Write-Host "Não foi possível determinar o tipo de disco ou o disco não é nem SSD nem HDD."
                    Write-Host ""
                    Write-Log "Não foi possível determinar o tipo de disco ou o disco não é nem SSD nem HDD."
                    Write-Log ""
                }
            }
        }
    }
    catch {
        Write-Host "ERRO: Falha durante a desfragmentação do disco: $_"
        Write-Host ""
        Write-Log "ERRO: Falha durante a desfragmentação do disco: $_"
        Write-Log ""
    }
}
