#Requires -Version 7.0
<#
Guardian 360 - telemetria em memoria (fallback Dell SMM)
Destino sugerido: C:\Guardian\Functions\Get-HardwareTelemetry.ps1
Bibliotecas: C:\Guardian\Monitor\*.dll
Saida: objeto PowerShell (nenhum JSON de laboratorio gerado)
Nao altera tarefas nem envia diretamente a API; integracao depende do transmissor existente.
Fallback Dell SMM opcional: -SemDellSMM para desativar.
Executa apenas DellFanCmd rpm-fan1, apos fechar o LibreHardwareMonitor.
Instala PawnIO 2.2.0 silenciosamente apenas se ausente, mediante assinatura valida.
#>
[CmdletBinding()]
param(
    [switch]$PrepararPawnIO,
    [switch]$SemInstalarPawnIO,
    [switch]$SemDellSMM,
    [int]$DiasEventos = 35,
    [string]$PastaMonitor = 'C:\Guardian\Monitor'
)

$ErrorActionPreference = 'Stop'
$avisos = [System.Collections.Generic.List[string]]::new()
$versaoPawnIO = '2.2.0'


function Test-PawnIODriver {
    try {
        $driver = Get-CimInstance -ClassName Win32_SystemDriver -Filter "Name='PawnIO'" -ErrorAction Stop
        return ($null -ne $driver -and $driver.State -eq 'Running')
    } catch { return $false }
}

function Install-PawnIOIfNeeded {
    if (Test-PawnIODriver) { return 'disponivel' }
    if ($SemInstalarPawnIO) {
        $avisos.Add('PawnIO nao esta em execucao; instalacao dispensada por parametro.')
        return 'indisponivel'
    }
    $admin = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $admin) {
        $avisos.Add('PawnIO ausente e PowerShell sem privilegios administrativos. Telemetria parcial.')
        return 'indisponivel'
    }
    $instalador = Join-Path $env:TEMP 'Guardian-PawnIO-2.2.0-setup.exe'
    $url = 'https://github.com/namazso/PawnIO.Setup/releases/download/2.2.0/PawnIO_setup.exe'
    try {
        Invoke-WebRequest -Uri $url -OutFile $instalador -MaximumRedirection 5 -ErrorAction Stop
        $assinatura = Get-AuthenticodeSignature -FilePath $instalador
        if ($assinatura.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
            throw "Assinatura do instalador PawnIO nao validada: $($assinatura.Status)"
        }
        $processo = Start-Process -FilePath $instalador -ArgumentList '-install -silent' -PassThru -Wait -ErrorAction Stop
        if ($processo.ExitCode -ne 0) { throw "Instalador PawnIO terminou com codigo $($processo.ExitCode)" }
        if (-not (Test-PawnIODriver)) { throw 'Instalador encerrou, mas driver PawnIO nao consta como Running.' }
        return 'instalado'
    } catch {
        $avisos.Add("Nao foi possivel disponibilizar PawnIO: $($_.Exception.Message)")
        return 'indisponivel'
    } finally {
        Remove-Item -LiteralPath $instalador -Force -ErrorAction SilentlyContinue
    }
}

# Preflight reutiliza a instalacao original sem executar a coleta de sensores.
# Quando a telemetria for chamada normalmente, esta verificacao permanece ativa.
if ($PrepararPawnIO) {
    $estadoPawnIO = Install-PawnIOIfNeeded
    [pscustomobject]@{
        Estado = $estadoPawnIO
        Avisos = @($avisos.ToArray())
    }
    return
}

function Get-HardwareReadings($computer) {
    $dados = [System.Collections.Generic.List[object]]::new()
    $fila = [System.Collections.Generic.Queue[object]]::new()
    foreach ($h in $computer.Hardware) { $fila.Enqueue($h) }
    while ($fila.Count -gt 0) {
        $h = $fila.Dequeue()
        try {
            $h.Update()
            foreach ($s in $h.Sensors) {
                if ($null -eq $s.Value) { continue }
                $v = [double]$s.Value
                if ([double]::IsNaN($v) -or [double]::IsInfinity($v)) { continue }
                $dados.Add([pscustomobject]@{
                    hardware = [string]$h.Name
                    categoria = [string]$h.HardwareType
                    sensor = [string]$s.Name
                    sensor_id = [string]$s.Identifier
                    tipo = [string]$s.SensorType
                    valor = $v
                })
            }
        } catch { $avisos.Add("Sensor indisponivel ($($h.Name)): $($_.Exception.Message)") }
        foreach ($sub in $h.SubHardware) { $fila.Enqueue($sub) }
    }
    return $dados.ToArray()
}

