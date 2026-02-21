<#
====================================================================
  CONVERSOR Json
  - Hardware limpo (sem discos e sem partições)
  - Armazenamentos e Partições extraídos corretamente
  - Redes estruturadas (coleta TODOS os adaptadores)
====================================================================
#>

param(
    [string]$Pasta = "."
)

# Write-Host "`n🔍 Procurando arquivo ORIGINAL..." -ForegroundColor Cyan

# ------------------------------------------------------------------------------
# Localizar arquivo ORIGINAL — caminho fixo C:\Guardian\Json
# ------------------------------------------------------------------------------

# Caminho base fixo
$baseJsonDir = "C:\Guardian\Json"

# Ano e mês atual para montar a pasta correta
$year        = Get-Date -Format 'yyyy'
$monthNumber = Get-Date -Format 'MM'
$monthName   = (Get-Culture).DateTimeFormat.GetMonthName([int]$monthNumber)
$monthFolder = ("{0}. {1}" -f $monthNumber, (Get-Culture).TextInfo.ToTitleCase($monthName.ToLower()))

# Caminho final onde o arquivo ORIGINAL sempre será salvo
$jsonDir = Join-Path (Join-Path $baseJsonDir $year) $monthFolder

if (-not (Test-Path $jsonDir)) {
    Write-Host "❌ Pasta de inventários não encontrada: $jsonDir" -ForegroundColor Red
    exit
}

# Write-Host "📁 Procurando arquivo ORIGINAL em: $jsonDir" -ForegroundColor Cyan

# Buscar arquivo ORIGINAL (ignora EXTREME e TRATADO)
$arquivo = Get-ChildItem -Path $jsonDir -Filter *.json |
    Where-Object {
        $_.Name -match "^[A-Za-z0-9\-]+_\d{8}_\d{4}\.json$" -and
        $_.Name -notmatch "EXTREME" -and
        $_.Name -notmatch "TRATADO"
    } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $arquivo) {
    Write-Host "❌ Nenhum arquivo ORIGINAL encontrado em: $jsonDir" -ForegroundColor Red
    exit
}

# Write-Host "✔ Arquivo original identificado: $($arquivo.FullName)" -ForegroundColor Green


# ------------------------------------------------------------------------------
# Carregar JSON
# ------------------------------------------------------------------------------
$jsonRaw = Get-Content $arquivo.FullName -Raw | ConvertFrom-Json

# Blindagem: consolidar fases duplicadas de bloqueio de atualização
$faseBlockApp = @($jsonRaw.Fases) | Where-Object { $_.Phase -match "Block-AppUpdates" } | Select-Object -First 1
$faseQgis     = @($jsonRaw.Fases) | Where-Object { $_.Phase -match "QGIS" } | Select-Object -First 1

if ($faseBlockApp -or $faseQgis) {

    $mensagens = @()
    $tempoTotal = 0

    if ($faseBlockApp) {
        if ($faseBlockApp.Mensagem) { $mensagens += $faseBlockApp.Mensagem }
        $tempoTotal += $faseBlockApp.TempoSeg
    }

    if ($faseQgis) {
        if ($faseQgis.Mensagem) { $mensagens += $faseQgis.Mensagem }
        $tempoTotal += $faseQgis.TempoSeg
    }

    $novaFase = [PSCustomObject]@{
        Phase    = "Regras de Bloqueio no Firewall contra Atualizações"
        Status   = "OK"
        TempoSeg = $tempoTotal
        Mensagem = ($mensagens -join " | ")
    }

    $jsonRaw.Fases = @($jsonRaw.Fases) | Where-Object {
        $_ -ne $faseBlockApp -and $_ -ne $faseQgis
    }

    # Inserir nova fase logo após "Atualização da Loja da Microsoft"
$indexStore = -1

for ($i = 0; $i -lt $jsonRaw.Fases.Count; $i++) {
    if ($jsonRaw.Fases[$i].Phase -match "Loja da Microsoft") {
        $indexStore = $i
        break
    }
}

if ($indexStore -ge 0) {
    $antes  = $jsonRaw.Fases[0..$indexStore]
    $depois = @()

    if ($indexStore + 1 -lt $jsonRaw.Fases.Count) {
        $depois = $jsonRaw.Fases[($indexStore + 1)..($jsonRaw.Fases.Count - 1)]
    }

    $jsonRaw.Fases = @($antes + $novaFase + $depois)
}
else {
    # fallback (caso não encontre)
    $jsonRaw.Fases += $novaFase
}

}

