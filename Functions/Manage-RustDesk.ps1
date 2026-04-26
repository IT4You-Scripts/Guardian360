# =============================================================================
# Manage-RustDesk.ps1
# Guardian 360 - Integracao com RustDesk
# =============================================================================
# Chamado de dentro do Optimize-JsonReport.ps1
#
# Dois caminhos:
#   A) RustDesk NAO instalado → baixa, instala, configura, gera senha, captura ID
#   B) RustDesk JA instalado  → apenas captura ID (senha fica por conta do tecnico)
#
# Retorno: Hashtable com rustdesk_id, rustdesk_pw, rustdesk_status, rustdesk_version
# =============================================================================

function Manage-RustDesk {
    [CmdletBinding()]
    param()

    # =========================================================================
    # CONFIGURACOES — ALTERE AQUI
    # =========================================================================
    $RustDeskServer = "rustdesk.it4you.com.br"
    $RustDeskKey    = "t5GEz58onhVjOdwom7336p+EWy8iXtIcuXrzo3YTwyU="
    # =========================================================================

    $RustDeskDir     = "C:\Program Files\RustDesk"
    $RustDeskExe     = Join-Path $RustDeskDir "rustdesk.exe"
    $RustDeskService = "RustDesk"
    $ConfigDir       = "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config"
    $ConfigFile      = Join-Path $ConfigDir "RustDesk.toml"
    $PasswordLength  = 16
    $DownloadTimeout = 120
    $GitHubApiUrl    = "https://api.github.com/repos/rustdesk/rustdesk/releases/latest"

    # Resultado padrao
    $result = @{
        rustdesk_id      = $null
        rustdesk_pw      = $null
        rustdesk_status  = "Nao instalado"
        rustdesk_version = $null
    }

    try {
        # =================================================================
        # ETAPA 1 — Verificar se o RustDesk ja esta instalado
        # =================================================================
        $jaExistia = Test-Path $RustDeskExe

        if (-not $jaExistia) {
            Write-Host "[RustDesk] Nao encontrado. Iniciando instalacao..." -ForegroundColor Yellow

            # -------------------------------------------------------------
            # ETAPA 2A — Baixar ultima versao estavel do GitHub
            # -------------------------------------------------------------
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

                $releaseInfo = Invoke-RestMethod -Uri $GitHubApiUrl -TimeoutSec 30 -ErrorAction Stop

                $asset = $releaseInfo.assets | Where-Object {
                    $_.name -match "rustdesk-.*-x86_64\.exe$" -and
                    $_.name -notmatch "portable"
                } | Select-Object -First 1

                if (-not $asset) {
                    Write-Host "[RustDesk] ERRO: Instalador nao encontrado no GitHub" -ForegroundColor Red
                    $result.rustdesk_status = "Erro: Instalador nao encontrado no GitHub"
                    return $result
                }

                $downloadUrl   = $asset.browser_download_url
                $installerPath = Join-Path $env:TEMP "rustdesk_installer.exe"

                Write-Host "[RustDesk] Baixando: $($asset.name) ..." -ForegroundColor Cyan
                Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -TimeoutSec $DownloadTimeout -ErrorAction Stop

                if (-not (Test-Path $installerPath)) {
                    $result.rustdesk_status = "Erro: Download falhou"
                    return $result
                }

                Write-Host "[RustDesk] Download concluido." -ForegroundColor Green
            }
            catch {
                Write-Host "[RustDesk] ERRO no download: $($_.Exception.Message)" -ForegroundColor Red
                $result.rustdesk_status = "Erro: Download falhou - $($_.Exception.Message)"
                return $result
            }

            # -------------------------------------------------------------
            # ETAPA 2B — Instalar silenciosamente
            # -------------------------------------------------------------
            try {
                Write-Host "[RustDesk] Instalando silenciosamente..." -ForegroundColor Cyan
                Start-Process -FilePath $installerPath -ArgumentList "--silent-install"

                # Aguardar a instalacao concluir verificando o executavel
                $tentativas = 0
                $maxTentativas = 12
                while (-not (Test-Path $RustDeskExe) -and $tentativas -lt $maxTentativas) {
                    Start-Sleep -Seconds 10
                    $tentativas++
                    Write-Host "[RustDesk] Aguardando instalacao... ($tentativas/$maxTentativas)" -ForegroundColor Cyan
                }

                if (-not (Test-Path $RustDeskExe)) {
                    Write-Host "[RustDesk] ERRO: Instalacao nao concluiu." -ForegroundColor Red
                    $result.rustdesk_status = "Erro: Instalacao nao concluiu"
                    return $result
                }

                # Aguardar servico ficar disponivel
                $tentativas = 0
                while (-not (Get-Service $RustDeskService -ErrorAction SilentlyContinue) -and $tentativas -lt 6) {
                    Start-Sleep -Seconds 5
                    $tentativas++
                }

                Write-Host "[RustDesk] Instalacao concluida." -ForegroundColor Green
                Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
            }
            catch {
                Write-Host "[RustDesk] ERRO na instalacao: $($_.Exception.Message)" -ForegroundColor Red
                $result.rustdesk_status = "Erro: Instalacao falhou - $($_.Exception.Message)"
                return $result
            }

            if (-not (Test-Path $RustDeskExe)) {
                $result.rustdesk_status = "Erro: Instalacao incompleta"
                return $result
            }

            Write-Host "[RustDesk] Instalacao concluida." -ForegroundColor Green

            # -------------------------------------------------------------
            # ETAPA 2C — Configurar servidor
            # -------------------------------------------------------------
            try {
                Write-Host "[RustDesk] Configurando servidor: $RustDeskServer ..." -ForegroundColor Cyan

                Stop-Service -Name $RustDeskService -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 3

                if (-not (Test-Path $ConfigDir)) {
                    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
                }

                $configContent = @"
rendezvous_server = '$RustDeskServer'
nat_type = 1
serial = 0

[options]
custom-rendezvous-server = '$RustDeskServer'
relay-server = '$RustDeskServer'
key = '$RustDeskKey'
"@
                Set-Content -Path $ConfigFile -Value $configContent -Force -Encoding UTF8

                Write-Host "[RustDesk] Servidor configurado." -ForegroundColor Green
            }
            catch {
                Write-Host "[RustDesk] ERRO na configuracao: $($_.Exception.Message)" -ForegroundColor Red
            }

            # -------------------------------------------------------------
            # ETAPA 2D — Gerar e definir senha (so quando Guardian instala)
            # -------------------------------------------------------------
            try {
                $chars    = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#%&*'
                $password = -join (1..$PasswordLength | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })

                Write-Host "[RustDesk] Definindo senha permanente..." -ForegroundColor Cyan

                Start-Service -Name $RustDeskService -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 5

                & $RustDeskExe --password $password 2>&1 | Out-Null

                Start-Sleep -Seconds 3

                $result.rustdesk_pw = $password
                Write-Host "[RustDesk] Senha definida." -ForegroundColor Green
            }
            catch {
                Write-Host "[RustDesk] ERRO ao definir senha: $($_.Exception.Message)" -ForegroundColor Red
            }

            # Garantir servico rodando
            Start-Service -Name $RustDeskService -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 5
        }
        else {
            # =============================================================
            # CAMINHO B — RustDesk ja estava instalado
            # =============================================================
            Write-Host "[RustDesk] Ja instalado (instalacao externa). Apenas capturando ID..." -ForegroundColor Green

            # Nao gera senha, nao configura servidor
            # A senha fica por conta do tecnico (NocoDB)
        }

        # =================================================================
        # ETAPA 3 — Garantir servico rodando
        # =================================================================
        $service = Get-Service -Name $RustDeskService -ErrorAction SilentlyContinue
        if ($service -and $service.Status -ne "Running") {
            Start-Service -Name $RustDeskService -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 5
        }

        # =================================================================
        # ETAPA 4 — Capturar RustDesk ID (3 metodos com fallback)
        # =================================================================

        # Metodo 1: via CLI --get-id
        try {
            $idOutput = & $RustDeskExe --get-id 2>&1 | Out-String
            $idOutput = $idOutput.Trim()

            if ($idOutput -match '^\d{7,12}$') {
                $result.rustdesk_id = $idOutput
                Write-Host "[RustDesk] ID obtido via CLI: $idOutput" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "[RustDesk] --get-id falhou: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # Metodo 2 (fallback): ler do TOML do servico
        if (-not $result.rustdesk_id) {
            try {
                if (Test-Path $ConfigFile) {
                    $tomlContent = Get-Content $ConfigFile -Raw -ErrorAction Stop
                    if ($tomlContent -match "enc_id\s*=\s*'([^']+)'") {
                        # enc_id esta criptografado, nao serve
                    }
                    if ($tomlContent -match "(?m)^id\s*=\s*'(\d{7,12})'") {
                        $result.rustdesk_id = $Matches[1]
                        Write-Host "[RustDesk] ID obtido via TOML servico: $($result.rustdesk_id)" -ForegroundColor Green
                    }
                }
            }
            catch {
                Write-Host "[RustDesk] Leitura TOML servico falhou." -ForegroundColor Yellow
            }
        }

        # Metodo 3 (fallback): ler do TOML do usuario
        if (-not $result.rustdesk_id) {
            try {
                $userConfig = "$env:APPDATA\RustDesk\config\RustDesk.toml"
                if (Test-Path $userConfig) {
                    $tomlContent = Get-Content $userConfig -Raw -ErrorAction Stop
                    if ($tomlContent -match "(?m)^id\s*=\s*'(\d{7,12})'") {
                        $result.rustdesk_id = $Matches[1]
                        Write-Host "[RustDesk] ID obtido via TOML usuario: $($result.rustdesk_id)" -ForegroundColor Green
                    }
                }
            }
            catch {
                Write-Host "[RustDesk] Config usuario nao encontrado." -ForegroundColor Yellow
            }
        }

        # =================================================================
        # ETAPA 5 — Capturar versao
        # =================================================================
        try {
            $versionInfo = (Get-Item $RustDeskExe -ErrorAction Stop).VersionInfo
            $result.rustdesk_version = $versionInfo.ProductVersion
            if (-not $result.rustdesk_version) {
                $result.rustdesk_version = $versionInfo.FileVersion
            }
        }
        catch {
            $result.rustdesk_version = "Desconhecida"
        }

        # =================================================================
        # ETAPA 6 — Definir status final
        # =================================================================
        if ($result.rustdesk_id) {
            $result.rustdesk_status = "Instalado"
        }
        elseif (Test-Path $RustDeskExe) {
            $result.rustdesk_status = "Instalado - ID pendente"
        }
        else {
            $result.rustdesk_status = "Nao instalado"
        }

        Write-Host "[RustDesk] Status: $($result.rustdesk_status)" -ForegroundColor Cyan
        Write-Host "[RustDesk] ID: $($result.rustdesk_id ?? 'N/A')" -ForegroundColor Cyan
        Write-Host "[RustDesk] Versao: $($result.rustdesk_version ?? 'N/A')" -ForegroundColor Cyan
    }
    catch {
        Write-Host "[RustDesk] ERRO GERAL: $($_.Exception.Message)" -ForegroundColor Red
        $result.rustdesk_status = "Erro: $($_.Exception.Message)"
    }

    return $result
}