function Select-Sensor($leituras, [string]$categoria, [string]$tipo, [string[]]$nomes) {
    foreach ($nome in $nomes) {
        $s = $leituras | Where-Object { $_.categoria -match $categoria -and $_.tipo -eq $tipo -and $_.sensor -eq $nome } | Select-Object -First 1
        if ($null -ne $s) { return $s }
    }
    return $null
}

function Get-Medida($leituras, [string]$categoria, [string]$tipo, [string[]]$nomes, [switch]$IgnorarZero) {
    $s = Select-Sensor $leituras $categoria $tipo $nomes
    if ($null -eq $s -or ($IgnorarZero -and $s.valor -eq 0)) { return $null }
    return [math]::Round([double]$s.valor, 2)
}


# Seleciona temperaturas exclusivamente do hardware CPU. Os sensores de
# distancia ate TjMax nao representam temperatura absoluta.
# Prioridade: Package > Core Average > Core Max > nucleos individuais > CPU generico.
# Na ausencia de agregados, a media e calculada entre os nucleos ativos,
# e o maximo e o maior valor medido entre eles.
function Get-CpuTemperatureSample($leituras) {
    $candidatos = @($leituras | Where-Object {
        $_.categoria -match 'Cpu' -and
        $_.tipo -eq 'Temperature' -and
        $null -ne $_.valor -and
        [double]$_.valor -gt -20 -and [double]$_.valor -le 150 -and
        $_.sensor -notmatch '(?i)distance|tjmax|delta|offset' -and
        $_.sensor_id -notmatch '(?i)distance|tjmax'
    })
    if ($candidatos.Count -eq 0) { return $null }

    $ordem = @(
        @{ Nome = 'package'; Padrao = '(?i)^(CPU Package|Package|CPU Die|Tdie|CPU \(Tctl/Tdie\))$'; Tipo = 'um' },
        @{ Nome = 'media_hardware'; Padrao = '(?i)^(Core Average|CPU Core Average|Core Temperatures Average)$'; Tipo = 'um' },
        @{ Nome = 'maximo_hardware'; Padrao = '(?i)^(Core Max|CPU Core Max)$'; Tipo = 'um' },
        @{ Nome = 'nucleos'; Padrao = '(?i)^(CPU Core|Core)\s*#?\s*\d+(?!\s*(?:Distance|Thread))'; Tipo = 'nucleos' },
        @{ Nome = 'cpu_generico'; Padrao = '(?i)^(CPU Core|CPU Temperature|CPU Temp|CPU|Tctl|Tdie|Core Temperature)$'; Tipo = 'um' }
    )

    foreach ($regra in $ordem) {
        $selecionados = @($candidatos | Where-Object { $_.sensor -match $regra.Padrao } |
            Sort-Object sensor_id -Unique)
        if ($selecionados.Count -eq 0) { continue }

        $valores = @($selecionados | ForEach-Object { [double]$_.valor })
        if ($regra.Tipo -eq 'nucleos') {
            $media = ($valores | Measure-Object -Average).Average
            $maximo = ($valores | Measure-Object -Maximum).Maximum
        } else {
            $media = $valores[0]
            $maximo = $valores[0]
            $selecionados = @($selecionados[0])
        }

        return [pscustomobject]@{
            media = [double]$media
            maxima = [double]$maximo
            criterio = $regra.Nome
            sensores = @($selecionados | ForEach-Object {
                [pscustomobject]@{ nome=$_.sensor; id=$_.sensor_id; temperatura_c=[math]::Round([double]$_.valor, 2) }
            })
        }
    }

    # Sensores desconhecidos nao sao classificados automaticamente como CPU.
    return $null
}