if (-not $jsonRaw.Fases) {
    Write-Host "❌ JSON inválido: campo Fases ausente." -ForegroundColor Red
    exit
}


# ----------------------------------------------------------------------
# Normalizar mensagens para string (remove polimorfismo)
# ----------------------------------------------------------------------
foreach ($f in $jsonRaw.Fases) {

    if ($null -eq $f.Mensagem) { continue }

    if ($f.Mensagem -isnot [string]) {

        if ($f.Mensagem -is [pscustomobject] -or $f.Mensagem -is [hashtable]) {
            $f.Mensagem = ($f.Mensagem | ConvertTo-Json -Depth 5)
        }
        else {
            $f.Mensagem = ($f.Mensagem | Out-String).Trim()
        }
    }
}




# --------------------------------------------------------------------------
# Normalizar Strings com aspas duplas externas
# --------------------------------------------------------------------------
function Remove-OuterQuotes {
    param([string]$s)

    if ($null -eq $s) { return $s }

    if ($s -match '^".*"$') {
        return $s.Trim('"')
    }

    return $s
}

if ($jsonRaw.Cliente) {
    $jsonRaw.Cliente = Remove-OuterQuotes $jsonRaw.Cliente
}


# ------------------------------------------------------------------------------
# Fase: Coleta do Inventário de Hardware e Software
# ------------------------------------------------------------------------------
$fase1 = @($jsonRaw.Fases) | Where-Object { $_.Phase -match "Invent" } | Select-Object -First 1

if (-not $fase1) {
    Write-Host "❌ Fase 1 não encontrada." -ForegroundColor Red
    exit
}

if (-not $fase1.Mensagem) {
    Write-Host "❌ Inventário sem conteúdo." -ForegroundColor Red
    exit
}

$msg = $fase1.Mensagem -split "`r`n"


# ------------------------------------------------------------------------------
# Encontrar início da lista de softwares
# ------------------------------------------------------------------------------
$indexSoftware = $null

for ($i = 0; $i -lt $msg.Count; $i++) {
    $linha = $msg[$i].Trim()
    if ($linha -match "Softwares" -or $linha -match "Instalados") {
        $indexSoftware = $i
        break
    }
}

if ($null -eq $indexSoftware)
 {
    Write-Host "❌ Não consegui identificar onde começam os softwares." -ForegroundColor Red
    exit
 }

# ------------------------------------------------------------------------------
# Divisão Hardware / Softwares
# ------------------------------------------------------------------------------
if ($indexSoftware -le 0) {
    Write-Host "❌ Estrutura inesperada no inventário." -ForegroundColor Red
    exit
}
$hardwareLines = $msg[0..($indexSoftware - 1)]
$softwareLines = $msg[($indexSoftware + 1)..($msg.Count - 1)]

$softwareList = $softwareLines |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -ne "" } |
    Sort-Object -Unique

# ------------------------------------------------------------------------------
# Identificar blocos Armazenamento e Partições
# ------------------------------------------------------------------------------
$idxArmazenamento = ($hardwareLines | Select-String "^\s*Armazenamento\s*:" | Select-Object -First 1).LineNumber
$idxParticoes     = ($hardwareLines | Select-String "^\s*Partições\s*:" | Select-Object -First 1).LineNumber


$armazenamentosRaw = @()
$particoesRaw = @()

# -------- ARMAZENAMENTO --------------------------------------------------------
if ($null -ne $idxArmazenamento) {
    $start = $idxArmazenamento - 1

    if ($hardwareLines[$start] -match "Armazenamento\s*:\s*(.*)$") {
        if ($matches[1].Trim() -ne "") { $armazenamentosRaw += $matches[1].Trim() }
    }

    for ($j = $start + 1; $j -lt $hardwareLines.Count; $j++) {

        $linha = $hardwareLines[$j].Trim()

        if ($linha -match "^[A-Za-z].*:\s*$") { break }

        if ($linha -ne "") { $armazenamentosRaw += $linha }
    }
}

# -------- PARTIÇÕES ------------------------------------------------------------
if ($null -ne $idxParticoes) {
    $start = $idxParticoes - 1

    if ($hardwareLines[$start] -match "Partições\s*:\s*(.*)$") {
        if ($matches[1].Trim() -ne "") { $particoesRaw += $matches[1].Trim() }
    }

    for ($j = $start + 1; $j -lt $hardwareLines.Count; $j++) {

        $linha = $hardwareLines[$j].Trim()

        if ($linha -match "^[A-Za-z].*:\s*$") { break }

        if ($linha -ne "") { $particoesRaw += $linha }
    }
}

