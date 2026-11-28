<#
====================================================================
  CONVERSOR Json
  - Hardware limpo (sem discos e sem partições)
  - Armazenamentos e Partições extraídos corretamente
  - Redes estruturadas (coleta TODOS os adaptadores)
====================================================================
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNull()][object]$Relatorio,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$JsonDestino,
    [switch]$NaoEnviarApi
)

$ErrorActionPreference = 'Stop'
# Create an isolated copy in memory: transforms must never mutate the motor's
# original report or discover the last report of a different computer.
$jsonRaw = $Relatorio | ConvertTo-Json -Depth 40 -ErrorAction Stop | ConvertFrom-Json -Depth 40 -ErrorAction Stop
if ($null -eq $jsonRaw -or $jsonRaw -is [array]) { throw 'Relatorio em memoria invalido.' }
if ([string]::IsNullOrWhiteSpace([string]$jsonRaw.Cliente) -or
    [string]::IsNullOrWhiteSpace([string]$jsonRaw.NomeComputador)) {
    throw 'Relatorio sem Cliente ou NomeComputador.'
}
if ([string]$jsonRaw.NomeComputador -ine $env:COMPUTERNAME) {
    throw "Nome do computador divergente: relatorio='$($jsonRaw.NomeComputador)', ambiente='$env:COMPUTERNAME'."
}
if ($null -eq $jsonRaw.Fases -or @($jsonRaw.Fases).Count -eq 0) {
    throw 'Relatorio sem fases; consolidacao cancelada.'
}
$destinoNome = [IO.Path]::GetFileName($JsonDestino)
if (-not $destinoNome.EndsWith('.json', [StringComparison]::OrdinalIgnoreCase) -or
    $destinoNome -match '_TRATADO\.json$') {
    throw 'Destino JSON definitivo invalido.'
}

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
    throw "JSON inválido: campo Fases ausente."
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
    throw "Fase 1 não encontrada."
}

if (-not $fase1.Mensagem) {
    throw "Inventário sem conteúdo."
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
    throw "Não consegui identificar onde começam os softwares."
 }

# ------------------------------------------------------------------------------
# Divisão Hardware / Softwares
# ------------------------------------------------------------------------------
if ($indexSoftware -le 0) {
    throw "Estrutura inesperada no inventário."
}
$hardwareLines = $msg[0..($indexSoftware - 1)]
$softwareLines = $msg[($indexSoftware + 1)..($msg.Count - 1)]

# Alerta de seguranca da conta Administrador nativa (SID -500).
# A coleta inclui a linha no fim do inventario; nao e um software instalado.
$padraoAlertaAdministrador = '^\s*Alerta Administrador\s*:\s*Suspeita de senha vazia\s*$'
$alertaAdministrador = $null

if (@($softwareLines | Where-Object { $_ -match $padraoAlertaAdministrador }).Count -gt 0) {
    $alertaAdministrador = 'Suspeita de senha vazia'
    $jsonRaw | Add-Member -MemberType NoteProperty -Name 'alerta_administrador' -Value $alertaAdministrador -Force
}

$softwareList = $softwareLines |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -ne "" -and $_ -notmatch $padraoAlertaAdministrador } |
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
# Armazenamentos — com capacidade total e tipo de mídia
# ------------------------------------------------------------------------------
$discosPhysical = @{}
try {
    Get-PhysicalDisk -ErrorAction SilentlyContinue | ForEach-Object {
        $discosPhysical[$_.FriendlyName] = @{
            Capacidade = [Math]::Round($_.Size / 1GB, 2)
            TipoMidia  = $_.MediaType
        }
    }
} catch {}