function Write-SensorSelectionLog([string]$caminho, $amostras, $selecoes) {
    try {
        $linhas = [System.Collections.Generic.List[string]]::new()
        $linhas.Add("Guardian 360 - diagnostico de sensores da CPU")
        $linhas.Add("Coletado em: $((Get-Date).ToString('o'))")
        for ($i = 0; $i -lt $amostras.Count; $i++) {
            $linhas.Add("Amostra $($i+1):")
            $todos = @($amostras[$i] | Where-Object { $_.categoria -match 'Cpu' -and $_.tipo -eq 'Temperature' })
            foreach ($s in $todos) {
                $linhas.Add("  Detectado: $($s.sensor) [$($s.sensor_id)] = $($s.valor) C")
            }
            if ($null -eq $selecoes[$i]) {
                $linhas.Add('  Selecao: nenhuma temperatura confiavel de CPU')
            } else {
                $linhas.Add("  Criterio: $($selecoes[$i].criterio)")
                foreach ($sensor in $selecoes[$i].sensores) {
                    $linhas.Add("  Utilizado: $($sensor.nome) [$($sensor.id)] = $($sensor.temperatura_c) C")
                }
            }
        }
        $logTemp = "$caminho.tmp"
        $linhas | Set-Content -LiteralPath $logTemp -Encoding utf8 -ErrorAction Stop
        Move-Item -LiteralPath $logTemp -Destination $caminho -Force -ErrorAction Stop
    } catch {
        # Log diagnostico e opcional e nunca deve interromper a coleta.
    }
}

function Get-EventSummary([int[]]$ids, [string]$providerPattern, [datetime]$inicio) {
    # Leitura somente: nao apaga, modifica nem exporta logs do Windows.
    try {
        $eventos = @(Get-WinEvent -FilterHashtable @{LogName='System'; Id=$ids; StartTime=$inicio} -ErrorAction SilentlyContinue |
            Where-Object { $_.ProviderName -match $providerPattern })
        $ultimo = $eventos | Sort-Object TimeCreated -Descending | Select-Object -First 1
        return [ordered]@{
            total = $eventos.Count
            ultimo_em = $(if ($null -eq $ultimo) { $null } else { $ultimo.TimeCreated.ToString('o') })
            ultimo_id = $(if ($null -eq $ultimo) { $null } else { [int]$ultimo.Id })
        }
    } catch {
        $avisos.Add("Consulta de eventos ($providerPattern): $($_.Exception.Message)")
        return [ordered]@{total=$null; ultimo_em=$null; ultimo_id=$null}
    }
}

$resultado = [ordered]@{
    schema_version = 1
    computador = $env:COMPUTERNAME
    coletado_em = (Get-Date).ToString('o')
    status = 'parcial'
    pawnio = [ordered]@{ versao_alvo=$versaoPawnIO; estado='indisponivel' }
    janela_amostragem_segundos = 15
    cpu = $null
    memoria = $null
    discos = @()
    gpu = $null
    ventoinhas = @()
    placa_mae = $null
    windows = $null
    eventos_windows = $null
    avisos = @()
}

# Instalar PawnIO (se necessario) ANTES de abrir a biblioteca.
$resultado.pawnio.estado = Install-PawnIOIfNeeded

try {
    $chave = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $resultado.windows = [ordered]@{
        produto = $os.Caption
        versao = $chave.DisplayVersion
        edicao = $chave.EditionID
        build = "{0}.{1}" -f $chave.CurrentBuild, $chave.UBR
        arquitetura = $os.OSArchitecture
    }
} catch { $avisos.Add("Windows: $($_.Exception.Message)") }

try {
    $inicio = (Get-Date).AddDays(-[math]::Max(1,[math]::Min(90,$DiasEventos)))
    $whea = Get-EventSummary @(17,18,19,46,47,1) 'WHEA-Logger' $inicio
    $bsod = Get-EventSummary @(1001) 'BugCheck|WER-SystemErrorReporting' $inicio
    $inesperados = Get-EventSummary @(41,6008) 'Kernel-Power|EventLog' $inicio
    $disco = Get-EventSummary @(7,51,129,153,157) '(^Disk$|storahci|stornvme|iaStor|storport)' $inicio
    $resultado.eventos_windows = [ordered]@{
        periodo_dias = [math]::Max(1,[math]::Min(90,$DiasEventos))
        whea = $whea
        telas_azuis = $bsod
        desligamentos_inesperados = $inesperados
        erros_disco = $disco
    }
    # IDs 41 e 6008 podem descrever o mesmo incidente; total e numero de eventos, nao de falhas unicas.
} catch { $avisos.Add("Eventos Windows: $($_.Exception.Message)") }

