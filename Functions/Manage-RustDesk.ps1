# =============================================================================
# Manage-RustDesk.ps1
# Guardian 360 - Integracao com RustDesk
# =============================================================================
# Chamado de dentro do Optimize-JsonReport.ps1
#
# Funcionamento:
#
#   A) RustDesk NAO instalado
#      - baixa
#      - instala
#
#   B) RustDesk JA instalado
#      - utiliza a instalacao existente
#
# Em AMBOS os casos:
#      - verifica/corrige servidor, relay e key
#      - valida a configuracao
#      - gera NOVA senha permanente
#      - tenta aplicar a senha ate 3 vezes
#      - somente retorna a senha se o comando for bem-sucedido
#      - captura ID
#
# A senha permanente e rotacionada em TODA execucao do Guardian.
#
# Retorno:
#   rustdesk_id
#   rustdesk_pw
#   rustdesk_status
#   rustdesk_version
# =============================================================================

function Manage-RustDesk {
    [CmdletBinding()]
    param()

    # =========================================================================
    # CONFIGURACOES
    # =========================================================================
    $RustDeskServer = "rustdesk.it4you.com.br"
    $RustDeskKey    = "t5GEz58onhVjOdwom7336p+EWy8iXtIcuXrzo3YTwyU="
    # =========================================================================

    $RustDeskDir     = "C:\Program Files\RustDesk"
    $RustDeskExe     = Join-Path $RustDeskDir "rustdesk.exe"
    $RustDeskService = "RustDesk"

    $ConfigDir = "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config"

    $ConfigFile  = Join-Path $ConfigDir "RustDesk.toml"
    $Config2File = Join-Path $ConfigDir "RustDesk2.toml"

    $PasswordLength  = 16
    $DownloadTimeout = 120

    $GitHubApiUrl = "https://api.github.com/repos/rustdesk/rustdesk/releases/latest"


    # =========================================================================
    # FUNCAO AUXILIAR
    # Verifica se RustDesk2.toml possui servidor e key corretos
    # =========================================================================
    function Test-RustDeskConfig {
        param([string]$FilePath)

        if (-not (Test-Path $FilePath)) {
            return $false
        }

        $conteudo = Get-Content `
            $FilePath `
            -Raw `
            -ErrorAction SilentlyContinue

        if (-not $conteudo) {
            return $false
        }


        # Key
        if ($conteudo -match "key\s*=\s*'([^']*)'") {
            $keyNoArquivo = $Matches[1]
        }
        else {
            return $false
        }


        # Custom Rendezvous Server
        if ($conteudo -match "custom-rendezvous-server\s*=\s*'([^']*)'") {
            $serverNoArquivo = $Matches[1]
        }
        else {
            return $false
        }


        # Comparacao exata
        if ($keyNoArquivo -ne $RustDeskKey) {
            return $false
        }

        if ($serverNoArquivo -ne $RustDeskServer) {
            return $false
        }


        return $true
    }


    # =========================================================================
    # RESULTADO PADRAO
    # =========================================================================
    $result = @{
        rustdesk_id      = $null
        rustdesk_pw      = $null
        rustdesk_status  = "Nao instalado"
        rustdesk_version = $null
    }


    try {

        # =====================================================================
        # ETAPA 1
        # Verificar se RustDesk ja esta instalado
        # =====================================================================
        $jaExistia = Test-Path $RustDeskExe


        if (-not $jaExistia) {

            Write-Host `
                "[RustDesk] Nao encontrado. Iniciando instalacao..." `
                -ForegroundColor Yellow


            # =================================================================
            # ETAPA 2A
            # Baixar ultima versao estavel do GitHub
            # =================================================================
            try {

                [Net.ServicePointManager]::SecurityProtocol = `
                    [Net.SecurityProtocolType]::Tls12


                $releaseInfo = Invoke-RestMethod `
                    -Uri $GitHubApiUrl `
                    -TimeoutSec 30 `
                    -ErrorAction Stop


                $asset = $releaseInfo.assets |
                    Where-Object {
                        $_.name -match "rustdesk-.*-x86_64\.exe$" -and
                        $_.name -notmatch "portable"
                    } |
                    Select-Object -First 1


                if (-not $asset) {

                    Write-Host `
                        "[RustDesk] ERRO: Instalador nao encontrado no GitHub" `
                        -ForegroundColor Red

                    $result.rustdesk_status = `
                        "Erro: Instalador nao encontrado no GitHub"

                    return $result
                }


                $downloadUrl   = $asset.browser_download_url
                $installerPath = "C:\Windows\Temp\rustdesk_installer.exe"


                Write-Host `
                    "[RustDesk] Baixando: $($asset.name) ..." `
                    -ForegroundColor Cyan


                Invoke-WebRequest `
                    -Uri $downloadUrl `
                    -OutFile $installerPath `
                    -TimeoutSec $DownloadTimeout `
                    -ErrorAction Stop


                if (-not (Test-Path $installerPath)) {

                    $result.rustdesk_status = `
                        "Erro: Download falhou"

                    return $result
                }


                Write-Host `
                    "[RustDesk] Download concluido." `
                    -ForegroundColor Green
            }
            catch {

                Write-Host `
                    "[RustDesk] ERRO no download: $($_.Exception.Message)" `
                    -ForegroundColor Red

                $result.rustdesk_status = `
                    "Erro: Download falhou - $($_.Exception.Message)"

                return $result
            }


            # =================================================================
            # ETAPA 2B
            # Instalar silenciosamente
            #
            # ESTE BLOCO PERMANECE COM O COMPORTAMENTO ORIGINAL
            # =================================================================
            try {

                Write-Host `
                    "[RustDesk] Instalando silenciosamente..." `
                    -ForegroundColor Cyan


                Start-Process `
                    -FilePath $installerPath `
                    -ArgumentList "--silent-install"


                # -------------------------------------------------------------
                # Aguardar instalacao concluir verificando executavel
                # -------------------------------------------------------------
                $tentativas    = 0
                $maxTentativas = 12


                while (
                    -not (Test-Path $RustDeskExe) -and
                    $tentativas -lt $maxTentativas
                ) {

                    Start-Sleep -Seconds 10

                    $tentativas++

                    Write-Host `
                        "[RustDesk] Aguardando instalacao... ($tentativas/$maxTentativas)" `
                        -ForegroundColor Cyan
                }


                if (-not (Test-Path $RustDeskExe)) {

                    Write-Host `
                        "[RustDesk] ERRO: Instalacao nao concluiu." `
                        -ForegroundColor Red

                    $result.rustdesk_status = `
                        "Erro: Instalacao nao concluiu"

                    return $result
                }


                # -------------------------------------------------------------
                # Aguardar servico ficar disponivel
                # COMPORTAMENTO ORIGINAL
                # -------------------------------------------------------------
                $tentativas = 0


                while (
                    -not (
                        Get-Service `
                            $RustDeskService `
                            -ErrorAction SilentlyContinue
                    ) -and
                    $tentativas -lt 6
                ) {

                    Start-Sleep -Seconds 5
                    $tentativas++
                }


                Write-Host `
                    "[RustDesk] Instalacao concluida." `
                    -ForegroundColor Green


                Remove-Item `
                    $installerPath `
                    -Force `
                    -ErrorAction SilentlyContinue
            }
            catch {

                Write-Host `
                    "[RustDesk] ERRO na instalacao: $($_.Exception.Message)" `
                    -ForegroundColor Red

                $result.rustdesk_status = `
                    "Erro: Instalacao falhou - $($_.Exception.Message)"

                return $result
            }


            if (-not (Test-Path $RustDeskExe)) {

                $result.rustdesk_status = `
                    "Erro: Instalacao incompleta"

                return $result
            }
        }
        else {

            # =================================================================
            # CAMINHO B
            # RustDesk ja estava instalado
            # =================================================================
            Write-Host `
                "[RustDesk] Ja instalado. Verificando configuracao..." `
                -ForegroundColor Green
        }


        # =====================================================================
        # ETAPA 3
        # SEMPRE verificar e garantir configuracao personalizada
        #
        # Esta e a versao resiliente que:
        #   - verifica
        #   - grava
        #   - rele
        #   - valida
        #   - tenta novamente ate 3 vezes
        # =====================================================================
        try {

            $usersDir = "C:\Users"


            $config2Content = @"
rendezvous_server = '$RustDeskServer'
nat_type = 1
serial = 0

[options]
custom-rendezvous-server = '$RustDeskServer'
relay-server = '$RustDeskServer'
key = '$RustDeskKey'
"@


            # -----------------------------------------------------------------
            # Verificar TODOS os locais
            # -----------------------------------------------------------------
            function Test-AllRustDeskConfigs {

                # Config do servico
                if (-not (Test-RustDeskConfig -FilePath $Config2File)) {
                    return $false
                }


                # Config dos perfis
                foreach (
                    $userDir in (
                        Get-ChildItem `
                            -Path $usersDir `
                            -Directory `
                            -ErrorAction SilentlyContinue
                    )
                ) {

                    $roamingDir = Join-Path `
                        $userDir.FullName `
                        "AppData\Roaming"


                    if (Test-Path $roamingDir) {

                        $userConfig2Path = Join-Path `
                            $userDir.FullName `
                            "AppData\Roaming\RustDesk\config\RustDesk2.toml"


                        if (
                            -not (
                                Test-RustDeskConfig `
                                    -FilePath $userConfig2Path
                            )
                        ) {

                            return $false
                        }
                    }
                }


                return $true
            }


            # -----------------------------------------------------------------
            # Verificacao inicial
            # -----------------------------------------------------------------
            $precisaConfigurar = `
                -not (Test-AllRustDeskConfigs)


            if ($precisaConfigurar) {

                Write-Host `
                    "[RustDesk] Configuracao ausente ou incorreta. Corrigindo..." `
                    -ForegroundColor Yellow


                $configuracaoConfirmada = $false
                $maxTentativasConfig    = 3


                for (
                    $tentativaConfig = 1;
                    $tentativaConfig -le $maxTentativasConfig;
                    $tentativaConfig++
                ) {

                    Write-Host `
                        "[RustDesk] Configurando servidor - tentativa $tentativaConfig/$maxTentativasConfig..." `
                        -ForegroundColor Cyan


                    # ---------------------------------------------------------
                    # Parar servico
                    # ---------------------------------------------------------
                    Stop-Service `
                        -Name $RustDeskService `
                        -Force `
                        -ErrorAction SilentlyContinue


                    Start-Sleep -Seconds 3


                    # ---------------------------------------------------------
                    # Config do servico LocalService
                    # ---------------------------------------------------------
                    if (-not (Test-Path $ConfigDir)) {

                        New-Item `
                            -ItemType Directory `
                            -Path $ConfigDir `
                            -Force |
                            Out-Null
                    }


                    Set-Content `
                        -Path $Config2File `
                        -Value $config2Content `
                        -Force `
                        -Encoding UTF8


                    # ---------------------------------------------------------
                    # Config de TODOS os perfis
                    # ---------------------------------------------------------
                    Get-ChildItem `
                        -Path $usersDir `
                        -Directory `
                        -ErrorAction SilentlyContinue |
                        ForEach-Object {

                            $roamingDir = Join-Path `
                                $_.FullName `
                                "AppData\Roaming"


                            if (Test-Path $roamingDir) {

                                $userConfigDir = Join-Path `
                                    $_.FullName `
                                    "AppData\Roaming\RustDesk\config"


                                if (-not (Test-Path $userConfigDir)) {

                                    New-Item `
                                        -ItemType Directory `
                                        -Path $userConfigDir `
                                        -Force |
                                        Out-Null
                                }


                                $userConfig2 = Join-Path `
                                    $userConfigDir `
                                    "RustDesk2.toml"


                                Set-Content `
                                    -Path $userConfig2 `
                                    -Value $config2Content `
                                    -Force `
                                    -Encoding UTF8
                            }
                        }


                    # ---------------------------------------------------------
                    # Iniciar novamente
                    # ---------------------------------------------------------
                    Start-Service `
                        -Name $RustDeskService `
                        -ErrorAction SilentlyContinue


                    Start-Sleep -Seconds 5


                    # ---------------------------------------------------------
                    # VALIDACAO REAL APOS GRAVACAO
                    # ---------------------------------------------------------
                    if (Test-AllRustDeskConfigs) {

                        $configuracaoConfirmada = $true


                        Write-Host `
                            "[RustDesk] Servidor e key configurados e validados." `
                            -ForegroundColor Green


                        break
                    }


                    Write-Host `
                        "[RustDesk] Configuracao nao permaneceu correta. Tentando novamente..." `
                        -ForegroundColor Yellow


                    Start-Sleep -Seconds 3
                }


                if (-not $configuracaoConfirmada) {

                    Write-Host `
                        "[RustDesk] AVISO: Nao foi possivel confirmar a personalizacao apos 3 tentativas." `
                        -ForegroundColor Yellow
                }
            }
            else {

                Write-Host `
                    "[RustDesk] Servidor e key corretos em todos os locais." `
                    -ForegroundColor Green
            }
        }
        catch {

            Write-Host `
                "[RustDesk] ERRO na verificacao/configuracao: $($_.Exception.Message)" `
                -ForegroundColor Red
        }


        # =====================================================================
        # ETAPA 4
        # Garantir servico rodando
        # =====================================================================
        $service = Get-Service `
            -Name $RustDeskService `
            -ErrorAction SilentlyContinue


        if (
            $service -and
            $service.Status -ne "Running"
        ) {

            Start-Service `
                -Name $RustDeskService `
                -ErrorAction SilentlyContinue


            Start-Sleep -Seconds 5
        }


        # =====================================================================
        # ETAPA 5
        # ROTACIONAR SENHA PERMANENTE
        #
        # IMPORTANTE:
        #
        # Esta etapa agora roda SEMPRE.
        #
        # Nao importa se:
        #   - RustDesk acabou de ser instalado
        #   - RustDesk ja estava instalado
        #   - ja possuia senha
        #   - nunca possuiu senha
        #
        # Uma nova senha e gerada e aplicada.
        #
        # Somente colocamos a senha em rustdesk_pw quando o comando
        # --password retornar ExitCode 0.
        #
        # =====================================================================
        try {

            $chars = `
                'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#%&*'


            $password = -join (
                1..$PasswordLength |
                ForEach-Object {
                    $chars[
                        Get-Random `
                            -Maximum $chars.Length
                    ]
                }
            )


            Write-Host `
                "[RustDesk] Atualizando senha permanente..." `
                -ForegroundColor Cyan


            $senhaConfigurada   = $false
            $maxTentativasSenha = 3


            for (
                $tentativaSenha = 1;
                $tentativaSenha -le $maxTentativasSenha;
                $tentativaSenha++
            ) {

                Write-Host `
                    "[RustDesk] Aplicando senha - tentativa $tentativaSenha/$maxTentativasSenha..." `
                    -ForegroundColor Cyan


                # -------------------------------------------------------------
                # Garantir servico iniciado
                # -------------------------------------------------------------
                Start-Service `
                    -Name $RustDeskService `
                    -ErrorAction SilentlyContinue


                # Na primeira tentativa damos o mesmo tempo que
                # o codigo original ja utilizava.
                Start-Sleep -Seconds 5


                try {

                    # ---------------------------------------------------------
                    # Executar o MESMO comando utilizado pelo codigo original.
                    #
                    # A diferenca e que agora verificamos $LASTEXITCODE.
                    # ---------------------------------------------------------
                    $passwordOutput = `
                        & $RustDeskExe --password $password 2>&1 |
                        Out-String


                    $passwordExitCode = $LASTEXITCODE


                    if ($passwordExitCode -eq 0) {

                        $senhaConfigurada = $true

                        Write-Host `
                            "[RustDesk] Senha permanente atualizada." `
                            -ForegroundColor Green


                        break
                    }


                    Write-Host `
                        "[RustDesk] Senha nao confirmada. Codigo: $passwordExitCode" `
                        -ForegroundColor Yellow
                }
                catch {

                    Write-Host `
                        "[RustDesk] Falha ao aplicar senha: $($_.Exception.Message)" `
                        -ForegroundColor Yellow
                }


                # -------------------------------------------------------------
                # Nao reiniciamos nem paramos o servico aqui.
                #
                # Apenas aguardamos antes de tentar novamente para preservar
                # o comportamento que ja funcionava no script original.
                # -------------------------------------------------------------
                if ($tentativaSenha -lt $maxTentativasSenha) {

                    Start-Sleep -Seconds 5
                }
            }


            # -----------------------------------------------------------------
            # SOMENTE AGORA A SENHA E LIBERADA PARA O RESULTADO / API
            # -----------------------------------------------------------------
            if ($senhaConfigurada) {

                $result.rustdesk_pw = $password
            }
            else {

                # Mantemos NULL.
                #
                # Portanto uma senha que nao foi aceita pelo comando
                # nao sera apresentada como senha valida para a API.
                $result.rustdesk_pw = $null


                Write-Host `
                    "[RustDesk] AVISO: Nao foi possivel confirmar a senha permanente apos 3 tentativas." `
                    -ForegroundColor Yellow
            }
        }
        catch {

            $result.rustdesk_pw = $null


            Write-Host `
                "[RustDesk] ERRO ao atualizar senha permanente: $($_.Exception.Message)" `
                -ForegroundColor Red
        }


        # =====================================================================
        # ETAPA 6
        # Capturar RustDesk ID
        # 3 metodos com fallback
        # =====================================================================

        # ---------------------------------------------------------------------
        # Metodo 1
        # CLI --get-id
        # ---------------------------------------------------------------------
        try {

            $idOutput = `
                & $RustDeskExe --get-id 2>&1 |
                Out-String


            $idOutput = $idOutput.Trim()


            if ($idOutput -match '^\d{7,12}$') {

                $result.rustdesk_id = $idOutput


                Write-Host `
                    "[RustDesk] ID obtido via CLI: $idOutput" `
                    -ForegroundColor Green
            }
        }
        catch {

            Write-Host `
                "[RustDesk] --get-id falhou: $($_.Exception.Message)" `
                -ForegroundColor Yellow
        }


        # ---------------------------------------------------------------------
        # Metodo 2
        # TOML do servico
        # ---------------------------------------------------------------------
        if (-not $result.rustdesk_id) {

            try {

                if (Test-Path $ConfigFile) {

                    $tomlContent = Get-Content `
                        $ConfigFile `
                        -Raw `
                        -ErrorAction Stop


                    if (
                        $tomlContent -match
                        "enc_id\s*=\s*'([^']+)'"
                    ) {

                        # enc_id esta criptografado, nao serve
                    }


                    if (
                        $tomlContent -match
                        "(?m)^id\s*=\s*'(\d{7,12})'"
                    ) {

                        $result.rustdesk_id = $Matches[1]


                        Write-Host `
                            "[RustDesk] ID obtido via TOML servico: $($result.rustdesk_id)" `
                            -ForegroundColor Green
                    }
                }
            }
            catch {

                Write-Host `
                    "[RustDesk] Leitura TOML servico falhou." `
                    -ForegroundColor Yellow
            }
        }


        # ---------------------------------------------------------------------
        # Metodo 3
        # TOML do usuario
        # ---------------------------------------------------------------------
        if (-not $result.rustdesk_id) {

            try {

                $userConfig = `
                    "$env:APPDATA\RustDesk\config\RustDesk.toml"


                if (Test-Path $userConfig) {

                    $tomlContent = Get-Content `
                        $userConfig `
                        -Raw `
                        -ErrorAction Stop


                    if (
                        $tomlContent -match
                        "(?m)^id\s*=\s*'(\d{7,12})'"
                    ) {

                        $result.rustdesk_id = $Matches[1]


                        Write-Host `
                            "[RustDesk] ID obtido via TOML usuario: $($result.rustdesk_id)" `
                            -ForegroundColor Green
                    }
                }
            }
            catch {

                Write-Host `
                    "[RustDesk] Config usuario nao encontrado." `
                    -ForegroundColor Yellow
            }
        }


        # =====================================================================
        # ETAPA 7
        # Capturar versao
        # =====================================================================
        try {

            $versionInfo = `
                (Get-Item $RustDeskExe -ErrorAction Stop).VersionInfo


            $result.rustdesk_version = `
                $versionInfo.ProductVersion


            if (-not $result.rustdesk_version) {

                $result.rustdesk_version = `
                    $versionInfo.FileVersion
            }
        }
        catch {

            $result.rustdesk_version = `
                "Desconhecida"
        }


        # =====================================================================
        # ETAPA 8
        # Status final
        # =====================================================================
        if ($result.rustdesk_id) {

            $result.rustdesk_status = `
                "Instalado"
        }
        elseif (Test-Path $RustDeskExe) {

            $result.rustdesk_status = `
                "Instalado - ID pendente"
        }
        else {

            $result.rustdesk_status = `
                "Nao instalado"
        }


        Write-Host `
            "[RustDesk] Status: $($result.rustdesk_status)" `
            -ForegroundColor Cyan


        Write-Host `
            "[RustDesk] ID: $($result.rustdesk_id ?? 'N/A')" `
            -ForegroundColor Cyan


        Write-Host `
            "[RustDesk] Versao: $($result.rustdesk_version ?? 'N/A')" `
            -ForegroundColor Cyan
    }
    catch {

        Write-Host `
            "[RustDesk] ERRO GERAL: $($_.Exception.Message)" `
            -ForegroundColor Red


        $result.rustdesk_status = `
            "Erro: $($_.Exception.Message)"
    }


    return $result
}