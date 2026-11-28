# ============================================================================
# AUTOATUALIZACAO DO PROPRIO ATUALIZA.PS1
# A marcacao de relancamento impede qualquer possibilidade de loop:
# a instancia nova pula esta verificacao uma unica vez e segue o Atualiza normal.
# ============================================================================
if ($env:GUARDIAN_ATUALIZA_RELANCADO -ne "1") {
    try {
        $SelfBaseUrl = "https://raw.githubusercontent.com/IT4You-Scripts/Guardian360/main/Atualiza.ps1"
        $SelfPath    = "C:\Guardian\Atualiza.ps1"
        $SelfTemp    = "C:\Guardian\Guardian_Atualiza_$PID.ps1"
        $SelfNoCache = "?nocache=$(Get-Date -Format 'yyyyMMddHHmmssfff')"

        Invoke-WebRequest `
            -Uri "$SelfBaseUrl$SelfNoCache" `
            -OutFile $SelfTemp `
            -UseBasicParsing `
            -Headers @{ "Cache-Control" = "no-cache" } `
            -ErrorAction Stop

        $RemoteHash = (Get-FileHash -LiteralPath $SelfTemp -Algorithm SHA256).Hash
        $LocalHash  = $null

        if (Test-Path -LiteralPath $SelfPath) {
            $LocalHash = (Get-FileHash -LiteralPath $SelfPath -Algorithm SHA256).Hash
        }

        # Download cortado ou invalido nunca substitui o Atualiza atual.
        $SelfValido = ((Get-Item -LiteralPath $SelfTemp).Length -gt 0)
        if ($SelfValido -and $PSVersionTable.PSVersion.Major -ge 7) {
            $SelfTokens = $null
            $SelfErros  = $null
            [void][System.Management.Automation.Language.Parser]::ParseInput(
                [System.IO.File]::ReadAllText($SelfTemp, [System.Text.UTF8Encoding]::new($false)),
                [ref]$SelfTokens, [ref]$SelfErros)
            if (@($SelfErros).Count -gt 0) { $SelfValido = $false }
        }

        if ($SelfValido -and $RemoteHash -ne $LocalHash) {
            if (-not (Test-Path -LiteralPath "C:\Guardian")) {
                New-Item -ItemType Directory -Path "C:\Guardian" -Force | Out-Null
            }

            if (Test-Path -LiteralPath $SelfPath) {
                attrib -R $SelfPath 2>$null
            }

            Copy-Item -LiteralPath $SelfTemp -Destination $SelfPath -Force

            $PwshSelf = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
            if (-not $PwshSelf) {
                $PwshSelf = "powershell.exe"
            }

            # O processo filho herda esta variavel e, portanto, NAO tenta
            # se autoatualizar novamente nesta mesma cadeia de execucao.
            $env:GUARDIAN_ATUALIZA_RELANCADO = "1"

            Start-Process `
                -FilePath $PwshSelf `
                -ArgumentList @(
                    "-NoProfile",
                    "-ExecutionPolicy", "Bypass",
                    "-File", "`"$SelfPath`""
                )

            Remove-Item -LiteralPath $SelfTemp -Force -ErrorAction SilentlyContinue
            exit 0
        }

        Remove-Item -LiteralPath $SelfTemp -Force -ErrorAction SilentlyContinue
    }
    catch {
        if ($SelfTemp -and (Test-Path -LiteralPath $SelfTemp -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $SelfTemp -Force -ErrorAction SilentlyContinue
        }
        # Se a autoatualizacao falhar, preserva o comportamento original.
    }
}
else {
    # Remove a marcacao dentro da nova instancia e continua normalmente.
    Remove-Item Env:\GUARDIAN_ATUALIZA_RELANCADO -ErrorAction SilentlyContinue
}


# ============================================================================
# ATUALIZADOR UNICO
# Este script nao tem mais lista propria de arquivos. Ele apenas garante uma copia
# valida de Functions\Update-GuardianFiles.ps1 (a unica lista oficial) e a executa.
# O nome da funcao abaixo e mantido porque Post-Install, Checkup e GuardianRestore
# conferem a presenca de "function Update-GuardianFiles" neste arquivo.
# ============================================================================
function Update-GuardianFiles {

    $ErrorActionPreference = "Stop"
    $ProgressPreference   = "SilentlyContinue"

    $BaseUrl  = "https://raw.githubusercontent.com/IT4You-Scripts/Guardian360/main"
    $DestDir  = "C:\Guardian\Functions"
    $DestPath = Join-Path $DestDir "Update-GuardianFiles.ps1"
    $Temp     = "$DestPath.download"
    $NoCache  = "?nocache=$(Get-Date -Format 'yyyyMMddHHmmssfff')"

    # 1) Baixa o atualizador para um temporario e valida antes de substituir o atual.
    try {
        if (-not (Test-Path -LiteralPath $DestDir)) {
            New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
        }

        Invoke-WebRequest `
            -Uri "$BaseUrl/Functions/Update-GuardianFiles.ps1$NoCache" `
            -OutFile $Temp `
            -UseBasicParsing `
            -Headers @{ "Cache-Control" = "no-cache" } `
            -ErrorAction Stop

        if ((Get-Item -LiteralPath $Temp -ErrorAction Stop).Length -eq 0) {
            throw "Download vazio"
        }

        $Texto = [System.IO.File]::ReadAllText($Temp, [System.Text.UTF8Encoding]::new($false))
        if ($Texto -notmatch 'function\s+Update-GuardianFiles') {
            throw "Arquivo baixado nao e o atualizador esperado"
        }

        if ($PSVersionTable.PSVersion.Major -ge 7) {
            $Tokens = $null
            $Erros  = $null
            [void][System.Management.Automation.Language.Parser]::ParseInput($Texto, [ref]$Tokens, [ref]$Erros)
            if (@($Erros).Count -gt 0) {
                throw "Atualizador incompleto ou invalido: $($Erros[0].Message)"
            }
        }

        if (Test-Path -LiteralPath $DestPath) {
            attrib -R $DestPath 2>$null
        }
        Move-Item -LiteralPath $Temp -Destination $DestPath -Force -ErrorAction Stop
    }
    catch {
        Remove-Item -LiteralPath $Temp -Force -ErrorAction SilentlyContinue

        if (-not (Test-Path -LiteralPath $DestPath)) {
            Write-Host "Falha critica: atualizador indisponivel ($($_.Exception.Message))." -ForegroundColor Red
            Write-Host "O script sera encerrado em 5 segundos..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
            exit 1
        }

        Write-Host "Aviso: nao foi possivel renovar o atualizador ($($_.Exception.Message)); usando a copia local." -ForegroundColor DarkYellow
    }

    # 2) Executa o atualizador unico em um processo separado: o que ele faz
    #    (lista de arquivos, validacao, falhas) continua exatamente como no uso pelo RodaGuardian.
    $PwshExe = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
    if (-not $PwshExe) {
        $PwshExe = (Get-Process -Id $PID).Path
    }

    & $PwshExe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ". '$DestPath'; Update-GuardianFiles"
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

Update-GuardianFiles