$computer = $null
try {
    $dll = Join-Path $PastaMonitor 'LibreHardwareMonitorLib.dll'
    if (-not ('LibreHardwareMonitor.Hardware.Computer' -as [type])) {
        if (-not (Test-Path -LiteralPath $dll -PathType Leaf)) { throw "DLL ausente: $dll" }
        Add-Type -Path $dll -ErrorAction Stop
    }
    $computer = [LibreHardwareMonitor.Hardware.Computer]::new()
    $computer.IsCpuEnabled = $true
    $computer.IsMotherboardEnabled = $true
    $computer.IsMemoryEnabled = $true
    $computer.IsStorageEnabled = $true
    $computer.IsGpuEnabled = $true
    $computer.IsControllerEnabled = $true
    $computer.Open()

    $amostras = @()
    for ($i = 0; $i -lt 4; $i++) {
        if ($i -gt 0) { Start-Sleep -Seconds 5 }
        $amostras += ,@(Get-HardwareReadings $computer)
    }
    $leituras = $amostras[-1]

    $cpuTemp = [System.Collections.Generic.List[double]]::new()
    $cpuMax = [System.Collections.Generic.List[double]]::new()
    $cpuCarga = [System.Collections.Generic.List[double]]::new()
    $selecoesCpu = [System.Collections.Generic.List[object]]::new()

    foreach ($amostra in $amostras) {
        $selecao = Get-CpuTemperatureSample $amostra
        $selecoesCpu.Add($selecao)
        if ($null -ne $selecao) {
            $cpuTemp.Add([double]$selecao.media)
            $cpuMax.Add([double]$selecao.maxima)
        }
        $carga = Get-Medida $amostra 'Cpu' 'Load' @('CPU Total')
        if ($null -ne $carga) { $cpuCarga.Add([double]$carga) }
    }

    Write-SensorSelectionLog (Join-Path $PastaMonitor 'telemetria-sensores.log') $amostras $selecoesCpu.ToArray()

    $cpuHardware = $leituras | Where-Object categoria -match 'Cpu' | Select-Object -First 1
    if ($null -ne $cpuHardware) {
        $resultado.cpu = [ordered]@{
            nome = $cpuHardware.hardware
            temperatura_media_c = $(if ($cpuTemp.Count) { [math]::Round(($cpuTemp | Measure-Object -Average).Average,2) } else { $null })
            temperatura_max_c = $(if ($cpuMax.Count) { [math]::Round(($cpuMax | Measure-Object -Maximum).Maximum,2) } else { $null })
            uso_medio_pct = $(if ($cpuCarga.Count) { [math]::Round(($cpuCarga | Measure-Object -Average).Average,2) } else { $null })
            uso_max_pct = $(if ($cpuCarga.Count) { [math]::Round(($cpuCarga | Measure-Object -Maximum).Maximum,2) } else { $null })
        }
    }

    $resultado.memoria = [ordered]@{
        uso_pct = (Get-Medida $leituras 'Memory' 'Load' @('Memory'))
        disponivel_gb = (Get-Medida $leituras 'Memory' 'Data' @('Memory Available'))
    }
    $resultado.gpu = [ordered]@{
        temperatura_c = (Get-Medida $leituras 'Gpu' 'Temperature' @('GPU Core','GPU Temperature','GPU Hot Spot'))
        uso_pct = (Get-Medida $leituras 'Gpu' 'Load' @('GPU Core','D3D 3D'))
    }
    $tmae = Get-Medida $leituras 'SuperIO|Motherboard' 'Temperature' @('System','Motherboard','Mainboard')
    $resultado.placa_mae = [ordered]@{temperatura_c=$tmae}

    $discos = [System.Collections.Generic.List[object]]::new()
    $gruposDisco = $leituras | Where-Object { $_.categoria -match 'Storage' } | Group-Object hardware
    foreach ($grupo in $gruposDisco) {
        $d = $grupo.Group
        $discos.Add([ordered]@{
            nome = $grupo.Name
            temperatura_c = (Get-Medida $d 'Storage' 'Temperature' @('Temperature','Temperature 1','Drive Temperature'))
            vida_util_pct = (Get-Medida $d 'Storage' 'Level' @('Life','Life Level','Remaining Life','Percentage Used Remaining'))
            horas_ligado = (Get-Medida $d 'Storage' 'Factor' @('Power On Hours'))
            ciclos_energia = (Get-Medida $d 'Storage' 'Factor' @('Power On Count'))
        })
    }
    $resultado.discos = @($discos.ToArray())

    # A coleta de ventoinhas ignora conectores com 0 RPM: zero nao prova defeito.
    $fans = $leituras | Where-Object { $_.tipo -eq 'Fan' -and $_.valor -gt 0 }
    $resultado.ventoinhas = @($fans | ForEach-Object {
        [ordered]@{controlador=$_.hardware; sensor=$_.sensor; rpm=[math]::Round($_.valor,0)}
    })
    $resultado.status = 'ok'
} catch {
    $avisos.Add("Hardware: $($_.Exception.Message)")
} finally {
    if ($null -ne $computer) { try { $computer.Close() } catch {} }
}

