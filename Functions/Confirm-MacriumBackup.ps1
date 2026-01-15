
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
        Write-Host -NoNewline ("[{0}] " -f $Tag) -ForegroundColor $Color
        Write-Host $Message

        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log ("[{0}] {1}" -f $Tag, $Message)
        }
        if (Get-Command Write-Report -ErrorAction SilentlyContinue) {
            Write-Report ("[{0}] {1}" -f $Tag, $Message)
        }
    }

    try {
        $drive = Get-PSDrive -Name $DriveLetter -PSProvider FileSystem -ErrorAction SilentlyContinue
        if (-not $drive) {
            Write-Tagged -Tag 'ALERTA' -Message "Não existe a partição $DriveLetter." -Color ([ConsoleColor]::Red)
            return
        }

        $rescuePath = Join-Path -Path $drive.Root -ChildPath $RescueFolderName
        if (-not (Test-Path -Path $rescuePath -PathType Container)) {
            Write-Tagged -Tag 'ALERTA' -Message "A partição $DriveLetter existe, mas não foi encontrada a pasta $RescueFolderName." -Color ([ConsoleColor]::Red)
            return
        }

        # Busca arquivos com as extensões especificadas
        $files = @()
        foreach ($ext in $Extensions) {
            $files += Get-ChildItem -Path $rescuePath -File -Filter "*$ext" -Recurse:$Recurse -ErrorAction SilentlyContinue
        }

        # Força array para evitar erro ao acessar .Count
        $files = @($files)

        # Se não encontrou arquivos com as extensões, tenta pegar qualquer arquivo
        if ($files.Count -eq 0) {
            $files = @(Get-ChildItem -Path $rescuePath -File -Recurse:$Recurse -ErrorAction SilentlyContinue)
        }

        if ($files.Count -eq 0) {
            Write-Tagged -Tag 'ALERTA' -Message "A pasta $rescuePath existe, mas não contém arquivos do Macrium Reflect." -Color ([ConsoleColor]::Red)
            return
        }

        # Ordena arquivos por data
        $sortedFiles = @($files | Sort-Object LastWriteTime)
        $newestFile = $sortedFiles[-1]
        $secondNewestFile = if ($sortedFiles.Count -ge 2) { $sortedFiles[-2] } else { $null }

        $newestDisplay = $newestFile.LastWriteTime.ToString('dd/MM/yyyy HH:mm')
        $secondNewestDisplay = if ($secondNewestFile) { $secondNewestFile.LastWriteTime.ToString('dd/MM/yyyy HH:mm') } else { 'N/A' }

        # Calcula idade do arquivo mais recente
        $newestAgeDays = [Math]::Round(((Get-Date) - $newestFile.LastWriteTime).TotalDays)
        $olderThanThreshold = $newestAgeDays -gt $ThresholdDays

        # Define severidade
        $tag = if ($olderThanThreshold) { 'AVISO' } else { 'INFO' }
        $color = if ($olderThanThreshold) { [ConsoleColor]::DarkYellow } else { [ConsoleColor]::Green }

        # Cabeçalho
        Write-Host "`n`nMacrium Reflect"
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log "Macrium Reflect" }
        if (Get-Command Write-Report -ErrorAction SilentlyContinue) {
            Write-Report ""
            Write-Report "Macrium Reflect"
        }

        # Exibe informações
        if ($sortedFiles.Count -eq 1) {
            Write-Tagged -Tag $tag -Message "Imagem mais recente: $newestDisplay" -Color $color
        } else {
            Write-Tagged -Tag $tag -Message "Imagem anterior: $secondNewestDisplay" -Color $color
            Write-Tagged -Tag $tag -Message "Imagem mais recente: $newestDisplay" -Color $color
        }

        # Idade do arquivo
        $msg = if ($olderThanThreshold) {
            "A imagem mais recente tem $newestAgeDays dias (acima do limite de $ThresholdDays dias)."
        } else {
            "O último arquivo tem aproximadamente $newestAgeDays dias."
        }
        Write-Tagged -Tag $tag -Message $msg -Color $color
    }
    catch {
        Write-Tagged -Tag 'ALERTA' -Message "Erro crítico durante a execução do bloco de manutenção: $($_.Exception.Message)" -Color ([ConsoleColor]::Red)
    }
}
