# =============================================================================
# Manage-RustDesk.ps1
# Guardian 360 - Integracao com RustDesk
# =============================================================================
#
# Chamado de dentro do Optimize-JsonReport.ps1
#
# Dois caminhos:
#   A) RustDesk NAO instalado
#      - baixa
#      - instala
#      - aguarda servico
#      - configura servidor/relay/key
#      - valida configuracao
#      - gera e define senha
#      - captura ID
#
#   B) RustDesk JA instalado
#      - garante servidor/relay/key
#      - captura ID
#      - NAO altera senha existente
#
# Retorno:
#   rustdesk_id
#   rustdesk_pw
#   rustdesk_status
#   rustdesk_version
#
# =============================================================================


function Manage-RustDesk {

    [CmdletBinding()]
    param()


    # =========================================================================
    # CONFIGURACOES
    # =========================================================================

    $RustDeskServer = "rustdesk.it4you.com.br"
    $RustDeskKey    = "t5GEz58onhVjOdwom7336p+EWy8iXtIcuXrzo3YTwyU="

    $RustDeskDir     = "C:\Program Files\RustDesk"
    $RustDeskExe     = Join-Path $RustDeskDir "rustdesk.exe"
    $RustDeskService = "RustDesk"

    $ConfigDir = `
        "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config"

    $ConfigFile  = Join-Path $ConfigDir "RustDesk.toml"
    $Config2File = Join-Path $ConfigDir "RustDesk2.toml"

    $PasswordLength  = 16
    $DownloadTimeout = 120

    $GitHubApiUrl = `
        "https://api.github.com/repos/rustdesk/rustdesk/releases/latest"

    # Quantidade maxima de tentativas para configuracao
    $MaxConfigAttempts = 3

    # Tempo maximo para o servico ficar pronto
    $ServiceTimeoutSeconds = 60

    # Quantidade de tentativas para obter ID
    $MaxIdAttempts = 6


    # =========================================================================
    # FUNCAO AUXILIAR
    # VERIFICAR CONFIGURACAO DO RUSTDESK
    # =========================================================================

    function Test-RustDeskConfig {

        param(
            [string]$FilePath
        )

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


        # ---------------------------------------------------------------------
        # KEY
        # ---------------------------------------------------------------------

        if ($conteudo -match "key\s*=\s*'([^']*)'") {

            $keyNoArquivo = $Matches[1]
        }
        else {

            return $false
        }


        # ---------------------------------------------------------------------
        # CUSTOM RENDEZVOUS SERVER
        # ---------------------------------------------------------------------

        if (
            $conteudo -match
            "custom-rendezvous-server\s*=\s*'([^']*)'"
        ) {

            $serverNoArquivo = $Matches[1]
        }
        else {

            return $false
        }


        # ---------------------------------------------------------------------
        # RELAY SERVER
        # ---------------------------------------------------------------------

        if (
            $conteudo -match
            "relay-server\s*=\s*'([^']*)'"
        ) {

            $relayNoArquivo = $Matches[1]
        }
        else {

            return $false
        }


        # ---------------------------------------------------------------------
        # VALIDACAO EXATA
        # ---------------------------------------------------------------------

        if ($keyNoArquivo -ne $RustDeskKey) {
            return $false
        }

        if ($serverNoArquivo -ne $RustDeskServer) {
            return $false
        }

        if ($relayNoArquivo -ne $RustDeskServer) {
            return $false
        }


        return $true
    }


    # =========================================================================
    # FUNCAO AUXILIAR
    # AGUARDAR SERVICO EXISTIR E FICAR RUNNING
    # =========================================================================

    function Wait-RustDeskService {

        param(
            [int]$TimeoutSeconds = 60
        )

        $elapsed = 0

        while ($elapsed -lt $TimeoutSeconds) {

            $service = Get-Service `
                -Name $RustDeskService `
                -ErrorAction SilentlyContinue

            if ($service) {

                if ($service.Status -ne "Running") {

                    try {

                        Start-Service `
                            -Name $RustDeskService `
                            -ErrorAction SilentlyContinue
                    }
                    catch {
                    }
                }


                # Atualizar estado
                $service = Get-Service `
                    -Name $RustDeskService `
                    -ErrorAction SilentlyContinue


                if (
                    $service -and
                    $service.Status -eq "Running"
                ) {

                    return $true
                }
            }


            Start-Sleep -Seconds 3
            $elapsed += 3
        }


        return $false
    }


    # =========================================================================
    # FUNCAO AUXILIAR
    # ESCREVER CONFIGURACAO
    # =========================================================================

    function Set-RustDeskConfiguration {

        $config2Content = @"
rendezvous_server = '$RustDeskServer'
nat_type = 1
serial = 0

[options]
custom-rendezvous-server = '$RustDeskServer'
relay-server = '$RustDeskServer'
key = '$RustDeskKey'
"@


        # ---------------------------------------------------------------------
        # PARAR SERVICO ANTES DE ALTERAR CONFIG
        # ---------------------------------------------------------------------

        Stop-Service `
            -Name $RustDeskService `
            -Force `
            -ErrorAction SilentlyContinue


        # Esperar realmente parar
        $stopTimeout = 0

        while ($stopTimeout -lt 30) {

            $service = Get-Service `
                -Name $RustDeskService `
                -ErrorAction SilentlyContinue

            if (
                -not $service -or
                $service.Status -eq "Stopped"
            ) {

                break
            }

            Start-Sleep -Seconds 2
            $stopTimeout += 2
        }


        # ---------------------------------------------------------------------
        # CONFIG DO SERVICO
        # ---------------------------------------------------------------------

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


        # ---------------------------------------------------------------------
        # CONFIG DE TODOS OS PERFIS DE USUARIO
        # ---------------------------------------------------------------------

        $usersDir = "C:\Users"

        Get-ChildItem `
            -Path $usersDir `
            -Directory `
            -ErrorAction SilentlyContinue |
            ForEach-Object {

                $roamingPath = Join-Path `
                    $_.FullName `
                    "AppData\Roaming"

                if (Test-Path $roamingPath) {

                    $userConfigDir = Join-Path `
                        $roamingPath `
                        "RustDesk\config"


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


        # ---------------------------------------------------------------------
        # INICIAR SERVICO NOVAMENTE
        # ---------------------------------------------------------------------

        Start-Service `
            -Name $RustDeskService `
            -ErrorAction SilentlyContinue


        return (
            Wait-RustDeskService `
                -TimeoutSeconds $ServiceTimeoutSeconds
        )
    }


    # =========================================================================
    # FUNCAO AUXILIAR
    # VALIDAR TODAS AS CONFIGURACOES
    # =========================================================================

    function Test-AllRustDeskConfigurations {

        # Config do servico
        if (
            -not (
                Test-RustDeskConfig `
                    -FilePath $Config2File
            )
        ) {

            return $false
        }


        # Config dos perfis
        $usersDir = "C:\Users"

        $profilesOk = $true


        Get-ChildItem `
            -Path $usersDir `
            -Directory `
            -ErrorAction SilentlyContinue |
            ForEach-Object {

                $roamingPath = Join-Path `
                    $_.FullName `
                    "AppData\Roaming"

                if (Test-Path $roamingPath) {

                    $userConfig2Path = Join-Path `
                        $roamingPath `
                        "RustDesk\config\RustDesk2.toml"


                    if (
                        -not (
                            Test-RustDeskConfig `
                                -FilePath $userConfig2Path
                        )
                    ) {

                        $profilesOk = $false
                    }
                }
            }


        return $profilesOk
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
        # VERIFICAR SE JA EXISTE
        # =====================================================================

        $jaExistia = Test-Path $RustDeskExe


        if (-not $jaExistia) {

            Write-Host `
                "[RustDesk] Nao encontrado. Iniciando instalacao..." `
                -ForegroundColor Yellow


            # =================================================================
            # ETAPA 2
            # DOWNLOAD
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

                        $_.name -match
                        "rustdesk-.*-x86_64\.exe$" `
                        -and
                        $_.name -notmatch "portable"

                    } |
                    Select-Object -First 1


                if (-not $asset) {

                    Write-Host `
                        "[RustDesk] ERRO: Instalador nao encontrado no GitHub." `
                        -ForegroundColor Red

                    $result.rustdesk_status = `
                        "Erro: Instalador nao encontrado no GitHub"

                    return $result
                }


                $downloadUrl = `
                    $asset.browser_download_url

                $installerPath = `
                    "C:\Windows\Temp\rustdesk_installer.exe"


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
            # ETAPA 3
            # INSTALACAO
            # =================================================================

            try {

                Write-Host `
                    "[RustDesk] Instalando silenciosamente..." `
                    -ForegroundColor Cyan


                $installProcess = Start-Process `
                    -FilePath $installerPath `
                    -ArgumentList "--silent-install" `
                    -PassThru


                # -------------------------------------------------------------
                # AGUARDAR EXECUTAVEL APARECER
                # -------------------------------------------------------------

                $elapsed = 0

                while (
                    -not (Test-Path $RustDeskExe) -and
                    $elapsed -lt 120
                ) {

                    Start-Sleep -Seconds 5
                    $elapsed += 5

                    Write-Host `
                        "[RustDesk] Aguardando instalacao..." `
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
                # AGUARDAR PROCESSO DO INSTALADOR
                # -------------------------------------------------------------

                try {

                    if (
                        $installProcess -and
                        -not $installProcess.HasExited
                    ) {

                        $installProcess.WaitForExit(30000)
                    }
                }
                catch {
                }


                # -------------------------------------------------------------
                # AGUARDAR SERVICO REALMENTE FICAR PRONTO
                # -------------------------------------------------------------

                Write-Host `
                    "[RustDesk] Aguardando servico ficar disponivel..." `
                    -ForegroundColor Cyan


                $serviceReady = Wait-RustDeskService `
                    -TimeoutSeconds $ServiceTimeoutSeconds


                if (-not $serviceReady) {

                    Write-Host `
                        "[RustDesk] ERRO: Servico nao ficou disponivel." `
                        -ForegroundColor Red

                    $result.rustdesk_status = `
                        "Erro: Servico RustDesk nao iniciou"

                    return $result
                }


                # Pequena estabilizacao depois do primeiro start
                Start-Sleep -Seconds 3


                Write-Host `
                    "[RustDesk] Instalacao concluida e servico ativo." `
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
        }
        else {

            # =================================================================
            # RUSTDESK JA EXISTIA
            # =================================================================

            Write-Host `
                "[RustDesk] Ja instalado. Verificando configuracao..." `
                -ForegroundColor Green


            # Garantir que o servico esteja disponivel
            Wait-RustDeskService `
                -TimeoutSeconds $ServiceTimeoutSeconds |
                Out-Null
        }


        # =====================================================================
        # ETAPA 4
        # GARANTIR SERVIDOR / RELAY / KEY
        # =====================================================================

        $configOk = Test-AllRustDeskConfigurations


        if (-not $configOk) {

            Write-Host `
                "[RustDesk] Configuracao ausente ou incorreta." `
                -ForegroundColor Yellow


            $configAttempt = 1

            while (
                -not $configOk -and
                $configAttempt -le $MaxConfigAttempts
            ) {

                Write-Host `
                    "[RustDesk] Configurando servidor - tentativa $configAttempt/$MaxConfigAttempts..." `
                    -ForegroundColor Cyan


                try {

                    $serviceReady = Set-RustDeskConfiguration


                    if (-not $serviceReady) {

                        Write-Host `
                            "[RustDesk] Servico nao estabilizou apos configuracao." `
                            -ForegroundColor Yellow
                    }


                    # Dar tempo para o RustDesk inicializar os arquivos
                    Start-Sleep -Seconds 3


                    # ---------------------------------------------------------
                    # VALIDAR O QUE FOI GRAVADO
                    # ---------------------------------------------------------

                    $configOk = Test-AllRustDeskConfigurations


                    if ($configOk) {

                        Write-Host `
                            "[RustDesk] Servidor, Relay e Key validados." `
                            -ForegroundColor Green

                        break
                    }


                    Write-Host `
                        "[RustDesk] Validacao falhou. Nova tentativa sera realizada." `
                        -ForegroundColor Yellow
                }
                catch {

                    Write-Host `
                        "[RustDesk] Falha na tentativa $configAttempt`: $($_.Exception.Message)" `
                        -ForegroundColor Yellow
                }


                $configAttempt++


                if (-not $configOk) {

                    Start-Sleep -Seconds 5
                }
            }


            # -----------------------------------------------------------------
            # CONFIGURACAO NAO FOI VALIDADA
            # -----------------------------------------------------------------

            if (-not $configOk) {

                Write-Host `
                    "[RustDesk] ERRO: Nao foi possivel validar a configuracao personalizada." `
                    -ForegroundColor Red

                $result.rustdesk_status = `
                    "Erro: Configuracao personalizada nao validada"

                return $result
            }
        }
        else {

            Write-Host `
                "[RustDesk] Servidor, Relay e Key ja estao corretos." `
                -ForegroundColor Green
        }


        # =====================================================================
        # ETAPA 5
        # SENHA
        #
        # SOMENTE SE O GUARDIAN ACABOU DE INSTALAR O RUSTDESK.
        # INSTALACOES EXISTENTES NAO TEM A SENHA ALTERADA.
        # =====================================================================

        if (-not $jaExistia) {

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
                    "[RustDesk] Definindo senha permanente..." `
                    -ForegroundColor Cyan


                # -------------------------------------------------------------
                # GARANTIR SERVICO RUNNING
                # -------------------------------------------------------------

                $serviceReady = Wait-RustDeskService `
                    -TimeoutSeconds $ServiceTimeoutSeconds


                if (-not $serviceReady) {

                    throw `
                        "Servico RustDesk nao esta disponivel para definir a senha."
                }


                # -------------------------------------------------------------
                # TENTAR DEFINIR A SENHA
                # -------------------------------------------------------------

                $passwordDefined = $false


                for (
                    $passwordAttempt = 1;
                    $passwordAttempt -le 3;
                    $passwordAttempt++
                ) {

                    Write-Host `
                        "[RustDesk] Aplicando senha - tentativa $passwordAttempt/3..." `
                        -ForegroundColor Cyan


                    try {

                        $passwordProcess = Start-Process `
                            -FilePath $RustDeskExe `
                            -ArgumentList @(
                                "--password",
                                $password
                            ) `
                            -NoNewWindow `
                            -Wait `
                            -PassThru


                        if ($passwordProcess.ExitCode -eq 0) {

                            $passwordDefined = $true
                            break
                        }


                        Write-Host `
                            "[RustDesk] Comando de senha retornou codigo $($passwordProcess.ExitCode)." `
                            -ForegroundColor Yellow
                    }
                    catch {

                        Write-Host `
                            "[RustDesk] Tentativa de senha falhou: $($_.Exception.Message)" `
                            -ForegroundColor Yellow
                    }


                    # Reiniciar servico antes da proxima tentativa
                    Restart-Service `
                        -Name $RustDeskService `
                        -Force `
                        -ErrorAction SilentlyContinue


                    Wait-RustDeskService `
                        -TimeoutSeconds $ServiceTimeoutSeconds |
                        Out-Null


                    Start-Sleep -Seconds 3
                }


                if (-not $passwordDefined) {

                    Write-Host `
                        "[RustDesk] ERRO: Nao foi possivel definir a senha permanente." `
                        -ForegroundColor Red

                    $result.rustdesk_status = `
                        "Erro: Senha RustDesk nao definida"

                    return $result
                }


                # IMPORTANTE:
                # So colocamos a senha no resultado depois do comando
                # ter retornado sucesso.
                $result.rustdesk_pw = $password


                Write-Host `
                    "[RustDesk] Senha definida com sucesso." `
                    -ForegroundColor Green
            }
            catch {

                Write-Host `
                    "[RustDesk] ERRO ao definir senha: $($_.Exception.Message)" `
                    -ForegroundColor Red

                $result.rustdesk_status = `
                    "Erro: Senha RustDesk nao definida"

                return $result
            }
        }


        # =====================================================================
        # ETAPA 6
        # GARANTIR SERVICO RODANDO
        # =====================================================================

        $serviceReady = Wait-RustDeskService `
            -TimeoutSeconds $ServiceTimeoutSeconds


        if (-not $serviceReady) {

            Write-Host `
                "[RustDesk] AVISO: Servico nao esta Running." `
                -ForegroundColor Yellow
        }


        # =====================================================================
        # ETAPA 7
        # CAPTURAR ID
        #
        # PRIMEIRO: CLI COM RETRY
        # DEPOIS: TOML DO SERVICO
        # DEPOIS: TOML DO USUARIO
        # =====================================================================


        # ---------------------------------------------------------------------
        # METODO 1
        # CLI --get-id COM RETRY
        # ---------------------------------------------------------------------

        for (
            $idAttempt = 1;
            $idAttempt -le $MaxIdAttempts;
            $idAttempt++
        ) {

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

                    break
                }
            }
            catch {

                Write-Host `
                    "[RustDesk] --get-id tentativa $idAttempt falhou." `
                    -ForegroundColor Yellow
            }


            if ($idAttempt -lt $MaxIdAttempts) {

                Write-Host `
                    "[RustDesk] Aguardando ID ficar disponivel... ($idAttempt/$MaxIdAttempts)" `
                    -ForegroundColor Cyan

                Start-Sleep -Seconds 5
            }
        }


        # ---------------------------------------------------------------------
        # METODO 2
        # TOML DO SERVICO
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
        # METODO 3
        # TOML DO USUARIO
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
        # ETAPA 8
        # CAPTURAR VERSAO
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
        # ETAPA 9
        # STATUS FINAL
        # =====================================================================

        if (
            $result.rustdesk_id -and
            $configOk
        ) {

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


        # =====================================================================
        # RESULTADO
        # =====================================================================

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