# Fallback experimental Dell SMM, somente leitura.
# Somente executado depois de fechar a instancia LibreHardwareMonitor.
# O driver e seus arquivos devem estar previamente instalados no laboratorio.
# Nao distribui, instala, desativa protecoes nem altera o controle da ventoinha.
if (-not $SemDellSMM -and @($resultado.ventoinhas).Count -eq 0) {
    try {
        $sistemaDell = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $fabricanteDell = ([string]$sistemaDell.Manufacturer -match '(?i)dell')
        $portatilDell = ($sistemaDell.PCSystemType -eq 2)

        if ($fabricanteDell -and -not $portatilDell) {
            $gabinetesDell = @(Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue)
            foreach ($gabineteDell in $gabinetesDell) {
                if (@($gabineteDell.ChassisTypes | Where-Object {
                    $_ -in @(8,9,10,11,12,14,18,21,30,31,32)
                }).Count -gt 0) {
                    $portatilDell = $true
                    break
                }
            }
        }

        if ($fabricanteDell -and $portatilDell) {
            $pastaDell = Join-Path $PastaMonitor 'DellFanCmd'
            $exeDell = Join-Path $pastaDell 'DellFanCmd.exe'
            $dllDell = Join-Path $pastaDell 'DellFanLib.dll'
            $driverDell = Join-Path $pastaDell 'bzh_dell_smm_io_x64.sys'

            if (-not ((Test-Path -LiteralPath $exeDell -PathType Leaf) -and
                       (Test-Path -LiteralPath $dllDell -PathType Leaf) -and
                       (Test-Path -LiteralPath $driverDell -PathType Leaf))) {
                $avisos.Add('Dell SMM: arquivos ausentes; RPM indisponivel.')
            } else {
                $assinaturaDell = Get-AuthenticodeSignature -LiteralPath $driverDell -ErrorAction Stop
                if ($assinaturaDell.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
                    $avisos.Add("Dell SMM: assinatura do driver nao validada ($($assinaturaDell.Status)).")
                } else {
                    $processoDell = $null
                    try {
                        $inicioDell = [System.Diagnostics.ProcessStartInfo]::new()
                        $inicioDell.FileName = $exeDell
                        $inicioDell.Arguments = 'rpm-fan1'
                        $inicioDell.WorkingDirectory = $pastaDell
                        $inicioDell.UseShellExecute = $false
                        $inicioDell.CreateNoWindow = $true

                        $processoDell = [System.Diagnostics.Process]::Start($inicioDell)
                        if ($null -eq $processoDell) { throw 'Nao foi possivel iniciar DellFanCmd.' }

                        if (-not $processoDell.WaitForExit(8000)) {
                            try { $processoDell.Kill($true) } catch {}
                            $avisos.Add('Dell SMM: tempo limite de 8 segundos excedido; RPM indisponivel.')
                        } else {
                            # DellFanCmd 2.1.1 retorna a leitura de RPM no exit code.
                            $rpmDell = [int]$processoDell.ExitCode
                            if ($rpmDell -ge 100 -and $rpmDell -le 15000) {
                                $resultado.ventoinhas = @(
                                    [ordered]@{ controlador='Dell SMM'; sensor='CPU Fan'; rpm=$rpmDell }
                                )
                            } else {
                                $avisos.Add("Dell SMM: leitura RPM indisponivel (codigo $rpmDell).")
                            }
                        }
                    } finally {
                        if ($null -ne $processoDell) { $processoDell.Dispose() }
                    }
                }
            }
        }
    } catch {
        $avisos.Add("Dell SMM: falha no fallback: $($_.Exception.Message)")
    }
}

$resultado.avisos = @($avisos.ToArray())
if ($resultado.status -eq 'ok' -and $avisos.Count -gt 0) { $resultado.status = 'parcial' }

# Retorna objeto em memoria para o transmissor oficial do Guardian.
# Nenhum arquivo telemetria-teste.json e criado.
[pscustomobject]$resultado
