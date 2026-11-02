#Requires -Version 7.0
<#
Guardian 360 - telemetria isolada (fase de laboratorio)
Destino sugerido: C:\Guardian\Functions\Get-HardwareTelemetry.ps1
Bibliotecas: C:\Guardian\Monitor\*.dll
Saida local: C:\Guardian\Monitor\telemetria-teste.json
Nao altera Guardian.ps1, tarefas, API ou banco de dados.
Instala PawnIO 2.2.0 silenciosamente apenas se ausente, mediante assinatura valida.
#>
[CmdletBinding()]
param(
    [switch]$SemInstalarPawnIO,
    [int]$DiasEventos = 35,
    [string]$PastaMonitor = 'C:\Guardian\Monitor'
)

$ErrorActionPreference = 'Stop'
$avisos = [System.Collections.Generic.List[string]]::new()
$versaoPawnIO = '2.2.0'
$saida = Join-Path $PastaMonitor 'telemetria-teste.json'

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

    $cpuTemp = @()
    $cpuCarga = @()
    foreach ($amostra in $amostras) {
        $temp = Get-Medida $amostra 'Cpu' 'Temperature' @('CPU Package','Core Average','Core Max')
        $carga = Get-Medida $amostra 'Cpu' 'Load' @('CPU Total')
        if ($null -ne $temp) { $cpuTemp += $temp }
        if ($null -ne $carga) { $cpuCarga += $carga }
    }
    $cpuHardware = $leituras | Where-Object categoria -match 'Cpu' | Select-Object -First 1
    if ($null -ne $cpuHardware) {
        $resultado.cpu = [ordered]@{
            nome = $cpuHardware.hardware
            temperatura_media_c = $(if ($cpuTemp.Count) { [math]::Round(($cpuTemp | Measure-Object -Average).Average,2) } else { $null })
            temperatura_max_c = $(if ($cpuTemp.Count) { [math]::Round(($cpuTemp | Measure-Object -Maximum).Maximum,2) } else { $null })
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

$resultado.avisos = @($avisos.ToArray())
if ($resultado.status -eq 'ok' -and $avisos.Count -gt 0) { $resultado.status = 'parcial' }

try {
    New-Item -ItemType Directory -Path $PastaMonitor -Force -ErrorAction Stop | Out-Null
    $temporario = Join-Path $PastaMonitor ('telemetria-teste.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $resultado | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $temporario -Encoding utf8 -ErrorAction Stop
        Move-Item -LiteralPath $temporario -Destination $saida -Force -ErrorAction Stop
    } finally {
        Remove-Item -LiteralPath $temporario -Force -ErrorAction SilentlyContinue
    }
    Write-Host "Telemetria salva em: $saida"
    Write-Host "Status: $($resultado.status); avisos: $($avisos.Count)"
} catch {
    Write-Warning "Nao foi possivel gravar telemetria local: $($_.Exception.Message)"
}
