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
# Em AMBOS os caminhos: verifica e garante que o servidor esta configurado
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
    $Config2File     = Join-Path $ConfigDir "RustDesk2.toml"
    $PasswordLength  = 16
    $DownloadTimeout = 120
    $GitHubApiUrl    = "https://api.github.com/repos/rustdesk/rustdesk/releases/latest"

    # =========================================================================
    # Funcao auxiliar: verifica se um RustDesk2.toml tem servidor e key corretos
    # Retorna $true se esta OK, $false se precisa corrigir
    # =========================================================================
    function Test-RustDeskConfig {
        param([string]$FilePath)

        if (-not (Test-Path $FilePath)) { return $false }

        $conteudo = Get-Content $FilePath -Raw -ErrorAction SilentlyContinue
        if (-not $conteudo) { return $false }

        # Extrair o valor do campo key do arquivo
        if ($conteudo -match "key\s*=\s*'([^']*)'") {
            $keyNoArquivo = $Matches[1]
        } else {
            return $false
        }

        # Extrair o valor do campo custom-rendezvous-server
        if ($conteudo -match "custom-rendezvous-server\s*=\s*'([^']*)'") {
            $serverNoArquivo = $Matches[1]
        } else {
            return $false
        }

        # Comparacao EXATA (nao substring)
        if ($keyNoArquivo -ne $RustDeskKey) { return $false }
        if ($serverNoArquivo -ne $RustDeskServer) { return $false }

        return $true
    }

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
                $installerPath = "C:\Windows\Temp\rustdesk_installer.exe"

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
        }
        else {
            # =============================================================
            # CAMINHO B — RustDesk ja estava instalado
            # =============================================================
            Write-Host "[RustDesk] Ja instalado. Verificando configuracao..." -ForegroundColor Green
        }

        # =================================================================
        # ETAPA 3 — SEMPRE: Verificar e garantir configuracao do servidor
        # =================================================================
        # Roda em TODA execucao, independente de ser instalacao nova ou existente.
        # Verifica CADA arquivo individualmente (servico + cada perfil de usuario).
        # Se qualquer um estiver errado, corrige TODOS.
        # =================================================================
        try {
            $precisaConfigurar = $false

            # Verificar config do servico
            if (-not (Test-RustDeskConfig -FilePath $Config2File)) {
                $precisaConfigurar = $true
                Write-Host "[RustDesk] Config do servico ausente ou incorreta." -ForegroundColor Yellow
            }

            # Verificar config de cada perfil de usuario
            $usersDir = "C:\Users"
            Get-ChildItem -Path $usersDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                if (Test-Path (Join-Path $_.FullName "AppData\Roaming")) {
                    $userConfig2Path = Join-Path $_.FullName "AppData\Roaming\RustDesk\config\RustDesk2.toml"
                    if (-not (Test-RustDeskConfig -FilePath $userConfig2Path)) {
                        $precisaConfigurar = $true
                        Write-Host "[RustDesk] Config incorreta no perfil: $($_.Name)" -ForegroundColor Yellow
                    }
                }
            }

            if ($precisaConfigurar) {
                Write-Host "[RustDesk] Corrigindo configuracao do servidor..." -ForegroundColor Cyan

                Stop-Service -Name $RustDeskService -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 3

                $config2Content = @"
rendezvous_server = '$RustDeskServer'
nat_type = 1
serial = 0

[options]
custom-rendezvous-server = '$RustDeskServer'
relay-server = '$RustDeskServer'
key = '$RustDeskKey'
"@

                # Local 1: Config do servico (LocalService)
                if (-not (Test-Path $ConfigDir)) {
                    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
                }
                Set-Content -Path $Config2File -Value $config2Content -Force -Encoding UTF8

                # Local 2: Config de TODOS os perfis de usuario
                Get-ChildItem -Path $usersDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                    $userConfigDir = Join-Path $_.FullName "AppData\Roaming\RustDesk\config"
                    if (Test-Path (Join-Path $_.FullName "AppData\Roaming")) {
                        if (-not (Test-Path $userConfigDir)) {
                            New-Item -ItemType Directory -Path $userConfigDir -Force | Out-Null
                        }
                        $userConfig2 = Join-Path $userConfigDir "RustDesk2.toml"
                        Set-Content -Path $userConfig2 -Value $config2Content -Force -Encoding UTF8
                    }
                }

                Start-Service -Name $RustDeskService -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 5

                Write-Host "[RustDesk] Servidor corrigido (servico + todos os perfis)." -ForegroundColor Green
            }
            else {
                Write-Host "[RustDesk] Servidor e key corretos em todos os locais." -ForegroundColor Green
            }
        }
        catch {
            Write-Host "[RustDesk] ERRO na verificacao/configuracao: $($_.Exception.Message)" -ForegroundColor Red
        }

        # =================================================================
        # ETAPA 4 — Garantir servico rodando
        # =================================================================
        $service = Get-Service -Name $RustDeskService -ErrorAction SilentlyContinue
        if ($service -and $service.Status -ne "Running") {
            Start-Service -Name $RustDeskService -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 5
        }

        # =================================================================
        # ETAPA 5 — Capturar RustDesk ID (3 metodos com fallback)
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
        # ETAPA 6 — Capturar versao
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
        # ETAPA 7 — Definir status final
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