# ------------------------------------------------------------------------------
# Hardware — sem discos e sem partições
# ------------------------------------------------------------------------------
$hardwareObj = @{}

foreach ($line in $hardwareLines) {

    $linha = $line.Trim()

    if ($linha -eq "") { continue }
    if ($linha -match "^Armazenamento") { continue }
    if ($linha -match "^Partições")     { continue }
    if ($linha -match "->\s*Status")    { continue }
    if ($linha -match "^[A-Z]:")        { continue }
    if ($linha -match "% livres") { continue }
    if ($linha -match "^(.*?):\s*(.*)$") {
        $hardwareObj[$matches[1].Trim()] = $matches[2].Trim()
    }
}

# Guardar IP e MAC caso precise para fallback
$ipHardware  = $hardwareObj["Endereço IP"]
$macHardware = $hardwareObj["Endereço MAC"]

# ------------------------------------------------------------------------------
# Adaptadores de rede — coleta TODOS os adaptadores
# ------------------------------------------------------------------------------
$redes = @()

try {
    $adapters = Get-NetAdapter -ErrorAction SilentlyContinue

    foreach ($adapter in $adapters) {
        
        $ip = (Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
            Select-Object -First 1).IPAddress

        $dnsServers = (Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses

        $redes += [PSCustomObject]@{
            Adaptador     = $adapter.Name
            Descricao     = $adapter.InterfaceDescription
            Tipo          = $adapter.InterfaceType
            Status        = $adapter.Status
            Velocidade    = $adapter.LinkSpeed
            EnderecoIP    = $ip
            EnderecoMAC   = $adapter.MacAddress
            DNSPrimario   = if ($dnsServers.Count -ge 1) { $dnsServers[0] } else { $null }
            DNSSecundario = if ($dnsServers.Count -ge 2) { $dnsServers[1] } else { $null }
        }
    }
}
catch {
    $redes = @()
}

if ($redes.Count -eq 0) {
    $redes += [PSCustomObject]@{
        Adaptador     = "Indisponível"
        Descricao     = $null
        Tipo          = $null
        Status        = $null
        Velocidade    = $null
        EnderecoIP    = $ipHardware
        EnderecoMAC   = $macHardware
        DNSPrimario   = $null
        DNSSecundario = $null
    }
}


# Remover IP/MAC do Hardware
$hardwareObj.Remove("Endereço IP")
$hardwareObj.Remove("Endereço MAC")

# ------------------------------------------------------------------------------
# Armazenamentos — com capacidade total
# ------------------------------------------------------------------------------
$discosPhysical = @{}
try {
    Get-PhysicalDisk -ErrorAction SilentlyContinue | ForEach-Object {
        $discosPhysical[$_.FriendlyName] = [Math]::Round($_.Size / 1GB, 2)
    }
} catch {}

$armazenamentos = @(
    foreach ($a in $armazenamentosRaw) {
        if ($a -match "^(.*?)\s*->\s*Status:\s*(.*)$") {
            $nome = $matches[1].Trim()
            $status = $matches[2].Trim()
            $capacidade = $discosPhysical[$nome]
            
            [PSCustomObject]@{
                Nome              = $nome
                Status            = $status
                CapacidadeTotalGB = $capacidade
            }
        }
    }
)


# ------------------------------------------------------------------------------
# Partições — Espaço real (GB) + percentagem utilizada
# ------------------------------------------------------------------------------
$particoes = @(
    foreach ($p in $particoesRaw) {
        if ($p -match "^([A-Z]):.*?([\d\.]+)\s*GB.*?([\d\.]+)%") {

            $letra     = $matches[1]
            $tamanho   = [double]$matches[2]
            $pctLivre  = [double]$matches[3]

            $livreGB = [Math]::Round(($tamanho * $pctLivre) / 100, 2)
            $usadoGB = [Math]::Round(($tamanho - $livreGB), 2)
            $pctUsado = [Math]::Round((($tamanho - $livreGB) / $tamanho) * 100, 2)

            [PSCustomObject]@{
                Letra     = $letra
                TamanhoGB = $tamanho
                LivreGB   = $livreGB
                UsadoGB   = $usadoGB
                UsadoPct  = $pctUsado
            }
        }
    }
)


# ------------------------------------------------------------------------------
# Fase: Integridade do Sistema com SFC/DISM estruturado e interpretado
# ------------------------------------------------------------------------------
$fase2 = @($jsonRaw.Fases) |
    Where-Object { $_.Phase -match "Registro" } |
    Select-Object -First 1


if ($fase2) {

    $linhasF2 = $fase2.Mensagem -split "`r`n"
    $tecnico = @{}

    foreach ($l in $linhasF2) {
        if ($l -match "^(.*?):\s*(.*)$") {

            $k = $matches[1].Trim()
            $v = $matches[2].Trim()

            if ($v -match "^(?i:true|false)$") {
               $v = ($v.ToLower() -eq "true")
            }

            elseif ($v -match "^\d+$") { $v = [int]$v }

            $tecnico[$k] = $v
        }
    }

    # interpretar estados técnicos
    $sfcOk   = ($tecnico["SfcExitCode"]   -eq 0)
    $dismOk  = ($tecnico["DismExitCode"]  -eq 0)
    $cleanOk = ($tecnico["ComponentCleanupExitCode"] -eq 0)

    $pendBefore = $false
    $pendAfter  = $false

    if ($tecnico.ContainsKey("PendingRebootBefore")) {
        $pendBefore = ($tecnico["PendingRebootBefore"].ToString().ToLower() -eq "true")
    }

    if ($tecnico.ContainsKey("PendingRebootAfter")) {
        $pendAfter = ($tecnico["PendingRebootAfter"].ToString().ToLower() -eq "true")
    }

    # texto interpretado
    $statusTexto = ""

    if ($sfcOk -and $dismOk -and $cleanOk) {
        $statusTexto = "Os arquivos essenciais do Windows estão íntegros e a verificação concluiu com sucesso."
    }
    else {
        $statusTexto = "Foram detectados problemas na verificação da integridade do Windows."
    }

    if ($pendAfter) {
        $statusTexto += " É recomendável reiniciar o computador para finalizar pendências."
    }

    # substituir mensagem por objeto estruturado
    $fase2.Mensagem = [PSCustomObject]@{
        IntegridadeArquivos        = if ($sfcOk -and $dismOk) { "OK" } else { "Problemas encontrados" }
        SfcCorrompido              = (-not $sfcOk)
        DismCorrompido             = (-not $dismOk)
        LimpezaRealizada           = $cleanOk
        ReinicioAntesNecessario    = $pendBefore
        ReinicioDepoisNecessario   = $pendAfter
        IntegridadeSistema          = $statusTexto
        DetalhesTecnicos           = $tecnico
    }
}


# ------------------------------------------------------------------------------
# Fase: Limpeza de todas as lixeiras — interpretação estruturada
# ------------------------------------------------------------------------------
$faseLixo = @($jsonRaw.Fases) | Where-Object { $_.Phase -match "lixeiras" }

if ($faseLixo) {

    # Dividir por cada unidade do texto original
    $entries = $faseLixo.Mensagem -split "\|"

    $detalhes = @()
    $sucessoTotal = $true
    $itensTotaisDeletados = 0

    foreach ($e in $entries) {

        if ($e -match "Drive=(.*?),\s*Success=(.*?),\s*ItemsDeleted=(.*?),\s*Errors=(.*)$") {

            $drive = $matches[1].Trim()
            $success = ($matches[2].ToString().ToLower() -eq "true")
            $deleted = [int]$matches[3]
            $errors  = $matches[4].Trim()

            if (-not $success) { $sucessoTotal = $false }

            $itensTotaisDeletados += $deleted

            $detalhes += [PSCustomObject]@{
                Unidade        = $drive
                Sucesso        = $success
                ItensDeletados = $deleted
                Erros          = if ($errors -ne "") { $errors } else { $null }
            }
        }
    }

    # interpretação humana
    $resultado = ""

    if ($sucessoTotal) {
        if ($itensTotaisDeletados -gt 0) {
            $resultado = "As lixeiras foram esvaziadas com sucesso e itens foram removidos."
        } else {
            $resultado = "As lixeiras foram esvaziadas, mas já estavam vazias."
        }
    } else {
        $resultado = "Houve falhas ao esvaziar uma ou mais lixeiras."
    }

    # substituir a mensagem original por um objeto estruturado
    $faseLixo.Mensagem = [PSCustomObject]@{
        LimpezaBemSucedida    = $sucessoTotal
        TotalItensRemovidos   = $itensTotaisDeletados
        IntegridadeLixeira    = $resultado
        DetalhesPorUnidade    = $detalhes
    }
}

# ------------------------------------------------------------------------------
# Fase: Atualização do Windows — interpretação estruturada
# ------------------------------------------------------------------------------
$faseUpdate = @($jsonRaw.Fases) | Where-Object { $_.Phase -match "Atualização do Windows" }

if ($faseUpdate) {

    $linhas = $faseUpdate.Mensagem -split "`r`n"
    $tecnico = @{}

    # ler linhas com chave : valor
    foreach ($l in $linhas) {
        if ($l -match "^(.*?):\s*(.*)$") {
            $key = $matches[1].Trim()
            $val = $matches[2].Trim()

            if ($val -match "^\d+$") { $val = [int]$val }

            $tecnico[$key] = $val
        }
    }

    # identificar código de saída
    $exitCode = $null

    # tenta extrair "ExitCode=0"
    foreach ($l in $linhas) {
        if ($l -match "ExitCode\s*=\s*(\d+)") {
            $exitCode = [int]$matches[1]
            break
        }
    }

    # interpretação
    $ok = ($exitCode -eq 0)

    $interpreta = if ($ok) {
        "A atualização do Windows foi concluída com sucesso."
    } else {
        "A atualização do Windows encontrou erros."
    }

    # substituir mensagem crua por estrutura limpa
    $faseUpdate.Mensagem = [PSCustomObject]@{
        AtualizacaoBemSucedida = $ok
        CodigoSaida            = $exitCode
        IntegridadeAtualizacao = $interpreta
        DetalhesTecnicos       = $tecnico
    }
}

# ------------------------------------------------------------------------------
# Fase: Atualização da Loja da Microsoft — interpretação estruturada
# ------------------------------------------------------------------------------
$faseStore = @($jsonRaw.Fases) | Where-Object { $_.Phase -match "Loja da Microsoft" }

if ($faseStore) {

    $linhas = $faseStore.Mensagem -split "`r`n"
    $tecnico = @{}
    $exitCode = $null

    # extrair tabela técnica
    foreach ($l in $linhas) {

        # detectar ExitCode=XXXX
        if ($l -match "ExitCode\s*=\s*([-]?\d+)") {
            $exitCode = [int]$matches[1]
        }

        if ($l -match "^(.*?):\s*(.*)$") {
            $k = $matches[1].Trim()
            $v = $matches[2].Trim()

            if ($v -match "^\-?\d+$") {
                $v = [int]$v
            }

            $tecnico[$k] = $v
        }
    }

    # interpretar
    $ok = ($exitCode -eq 0 -or $exitCode -lt 0)

    if ($ok) {
        $interpretacao = "A atualização da Microsoft Store foi concluída sem erros relevantes."
    } else {
        $interpretacao = "A atualização da Microsoft Store encontrou falhas."
    }

    # estruturar mensagem
    $faseStore.Mensagem = [PSCustomObject]@{
        AtualizacaoBemSucedida = $ok
        CodigoSaida            = $exitCode
        IntegridadeAtualizacao = $interpretacao
        DetalhesTecnicos       = $tecnico
    }
}

# ------------------------------------------------------------------------------
# Fase: Atualização dos programas via Winget — interpretação estruturada
# ------------------------------------------------------------------------------
$faseWinget = @($jsonRaw.Fases) | Where-Object { $_.Phase -match "Winget" }

if ($faseWinget) {

    $linhas = $faseWinget.Mensagem -split "`r`n"
    $tecnico = @{}
    $exitCode = $null

    foreach ($l in $linhas) {

        # Detectar ExitCode=0
        if ($l -match "ExitCode\s*=\s*([-]?\d+)") {
            $exitCode = [int]$matches[1]
        }

        # Chave:Valor
        if ($l -match "^(.*?):\s*(.*)$") {
            $k = $matches[1].Trim()
            $v = $matches[2].Trim()

            if ($v -match "^\-?\d+$") { $v = [int]$v }

            $tecnico[$k] = $v
        }
    }

    # interpretação
    $sucesso = ($exitCode -eq 0)

    $interpretacao = if ($sucesso) {
        "As atualizações dos programas via Winget foram concluídas com sucesso."
    } else {
        "Ocorreram erros ao atualizar programas via Winget."
    }

    # substituir por objeto estruturado
    $faseWinget.Mensagem = [PSCustomObject]@{
        AtualizacaoBemSucedida = $sucesso
        CodigoSaida            = $exitCode
        IntegridadeWinget      = $interpretacao
        DetalhesTecnicos       = $tecnico
    }
}

# ------------------------------------------------------------------------------
# Fase: Limpeza dos arquivos temporários dos componentes do Windows — estruturada
# ------------------------------------------------------------------------------
$faseDismClean = @($jsonRaw.Fases) | Where-Object { $_.Phase -match "componentes do Windows" }

if ($faseDismClean) {

    $linhas = $faseDismClean.Mensagem -split "`r`n"

    $versaoFerramenta = $null
    $versaoImagem = $null
    $sucesso = $false

    foreach ($l in $linhas) {

        if ($l -match "Vers[aã]o:\s*(.*)$") {
            $versaoFerramenta = $matches[1].Trim()
        }

        if ($l -match "Vers[aã]o da Imagem:\s*(.*)$") {
            $versaoImagem = $matches[1].Trim()
        }

        if ($l -match "conclu[ií]da? com êxito|\bsucesso\b") {
            $sucesso = $true
        }
    }

    # criar texto interpretado
    $interpretacao = if ($sucesso) {
        "A limpeza de componentes do Windows foi concluída com sucesso."
    } else {
        "A limpeza de componentes do Windows encontrou problemas."
    }

    # substituir por objeto limpo
    $faseDismClean.Mensagem = [PSCustomObject]@{
        LimpezaBemSucedida       = $sucesso
        VersaoFerramentaDISM     = $versaoFerramenta
        VersaoImagemWindows      = $versaoImagem
        IntegridadeComponentes    = $interpretacao
        Observacoes              = "StartComponentCleanup executado para remover componentes antigos do Windows."
    }
}

# ------------------------------------------------------------------------------
# Fase: Varredura contra malwares com Windows Defender — estruturada
# ------------------------------------------------------------------------------
$faseDefender = @($jsonRaw.Fases) | Where-Object { $_.Phase -match "Windows Defender" }

if ($faseDefender) {

    $linhas = $faseDefender.Mensagem -split "`r`n"
    $tecnico = @{}
    $exitCode = $null

    foreach ($l in $linhas) {

        # Detectar ExitCode=0
        if ($l -match "ExitCode\s*=\s*([-]?\d+)") {
            $exitCode = [int]$matches[1]
        }

        # Detectar chave:valor
        if ($l -match "^(.*?):\s*(.*)$") {
            $k = $matches[1].Trim()
            $v = $matches[2].Trim()

            if ($v -match "^\-?\d+$") { $v = [int]$v }
            $tecnico[$k] = $v
        }
    }

    # interpretação
    $sucesso = ($exitCode -eq 0)

    if ($sucesso) {
        $interpretacao = "A varredura foi concluída e nenhuma ameaça foi detectada pelo Windows Defender."
    } else {
        $interpretacao = "A varredura encontrou possíveis ameaças ou erros."
    }

    # substituir mensagem original por objeto estruturado
    $faseDefender.Mensagem = [PSCustomObject]@{
        ScanBemSucedido       = $sucesso
        CodigoSaida           = $exitCode
        IntegridadeAntivirus  = $interpretacao
        DetalhesTecnicos      = $tecnico
    }
}

# ------------------------------------------------------------------------------
# Verificação de Backups do Macrium Reflect
# ------------------------------------------------------------------------------
$macriumInfo = [PSCustomObject]@{
    ExisteParticaoD   = $false
    ExistePastaRescue = $false
    ExistemImagens    = $false
    TotalImagens      = 0
    DataImagem1       = $null
    DataImagem2       = $null
}

try {

    if (Test-Path "D:\") {

        $macriumInfo.ExisteParticaoD = $true
        $rescuePath = "D:\Rescue"

        if (Test-Path $rescuePath) {

            $macriumInfo.ExistePastaRescue = $true

            $files = @(
                Get-ChildItem $rescuePath -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object {
                    $ext = $_.Extension.ToLower().Trim()
                    $ext -eq ".mrimg" -or $ext -eq ".mrbak"
                } |
                Sort-Object LastWriteTime -Descending
            )

            if ($files.Count -gt 0) {

                $macriumInfo.ExistemImagens = $true
                $macriumInfo.TotalImagens   = $files.Count

                if ($files.Count -ge 1) {
                    $macriumInfo.DataImagem1 = $files[0].LastWriteTime
                }

                if ($files.Count -ge 2) {
                    $macriumInfo.DataImagem2 = $files[1].LastWriteTime
                }
            }
        }
    }

}
catch {}


# ------------------------------------------------------------------------------
# Saúde Geral do Sistema — Consolidação de todas as fases
# ------------------------------------------------------------------------------

# =============== 1. Integridade do Sistema (SFC/DISM) ===============
$notaIntegridade = 0
if ($fase2) {
    if ($fase2.Mensagem.IntegridadeArquivos -eq "OK") {
        $notaIntegridade = 100
    } else {
        $notaIntegridade = 40
    }
}

# =============== 2. Atualizações (Windows + Store + Winget) ===============
$notaAtualizacoes = 0
$faseUpdateWin = @($jsonRaw.Fases) | Where-Object { $_.Phase -match "Atualização do Windows" }
$faseStore     = @($jsonRaw.Fases) | Where-Object { $_.Phase -match "Loja da Microsoft" }
$faseWinget    = @($jsonRaw.Fases) | Where-Object { $_.Phase -match "Winget" }

$okWin   = $faseUpdateWin  -and $faseUpdateWin.Mensagem.AtualizacaoBemSucedida
$okStore = $faseStore      -and $faseStore.Mensagem.AtualizacaoBemSucedida
$okWing  = $faseWinget     -and $faseWinget.Mensagem.AtualizacaoBemSucedida

$sucessos = @($okWin, $okStore, $okWing) | Where-Object { $_ -eq $true } | Measure-Object | Select-Object -ExpandProperty Count

switch ($sucessos) {
    3 { $notaAtualizacoes = 100 }
    2 { $notaAtualizacoes = 80 }
    1 { $notaAtualizacoes = 60 }
    0 { $notaAtualizacoes = 30 }
}

# =============== 3. Armazenamentos (SSD/HDD) ===============
$notaArmazenamento = 0
if ($armazenamentos.Count -gt 0) {
    $discosOK = ($armazenamentos | Where-Object { $_.Status -match "Saud" }).Count
    if ($discosOK -eq $armazenamentos.Count) {
        $notaArmazenamento = 100
    } elseif ($discosOK -gt 0) {
        $notaArmazenamento = 70
    } else {
        $notaArmazenamento = 30
    }
}

# =============== 4. Partições (base UsadoPct) ===============
$notaParticoes = 100

foreach ($p in $particoes) {
    if ($p.UsadoPct -gt 95) { $notaParticoes = [Math]::Min($notaParticoes, 10) }
    elseif ($p.UsadoPct -gt 85) { $notaParticoes = [Math]::Min($notaParticoes, 40) }
    elseif ($p.UsadoPct -gt 70) { $notaParticoes = [Math]::Min($notaParticoes, 70) }
    else { $notaParticoes = [Math]::Min($notaParticoes, 100) }
}

# =============== 5. Segurança (Windows Defender) ===============
$notaSeguranca = 0
$faseDefender = @($jsonRaw.Fases) | Where-Object { $_.Phase -match "Windows Defender" }

if ($faseDefender -and $faseDefender.Mensagem.ScanBemSucedido) {
    $notaSeguranca = 100
} else {
    $notaSeguranca = 40
}

# =============== 6. Rede (prioriza Ethernet, depois Wi-Fi, depois qualquer Up) ===============
$notaRede = 0
$redeAvaliada = $redes | Where-Object { $_.Adaptador -eq "Ethernet" } | Select-Object -First 1
if (-not $redeAvaliada) {
    $redeAvaliada = $redes | Where-Object { $_.Adaptador -eq "Wi-Fi" } | Select-Object -First 1
}
if (-not $redeAvaliada) {
    $redeAvaliada = $redes | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
}

if ($redeAvaliada) {
    switch ($redeAvaliada.Status) {
        "Up" { $notaRede = 100 }
        default { $notaRede = 40 }
    }

    if ($redeAvaliada.Velocidade -match "100 Mbps") { $notaRede = 70 }
    if ($redeAvaliada.Velocidade -match "10 Mbps")  { $notaRede = 40 }
}

# =============== 7. Limpezas e Otimizações ===============
$notaLimpezas = 100  # Se chegou até aqui no script, todas as limpezas foram executadas


# =============== 8. Backup Macrium ===============
$notaBackup = 0

if ($macriumInfo.ExisteParticaoD -eq $false) {
    $notaBackup = 0
}
elseif ($macriumInfo.ExistePastaRescue -eq $false) {
    $notaBackup = 0
}
elseif ($macriumInfo.ExistemImagens -eq $false) {
    $notaBackup = 0
}
else {
    if ($macriumInfo.DataImagem1) {
        $dias = (New-TimeSpan -Start $macriumInfo.DataImagem1 -End (Get-Date)).Days

        if ($dias -le 30) {
            $notaBackup = 100
        }
        elseif ($dias -le 90) {
            $notaBackup = 80
        }
        else {
            $notaBackup = 50
        }
    }
    else {
        $notaBackup = 0
    }
}




# =============== Ponderação final (0–100) ===============

$saudeFinal = `
($notaIntegridade * 0.27) +
($notaAtualizacoes * 0.18) +
($notaArmazenamento * 0.18) +
($notaParticoes * 0.08) +
($notaSeguranca * 0.14) +
($notaRede * 0.03) +
($notaLimpezas * 0.02) +
($notaBackup * 0.10)


$saudeFinal = [Math]::Round($saudeFinal)

# Classificação textual
$classificacao = switch ($saudeFinal) {
    {$_ -ge 90} { "Excelente"; break }
    {$_ -ge 75} { "Boa"; break }
    {$_ -ge 50} { "Regular"; break }
    default     { "Crítica" }
}

# Inserir no JSON final
if ($jsonRaw.PSObject.Properties.Name -contains "SaudeGeral") {
    $jsonRaw.PSObject.Properties.Remove("SaudeGeral")
}

$jsonRaw | Add-Member -MemberType NoteProperty -Name SaudeGeral -Value ([PSCustomObject]@{
    Nota          = $saudeFinal
    Classificacao = $classificacao
    Detalhes = [PSCustomObject]@{
        IntegridadeSistema = $notaIntegridade
        Atualizacoes       = $notaAtualizacoes
        Armazenamento      = $notaArmazenamento
        Particoes          = $notaParticoes
        Seguranca          = $notaSeguranca
        Rede               = $notaRede
        Limpezas           = $notaLimpezas
        Backup             = $notaBackup
    }
})


# ---------------- UUID SMBIOS ----------------
$uuidSistema = $null

try {
    $uuidSistema = (Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction Stop).UUID
}
catch {
    $uuidSistema = $null
}



# ------------------------------------------------------------------------------
# Finalizar Fase do Inventário
# ------------------------------------------------------------------------------
# ---------------- SISTEMA ----------------
$sistemaObj = [PSCustomObject]@{
    "Nome do Computador"  = $hardwareObj["Nome do Computador"]
    "Usuário Adm"         = $hardwareObj["Usuário Adm"]
    "Login ID"            = $hardwareObj["Login ID"]
    "Sistema Operacional" = $hardwareObj["Sistema Operacional"]
    "UUID SMBIOS"         = $uuidSistema
}


# ---------------- HARDWARE ----------------
$hardwareFinal = [PSCustomObject]@{
    "Processador"             = $hardwareObj["Processador (CPU)"]
    "Placa-Mãe"               = $hardwareObj["Placa-Mãe"]
    "Fabricante e Modelo PC"  = $hardwareObj["Fabricante e Modelo PC"]
    "Serial Number"           = $hardwareObj["Serial Number"]
    "Memória RAM Total"       = $hardwareObj["Memória RAM Total"]
    "Placa de Vídeo"          = $hardwareObj["Placas de Vídeo"]
}

# ---------------- FINAL ----------------
$fase1.Mensagem = [PSCustomObject]@{
    Sistema        = $sistemaObj
    Hardware       = $hardwareFinal
    Redes          = $redes
    Armazenamentos = $armazenamentos
    Particoes      = $particoes
    BackupMacrium  = $macriumInfo
    Softwares      = $softwareList
}


# --------------------------------------------------------------------------
# Exportar JSON final — No mesmo local do arquivo json original
# --------------------------------------------------------------------------

$nomeOut = Join-Path $arquivo.DirectoryName (($arquivo.BaseName) + "_TRATADO.json")

$jsonRaw | ConvertTo-Json -Depth 20 |
    Out-File $nomeOut -Encoding UTF8




Write-Host "📦 JSON gerado em: $nomeOut" -ForegroundColor Cyan
Write-Host ""


# ------------------------------------------------------------------------------
# Enviar para a API do Guardian
# ------------------------------------------------------------------------------
#$apiUrl = "http://192.168.0.210:8000/insert-single"
$apiUrl = "https://guardian.it4you.com.br/api/insert-single"


try {
    $jsonParaApi = Get-Content $nomeOut -Raw -Encoding UTF8

    $response = Invoke-RestMethod `
        -Uri $apiUrl `
        -Method POST `
        -Body $jsonParaApi `
        -ContentType "application/json; charset=utf-8"`
        -TimeoutSec 3

    Write-Host "🚀 Integração realizada com sucesso via API!" -ForegroundColor Cyan
    #Write-Host "  computador_id : $($response.computador_id)" -ForegroundColor Gray
    #Write-Host "  vistoria_id   : $($response.vistoria_id)" -ForegroundColor Gray
    #Write-Host "  nota saúde    : $($jsonRaw.SaudeGeral.Nota) - $($jsonRaw.SaudeGeral.Classificacao)" -ForegroundColor Gray

} catch {
    # Write-Host "`n⚠ Falha ao enviar para a API: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "`n🔥 GUARDIAN 360 finalizado com sucesso!"
Write-Host ""