$armazenamentos = @(
    foreach ($a in $armazenamentosRaw) {
        if ($a -match "^(.*?)\s*->\s*Status:\s*(.*)$") {
            $nome = $matches[1].Trim()
            $status = $matches[2].Trim()
            $capacidade = $null
            $tipoMidia = "Desconhecido"
            
            if ($discosPhysical.ContainsKey($nome)) {
                $capacidade = $discosPhysical[$nome].Capacidade
                $tipoMidia = $discosPhysical[$nome].TipoMidia
            }
            
            # Fallback: detectar tipo pelo nome se MediaType não disponível
            if ($tipoMidia -eq "Unspecified" -or $tipoMidia -eq "Desconhecido" -or [string]::IsNullOrEmpty($tipoMidia)) {
                $nomeUpper = $nome.ToUpper()
                if ($nomeUpper -match "SSD|SOLID|NVME|M\.2") {
                    $tipoMidia = "SSD"
                } elseif ($nomeUpper -match "HDD|HARD|WD\d|ST\d|SEAGATE|WESTERN|TOSHIBA MQ|TOSHIBA DT") {
                    $tipoMidia = "HDD"
                } else {
                    $tipoMidia = "Desconhecido"
                }
            }
            
            [PSCustomObject]@{
                Nome              = $nome
                Status            = $status
                TipoMidia         = $tipoMidia
                CapacidadeTotalGB = $capacidade
            }
        }
    }
)


