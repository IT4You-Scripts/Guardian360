
<#
.SYNOPSIS
    Verifica e corrige problemas do Winget com teste real e tratamento de erros avançado.
.DESCRIPTION
    Diagnóstico completo, reparo profundo e reinstalação do Winget se necessário.
.NOTES
    Autor: [Seu Nome]
    Data: 16/01/2026
#>

$LogPath = "$env:ProgramData\WingetRepair\WingetRepair.log"
New-Item -ItemType Directory -Force -Path (Split-Path $LogPath) | Out-Null

Function Write-Log {
    param([string]$Message)
    $Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    "$Timestamp - $Message" | Out-File -Append -FilePath $LogPath
}

Write-Log "===== Iniciando verificação do Winget ====="

Function Test-Winget {
    try {
        $wingetVersion = winget --version 2>$null
        if (-not $wingetVersion) {
            Write-Log "Winget não está funcional (versão não encontrada)."
            return $false
        }
        Write-Log "Winget encontrado. Versão: $wingetVersion"
        
        # Teste real: listar pacotes
        try {
            $result = winget list --source winget 2>$null
            if ($result) {
                Write-Log "Teste real OK: Winget list executado com sucesso."
                return $true
            } else {
                Write-Log "Teste real falhou: Winget não conseguiu listar pacotes."
                return $false
            }
        } catch {
            Write-Log "Erro no teste real: $_"
            return $false
        }
    } catch {
        Write-Log "Erro ao executar Winget: $_"
        return $false
    }
}

Function Remove-Winget {
    Write-Log "Removendo Winget e App Installer..."
    try {
        Get-AppxPackage Microsoft.DesktopAppInstaller | Remove-AppxPackage -ErrorAction SilentlyContinue
        Get-AppxPackage Microsoft.VCLibs* | Remove-AppxPackage -ErrorAction SilentlyContinue
        Remove-Item "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller*" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Remoção completa."
    } catch {
        Write-Log "Erro na remoção: $_"
    }
}

Function Install-Winget {
    Write-Log "Baixando e instalando Winget mais recente..."
    $InstallerUrl = "https://aka.ms/getwinget"
    $InstallerPath = "$env:TEMP\AppInstaller.msixbundle"
    $retryCount = 0
    do {
        try {
            Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath -ErrorAction Stop
            Add-AppxPackage -Path $InstallerPath -ErrorAction Stop
            Write-Log "Instalação concluída."
            return
        } catch {
            $retryCount++
            Write-Log "Erro na instalação (tentativa $retryCount): $_"
            Start-Sleep -Seconds 5
        }
    } while ($retryCount -lt 3)
    Write-Log "Falha após 3 tentativas de instalação."
}

# Execução principal
if (Test-Winget) {
    Write-Host "✅ Winget está saudável. Nenhuma correção necessária."
    Write-Log "Winget OK."
} else {
    Write-Host "⚠ Winget com problemas. Iniciando reparo..."
    Remove-Winget
    Install-Winget
    if (Test-Winget) {
        Write-Host "✅ Winget reparado com sucesso!"
        Write-Log "Winget reparado com sucesso."
    } else {
        Write-Host "❌ Falha ao reparar Winget. Verifique o log em $LogPath"
        Write-Log "Falha ao reparar Winget."
    }
}

Write-Log "===== Processo concluído ====="
