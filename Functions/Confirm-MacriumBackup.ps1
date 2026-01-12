function Confirm-MacriumBackup {
    param(
        [string]$DriveLetter = 'D',
        [string]$RescueFolderName = 'Rescue',
        [int]$ThresholdDays = 60,
        [switch]$Recurse,
        [string[]]$Extensions = @('.mrimg', '.mrbak')
    )

    # Helper: imprime um rótulo colorido seguido do texto padrão
    function Write-Tagged {
        param(
            [Parameter(Mandatory)][ValidateSet('INFO','AVISO','ALERTA')] [string]$Tag,
            [Parameter(Mandatory)][string]$Message,
            [ConsoleColor]$Color = [ConsoleColor]::White
        )
        # Saída no console
        Write-Host -NoNewline ("[{0}] " -f $Tag) -ForegroundColor $Color
        Write-Host $Message

        # Saída no log (se existir)
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log ("[{0}] {1}" -f $Tag, $Message)
        }

        # Saída no relatório (se existir)
        if (Get-Command Write-Report -ErrorAction SilentlyContinue) {
            Write-Report ("[{0}] {1}" -f $Tag, $Message)
        }
    }

    try {
        $drive = Get-PSDrive -Name $DriveLetter -PSProvider FileSystem -ErrorAction SilentlyContinue
        if (-not $drive) {
            $msg = "Não existe a partição $DriveLetter."
            Write-Tagged -Tag 'ALERTA' -Message $msg -Color ([ConsoleColor]::Red)
            return
        }

        $driveRoot = $drive.Root
        $rescuePath = Join-Path -Path $driveRoot -ChildPath $RescueFolderName
        if (-not (Test-Path -Path $rescuePath -PathType Container)) {
            $msg = "Tem a partição $DriveLetter, mas não tem a pasta $RescueFolderName."
            Write-Tagged -Tag 'ALERTA' -Message $msg -Color ([ConsoleColor]::Red)
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
            Write-Tagged -Tag 'ALERTA' -Message $msg -Color ([ConsoleColor]::Red)
            return
        }

        $sortedFiles = $files | Sort-Object LastWriteTime
        $newestFile = $sortedFiles[-1]
        $secondNewestFile = if ($fileCount -ge 2) { $sortedFiles[-2] } else { $null }

        $newestDisplay = $newestFile.LastWriteTime.ToString('dd/MM/yyyy HH:mm')
        $secondNewestDisplay = if ($secondNewestFile) { $secondNewestFile.LastWriteTime.ToString('dd/MM/yyyy HH:mm') } else { $null }

        $newestAgeDays = ((Get-Date) - $newestFile.LastWriteTime).Days
        $olderThanThreshold = $newestAgeDays -gt $ThresholdDays

        # Definição de severidade e cor
        if ($olderThanThreshold) {
            $tag = 'AVISO'
            $color = [ConsoleColor]::DarkYellow  # aproximação de laranja escuro
        }
        else {
            $tag = 'INFO'
            $color = [ConsoleColor]::Green  # verde claro
        }

        # Título + linha em branco
        $titulo = "Macrium Reflect"
        Write-Host ""
        Write-Host ""
        Write-Host $titulo
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log $titulo }
        if (Get-Command Write-Report -ErrorAction SilentlyContinue) {
            Write-Report ""
            Write-Report ""
            Write-Report $titulo
        }

        # Rótulos com largura padronizada para alinhar a coluna da data
        $labelAnterior = "Imagem do Macrium Reflect (penúltima):"
        $labelRecente = "Imagem do Macrium Reflect (mais recente):"
        $labelWidth = [Math]::Max($labelAnterior.Length, $labelRecente.Length) + 1  # +1 para um espaço de separação

        if ($fileCount -eq 1) {
            $msg = ($labelRecente.PadRight($labelWidth)) + $newestDisplay
            Write-Tagged -Tag $tag -Message $msg -Color $color
        }
        else {
            $msg1 = ($labelAnterior.PadRight($labelWidth)) + $secondNewestDisplay
            $msg2 = ($labelRecente.PadRight($labelWidth)) + $newestDisplay
            Write-Tagged -Tag $tag -Message $msg1 -Color $color
            Write-Tagged -Tag $tag -Message $msg2 -Color $color
        }

        # Mensagem de idade - sempre exibida
        $msg = if ($olderThanThreshold) {
            "A imagem mais recente tem $newestAgeDays dias (acima do limite de $ThresholdDays dias)."
        } else {
            "A imagem mais recente tem $newestAgeDays dias."
        }
        Write-Tagged -Tag $tag -Message $msg -Color $color

    }
    catch {
        $errorMessage = "Erro crítico durante a execução do bloco de manutenção: $($_.Exception.Message)"
        Write-Tagged -Tag 'ALERTA' -Message $errorMessage -Color ([ConsoleColor]::Red)
    }
}