# ------------------------------------------------------------------------------
# Partições — Espaço real (GB) + percentagem utilizada
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# COLETA FRESCA DAS PARTIÇÕES (após limpezas)
# ------------------------------------------------------------------------------
$particoes = @()
try {
    # -ErrorAction Stop: falha na consulta deve cair no fallback (antes devolvia lista vazia em silêncio).
    $drives = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType = 3" -ErrorAction Stop
    foreach ($d in $drives) {
        if ($d.Size -and $d.Size -gt 0) {
            $tamanhoGB = [Math]::Round($d.Size / 1GB, 2)
            $livreGB   = [Math]::Round($d.FreeSpace / 1GB, 2)
            $usadoGB   = [Math]::Round(($d.Size - $d.FreeSpace) / 1GB, 2)
            $usadoPct  = [Math]::Round((($d.Size - $d.FreeSpace) / $d.Size) * 100, 2)

            $particoes += [PSCustomObject]@{
                Letra     = $d.DeviceID.TrimEnd(':')
                TamanhoGB = $tamanhoGB
                LivreGB   = $livreGB
                UsadoGB   = $usadoGB
                UsadoPct  = $usadoPct
            }
        }
    }
    # Nenhuma partição coletada: usa o fallback em vez de seguir com lista vazia (nota 100 sem medir).
    if (@($particoes).Count -eq 0) { throw 'Nenhuma partição fixa retornada pela consulta.' }
} catch {
    # Fallback: usar dados do JSON anterior se a coleta falhar
    $particoes = @(
        foreach ($p in $particoesRaw) {
            if ($p -match "^([A-Z]):.*?([\d\.]+)\s*GB.*?([\d\.]+)%") {
                $letra     = $matches[1]
                $tamanho   = [double]$matches[2]
                $pctLivre  = [double]$matches[3]
                $livreGB   = [Math]::Round(($tamanho * $pctLivre) / 100, 2)
                $usadoGB   = [Math]::Round(($tamanho - $livreGB), 2)
                $pctUsado  = [Math]::Round((($tamanho - $livreGB) / $tamanho) * 100, 2)

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
}


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

    $linhas = [string]$faseWinget.Mensagem -split '\r?\n'
    $tecnico = @{}
    $exitCode = $null

    foreach ($l in $linhas) {

        # O retorno do objeto PowerShell via Out-String usa "ExitCode : 0".
        # Aceitar tambem "ExitCode=0", somente como campo independente.
        if ($l -match '^\s*ExitCode\s*[:=]\s*(-?\d+)\s*$') {
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
# A Fase 2 roda separadamente via Guardian Ghost, que grava o resultado em guardian_ghost.json
# (bloco "integridade"). A nota usa esse resultado real. Sem dado válido (arquivo ou bloco ausente,
# data inválida ou com mais de 60 dias) mantém 100 como antes: não penaliza sem ter medido.
$notaIntegridade = 100
try {
    $ghostJsonPath = 'C:\Guardian\guardian_ghost.json'
    if (Test-Path -LiteralPath $ghostJsonPath -PathType Leaf) {
        $ghostInfo  = Get-Content -LiteralPath $ghostJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $ghostInteg = $ghostInfo.integridade
        if ($ghostInteg -and $null -ne $ghostInteg.sfc_exit_code -and $null -ne $ghostInteg.dism_exit_code -and $ghostInteg.data) {
            $ghostData  = [datetime]::ParseExact([string]$ghostInteg.data, 'yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
            $ghostIdade = (New-TimeSpan -Start $ghostData -End (Get-Date)).Days
            if ($ghostIdade -le 60) {
                $ghostSfcOk   = ([int]$ghostInteg.sfc_exit_code -eq 0)
                $ghostDismOk  = ([int]$ghostInteg.dism_exit_code -eq 0)
                $ghostCleanOk = ($null -eq $ghostInteg.cleanup_exit_code) -or ([int]$ghostInteg.cleanup_exit_code -eq 0)
                if ($ghostSfcOk -and $ghostDismOk) {
                    $notaIntegridade = if ($ghostCleanOk) { 100 } else { 90 }
                } elseif ($ghostSfcOk -or $ghostDismOk) {
                    $notaIntegridade = 40
                } else {
                    $notaIntegridade = 10
                }
            }
        }
    }
} catch {
    # Leitura do resultado do Ghost nunca interrompe o relatório.
    $notaIntegridade = 100
}

# =============== 2. Atualizações (Windows + Store + Winget) ===============
$notaAtualizacoes = 0
$faseUpdateWin = @($jsonRaw.Fases) | Where-Object { $_.Phase -match "Atualização do Windows" }
$faseStore     = @($jsonRaw.Fases) | Where-Object { $_.Phase -match "Loja da Microsoft" }
$faseWinget    = @($jsonRaw.Fases) | Where-Object { $_.Phase -match "Winget" }

# Só entram na conta as verificações que realmente existem: fase pulada de propósito
# (-PulaFases 5 ou 6) não conta como falha, e a Loja só conta se a etapa tiver rodado
# (hoje ela não é chamada pelo Guardian).
$fasesPuladas = @(@($jsonRaw.PulaFases) | ForEach-Object { try { [int]$_ } catch { } })
$avaliacoes = @()
if ($fasesPuladas -notcontains 5) { $avaliacoes += [bool]($faseUpdateWin -and $faseUpdateWin.Mensagem.AtualizacaoBemSucedida) }
if ($fasesPuladas -notcontains 6) { $avaliacoes += [bool]($faseWinget    -and $faseWinget.Mensagem.AtualizacaoBemSucedida) }
if ($faseStore)                   { $avaliacoes += [bool]($faseStore.Mensagem.AtualizacaoBemSucedida) }

if ($avaliacoes.Count -eq 0) {
    $notaAtualizacoes = 100   # nada a avaliar nesta execução
} else {
    $proporcaoAtualizacoes = (@($avaliacoes | Where-Object { $_ -eq $true }).Count) / $avaliacoes.Count
    if     ($proporcaoAtualizacoes -ge 1)    { $notaAtualizacoes = 100 }
    elseif ($proporcaoAtualizacoes -ge 0.66) { $notaAtualizacoes = 80 }
    elseif ($proporcaoAtualizacoes -ge 0.5)  { $notaAtualizacoes = 60 }
    else                                     { $notaAtualizacoes = 30 }
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
# Proporção das etapas de limpeza/otimização que terminaram OK nesta execução.
# Sem nenhuma dessas etapas no JSON (todas puladas), mantém 100 como antes.
$notaLimpezas = 100
$fasesLimpeza = @(@($jsonRaw.Fases) | Where-Object { $_.Phase -match '^(Limpeza|Otimização|Desfragmentação)' })
if ($fasesLimpeza.Count -gt 0) {
    $limpezasOk = @($fasesLimpeza | Where-Object { $_.Status -eq 'OK' }).Count
    $notaLimpezas = [int][Math]::Round(($limpezasOk / $fasesLimpeza.Count) * 100)
}


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


# ---------------- UUID SMBIOS + CPU ID + NOME DO COMPUTADOR ----------------
$uuidSistema = $null

try {
    $uuid  = ([string](Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction Stop).UUID).Trim()
    $cpuId = ([string](Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1).ProcessorId).Trim()
    # O nome do relatorio ja foi validado contra o nome real da maquina.
    $nomeIdentidade = ([string]$jsonRaw.NomeComputador).Trim()
    if (-not [string]::IsNullOrWhiteSpace($uuid) -and -not [string]::IsNullOrWhiteSpace($cpuId) -and
        -not [string]::IsNullOrWhiteSpace($nomeIdentidade) -and -not $nomeIdentidade.Contains('|')) {
        $uuidSistema = "$uuid|$cpuId|$nomeIdentidade"
    }
} catch {
    $uuidSistema = $null
}

# Identificador incompleto nao pode provocar associacao indevida entre maquinas.
if (-not $uuidSistema) {
    throw "Identificador incompleto: UUID SMBIOS, CPU ID ou NomeComputador indisponivel/invalido. Integracao cancelada."
}

# ------------------------------------------------------------------------------
# Finalizar Fase do Inventário
# ------------------------------------------------------------------------------
# ---------------- SISTEMA ----------------
$sistemaObj = [PSCustomObject]@{
    "Nome do Computador"  = $hardwareObj["Nome do Computador"]
    "Usuário Adm"         = $hardwareObj["Usuário Adm"]
    "Login ID"            = $hardwareObj["Login ID"]
    "Usuário Logado"       = $hardwareObj["Usuário Logado"]
    "Tipo de Conta"        = $hardwareObj["Tipo de Conta"]
    "Permissão do Usuário" = $hardwareObj["Permissão do Usuário"]
    "Guardian Elevado"     = $hardwareObj["Guardian Elevado"]
    "Conta de Execução"    = $hardwareObj["Conta de Execução"]
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


# ------------------------------------------------------------------------------
# RustDesk — Coleta de dados de acesso remoto
# ------------------------------------------------------------------------------
try {
    . "$PSScriptRoot\Manage-RustDesk.ps1"
    $rustdeskData = Manage-RustDesk 6>$null

    if ($rustdeskData) {
        $rustdeskObj = [PSCustomObject]@{
            rustdesk_id      = $rustdeskData.rustdesk_id
            rustdesk_pw      = $rustdeskData.rustdesk_pw
            rustdesk_status  = $rustdeskData.rustdesk_status
            rustdesk_version = $rustdeskData.rustdesk_version
        }

        if ($jsonRaw.PSObject.Properties.Name -contains "RustDesk") {
            $jsonRaw.PSObject.Properties.Remove("RustDesk")
        }

        $jsonRaw | Add-Member -MemberType NoteProperty -Name RustDesk -Value $rustdeskObj
    }
}
catch {
    Write-Host "[RustDesk] Erro na integracao: $($_.Exception.Message)" -ForegroundColor Yellow
}


# Telemetria ja coletada em memoria exclusivamente pelo Guardian.ps1.
# Este conversor NAO invoca Get-HardwareTelemetry.ps1.

# --------------------------------------------------------------------------
# Exportar JSON final — No mesmo local do arquivo json original
# --------------------------------------------------------------------------

$nomeOut = [IO.Path]::GetFullPath($JsonDestino)

# ------------------------------------------------------------------------------
# Sanitizacao Unicode do objeto FINAL, apos incorporar a telemetria.
# O PostgreSQL (jsonb) nao aceita U+0000, mesmo serializado como \u0000.
# Somente remove caracteres NUL de valores string; preserva arrays, objetos,
# numeros, booleanos, datas e a estrutura do relatorio.
# ------------------------------------------------------------------------------
function Remove-GuardianNullChars {
    param([AllowNull()][object]$Valor)

    if ($null -eq $Valor) { return $null }

    if ($Valor -is [string]) {
        return $Valor.Replace([string][char]0, '')
    }

    if ($Valor -is [System.Collections.IDictionary]) {
        foreach ($chave in @($Valor.Keys)) {
            $Valor[$chave] = Remove-GuardianNullChars -Valor $Valor[$chave]
        }
        return ,$Valor
    }

    if ($Valor -is [System.Collections.IList]) {
        for ($i = 0; $i -lt $Valor.Count; $i++) {
            $Valor[$i] = Remove-GuardianNullChars -Valor $Valor[$i]
        }
        return ,$Valor
    }

    if ($Valor -is [pscustomobject]) {
        foreach ($propriedade in $Valor.PSObject.Properties) {
            if ($propriedade.IsSettable) {
                $propriedade.Value = Remove-GuardianNullChars -Valor $propriedade.Value
            }
        }
        return $Valor
    }

    return $Valor
}

$jsonRaw = Remove-GuardianNullChars -Valor $jsonRaw

# JSON unico e definitivo. Validar integralmente antes de gravar no destino.
$conteudoFinal = $jsonRaw | ConvertTo-Json -Depth 40 -ErrorAction Stop
$validado = $conteudoFinal | ConvertFrom-Json -Depth 40 -ErrorAction Stop
if (-not $validado.SaudeGeral -or -not $validado.Fases -or
    -not $validado.Fases[0].Mensagem -or
    $validado.Fases[0].Mensagem -is [string]) {
    throw 'JSON consolidado sem SaudeGeral ou inventario estruturado; envio bloqueado.'
}
if ($validado.PSObject.Properties.Name -notcontains 'telemetria' -or
    $null -eq $validado.telemetria -or
    $validado.telemetria.status -notin @('ok','parcial') -or
    $validado.telemetria.computador -ine $validado.NomeComputador) {
    throw 'Telemetria ausente/invalida no JSON final; envio bloqueado.'
}

$dirDestino = Split-Path -Parent $nomeOut
if (-not (Test-Path -LiteralPath $dirDestino -PathType Container)) {
    New-Item -ItemType Directory -Path $dirDestino -Force -ErrorAction Stop | Out-Null
}
$arquivoTemp = Join-Path $dirDestino ('.guardian-' + [guid]::NewGuid().ToString('N') + '.tmp')
try {
    [IO.File]::WriteAllText($arquivoTemp, $conteudoFinal, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $arquivoTemp -Destination $nomeOut -Force -ErrorAction Stop
} finally {
    Remove-Item -LiteralPath $arquivoTemp -Force -ErrorAction SilentlyContinue
}

# ------------------------------------------------------------------------------
# Enviar para a API do Guardian
# ------------------------------------------------------------------------------
#$apiUrl = "http://192.168.0.210:8000/insert-single"
$apiUrl = "https://guardian.it4you.com.br/api/insert-single"


if ($NaoEnviarApi) {
    $global:GuardianEnvioApiStatus = 'Ignorado (simulacao)'
    return
}
$global:GuardianEnvioApiStatus = 'Em andamento'
$jsonParaApi = $conteudoFinal

$apiIntegrada = $false
$maxTentativasApi = 3

for ($tentativaApi = 1; $tentativaApi -le $maxTentativasApi; $tentativaApi++) {
    try {
        $response = Invoke-RestMethod `
            -Uri $apiUrl `
            -Method POST `
            -Body $jsonParaApi `
            -ContentType "application/json; charset=utf-8" `
            -TimeoutSec 10

        $global:GuardianEnvioApiStatus = 'Concluido'
        $apiIntegrada = $true
        break

    } catch {
        if ($tentativaApi -eq $maxTentativasApi) {
            Write-Host ("  API  Falha apos {0} tentativas: {1}" -f $maxTentativasApi, $_.Exception.Message) -ForegroundColor Yellow
        }

        if ($tentativaApi -lt $maxTentativasApi) {
            $esperaApi = if ($tentativaApi -eq 1) { 5 } else { 10 }
            Start-Sleep -Seconds $esperaApi
        }
    }
}

if (-not $apiIntegrada) {
    $global:GuardianEnvioApiStatus = 'Falhou (JSON preservado)' 
}


