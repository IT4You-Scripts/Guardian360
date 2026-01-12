# Verifica a existência dos arquivos de backup do Macrium Reflect
function Validate-MacriumBackup {
    param(
        [string]$DriveLetter = 'D',
        [string]$RescueFolderName = 'Rescue',
        [int]$ThresholdDays = 60,
        [switch]$Recurse,
        [string[]]$Extensions = @('.mrimg', '.mrbak')
    )

    try {
        $drive = Get-PSDrive -Name $DriveLetter -PSProvider FileSystem -ErrorAction SilentlyContinue
        if (-not $drive) {
            $msg = "Não existe a partição $DriveLetter."
            Write-Host $msg
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log "$msg" }
            return
        }

        $driveRoot = $drive.Root
        $rescuePath = Join-Path -Path $driveRoot -ChildPath $RescueFolderName
        if (-not (Test-Path -Path $rescuePath -PathType Container)) {
            $msg = "Tem a partição $DriveLetter, mas não tem a pasta $RescueFolderName."
            Write-Host $msg
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log "$msg" }
            return
        }

        $files = @()
        foreach ($ext in $Extensions) {
            $files += Get-ChildItem -Path $rescuePath -File -Filter "*$ext" -Recurse:$Recurse -ErrorAction SilentlyContinue
        }
        if ($files.Count -eq 0) {
            $files = Get-ChildItem -Path $rescuePath -File -Recurse:$Recurse -ErrorAction SilentlyContinue
        }

        $fileCount = $files.Count
        if ($fileCount -eq 0) {
            $msg = "A pasta $rescuePath existe, mas não contém arquivos."
            Write-Host $msg
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log "$msg" }
            return
        }

        $sortedFiles = $files | Sort-Object LastWriteTime
        $newestFile = $sortedFiles[-1]
        $secondNewestFile = if ($fileCount -ge 2) { $sortedFiles[-2] } else { $null }

        $newestDisplay = $newestFile.LastWriteTime.ToString('dd/MM/yyyy HH:mm')
        $secondNewestDisplay = if ($secondNewestFile) { $secondNewestFile.LastWriteTime.ToString('dd/MM/yyyy HH:mm') } else { $null }

        $newestAgeDays = ((Get-Date) - $newestFile.LastWriteTime).Days
        $olderThanThreshold = $newestAgeDays -gt $ThresholdDays

        # Título + linha em branco
        $titulo = if ($fileCount -le 1) { "IMAGEM DO MACRIUM REFLECT" } else { "IMAGENS DO MACRIUM REFLECT" }
        Write-Host ""
        Write-Host $titulo
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log "$titulo" }

        # Rótulos com largura padronizada para alinhar a coluna da data
        $labelAnterior = "-> IMAGEM ANTERIOR:"
        $labelRecente = "-> IMAGEM MAIS RECENTE:"
        $labelWidth = [Math]::Max($labelAnterior.Length, $labelRecente.Length) + 1  # +1 para um espaço de separação

        if ($fileCount -eq 1) {
            $msg = ($labelRecente.PadRight($labelWidth)) + $newestDisplay
            Write-Host $msg
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log "$msg" }
        } else {
            $msg1 = ($labelAnterior.PadRight($labelWidth)) + $secondNewestDisplay
            $msg2 = ($labelRecente.PadRight($labelWidth)) + $newestDisplay
            Write-Host $msg1
            Write-Host $msg2
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log "$msg1"; Write-Log "$msg2" }
        }

        if ($olderThanThreshold) {
            $msg = "A imagem mais recente tem mais de $ThresholdDays dias."
            Write-Host $msg
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log "$msg" }
        }

    } catch {
        $errorMessage = "Erro crítico durante a execução do bloco de manutenção: $($_.Exception.Message)"
        Write-Host $errorMessage
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log "$errorMessage" }
    }
}
