# GUARDIAN 2026-11-06: identidade do usuario interativo, independente da elevacao.
# Nao substitui os campos legados "Usuario Adm" e "Login ID".
function Get-GuardianInteractiveIdentity {
    $resultado = [ordered]@{
        'Usuário Logado'       = 'Não identificado'
        'Tipo de Conta'        = 'Não identificado'
        'Permissão do Usuário' = 'Não identificado'
        'Guardian Elevado'     = 'Não identificado'
        'Conta de Execução'    = 'Não identificado'
    }

    try {
        $atual = [Security.Principal.WindowsIdentity]::GetCurrent()
        $resultado['Conta de Execução'] = $atual.Name
        $principal = [Security.Principal.WindowsPrincipal]::new($atual)
        $resultado['Guardian Elevado'] = if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -or
            $atual.User.Value -eq 'S-1-5-18') { 'Sim' } else { 'Não' }
    } catch {}

    try {
        # Lemos o token da sessao do usuario (nao o token do Guardian).
        # WTSQueryUserToken funciona como SYSTEM; OpenProcessToken e a alternativa
        # para o Guardian elevado por outra conta administrativa (ElevaGuardian).
        if (-not ('GuardianInteractiveTokenV1' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Security.Principal;
public static class GuardianInteractiveTokenV1 {
    [DllImport("wtsapi32.dll", SetLastError=true)]
    public static extern bool WTSQueryUserToken(uint sessionId, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool OpenProcessToken(IntPtr processHandle, uint desiredAccess, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError=true)]
    private static extern bool GetTokenInformation(IntPtr token, int infoClass, IntPtr buffer, int length, out int needed);
    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr handle);
    [StructLayout(LayoutKind.Sequential)]
    private struct SidAndAttributes { public IntPtr Sid; public uint Attributes; }
    [StructLayout(LayoutKind.Sequential)]
    private struct TokenGroups { public uint Count; public SidAndAttributes First; }
    public static bool HasAdministratorsSid(IntPtr token) {
        int needed;
        GetTokenInformation(token, 2, IntPtr.Zero, 0, out needed); // TokenGroups
        if (needed <= 0) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        IntPtr buffer = Marshal.AllocHGlobal(needed);
        try {
            if (!GetTokenInformation(token, 2, buffer, needed, out needed))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            uint count = (uint)Marshal.ReadInt32(buffer);
            long offset = Marshal.OffsetOf(typeof(TokenGroups), "First").ToInt64();
            int stride = Marshal.SizeOf(typeof(SidAndAttributes));
            for (uint i=0; i<count; i++) {
                IntPtr entry = IntPtr.Add(buffer, checked((int)(offset + (long)i*stride)));
                IntPtr sidPtr = Marshal.ReadIntPtr(entry);
                if (sidPtr != IntPtr.Zero && new SecurityIdentifier(sidPtr).IsWellKnown(WellKnownSidType.BuiltinAdministratorsSid))
                    return true; // inclui administradores com SID deny-only por UAC
            }
            return false;
        } finally { Marshal.FreeHGlobal(buffer); }
    }
}
'@ -ErrorAction Stop
        }

        $usuarioConsole = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
        $candidatos = @()
        foreach ($p in @(Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
            $token = [IntPtr]::Zero
            $identidade = $null
            try {
                if ($resultado['Conta de Execução'] -eq 'NT AUTHORITY\SYSTEM') {
                    [void][GuardianInteractiveTokenV1]::WTSQueryUserToken([uint32]$p.SessionId, [ref]$token)
                }
                if ($token -eq [IntPtr]::Zero) {
                    [void][GuardianInteractiveTokenV1]::OpenProcessToken($p.Handle, 0x0008, [ref]$token)
                }
                if ($token -eq [IntPtr]::Zero) { continue }
                $identidade = [Security.Principal.WindowsIdentity]::new($token)
                if (-not $identidade.User -or $identidade.User.Value -eq 'S-1-5-18') { continue }
                $candidatos += [pscustomobject]@{
                    Nome       = $identidade.Name
                    Sid        = $identidade.User.Value
                    Sessao     = $p.SessionId
                    Admin      = [GuardianInteractiveTokenV1]::HasAdministratorsSid($token)
                }
            } catch {
                # Falha isolada da sessao: nunca atribuir permissao por suposicao.
            } finally {
                if ($identidade) { $identidade.Dispose() }
                if ($token -ne [IntPtr]::Zero) { [void][GuardianInteractiveTokenV1]::CloseHandle($token) }
            }
        }

        # Se ha varias sessoes, dar preferencia ao usuario que o Windows
        # identifica no console. Nao escolher uma sessao arbitrariamente.
        $selecionados = @($candidatos | Where-Object { $usuarioConsole -and $_.Nome -ieq $usuarioConsole } |
            Sort-Object Sid -Unique)
        if ($selecionados.Count -eq 0) {
            $selecionados = @($candidatos | Sort-Object Sid -Unique)
        }
        if ($selecionados.Count -ne 1) {
            if ($usuarioConsole) { $resultado['Usuário Logado'] = $usuarioConsole }
            return [pscustomobject]$resultado
        }

        $selecionado = $selecionados[0]
        $resultado['Usuário Logado'] = $selecionado.Nome
        $resultado['Permissão do Usuário'] = if ($selecionado.Admin) { 'Administrador' } else { 'Restrito' }

        # Tipo de conta: somente classificar quando a origem for demonstravel.
        $sid = $selecionado.Sid
        if ($sid -match '^S-1-12-1-') {
            $resultado['Tipo de Conta'] = 'Microsoft Entra ID'
        } elseif ($selecionado.Nome -match '^AzureAD\\') {
            $resultado['Tipo de Conta'] = 'Microsoft Entra ID'
        } else {
            $local = Get-LocalUser -SID ([Security.Principal.SecurityIdentifier]::new($sid)) -ErrorAction SilentlyContinue
            if ($local) {
                $origem = [string]$local.PrincipalSource
                $resultado['Tipo de Conta'] = switch ($origem) {
                    'MicrosoftAccount' { 'Microsoft'; break }
                    'Local'            { 'Local'; break }
                    'ActiveDirectory'  { 'Active Directory'; break }
                    'AzureAD'          { 'Microsoft Entra ID'; break }
                    default            { 'Não identificado' }
                }
            } elseif ($selecionado.Nome -match '^MicrosoftAccount\\') {
                $resultado['Tipo de Conta'] = 'Microsoft'
            } elseif ($selecionado.Nome -match '^([^\\]+)\\' -and $matches[1] -ine $env:COMPUTERNAME -and
                      $matches[1] -ine 'NT AUTHORITY') {
                # Nao confundir nomes de dominio com prova de AD.
                $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
                if ($cs.PartOfDomain -and $cs.Domain -ieq $matches[1]) {
                    $resultado['Tipo de Conta'] = 'Active Directory'
                }
            }
        }
    } catch {
        # A coleta de identidade nao pode impedir a vistoria.
    }
    return [pscustomobject]$resultado
}

# Coleta informações do inventário de software hardware, com alertas de espaço em disco C: e Saúde do SSD
function Get-SystemInventory {
    # Fallback de log para ambientes que não tenham Write-Log
    if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
        function Write-Log { param([string]$Message) }
    }

    #Write-Host "Iniciando coleta de informações do inventário de Hardware e Software..." -ForegroundColor Cyan
    #Write-Host ""

    try {
        # 1. Cache de instâncias CIM com validação individual
        $cimOS   = Get-CimInstance -Class Win32_OperatingSystem -ErrorAction SilentlyContinue
        $cimCS   = Get-CimInstance -Class Win32_ComputerSystem     -ErrorAction SilentlyContinue
        $cimBios = Get-CimInstance -Class Win32_BIOS               -ErrorAction SilentlyContinue
        $cimBase = Get-CimInstance -Class Win32_BaseBoard          -ErrorAction SilentlyContinue
        $cimProc = Get-CimInstance -Class Win32_Processor          -ErrorAction SilentlyContinue

        # 2. Identificação da Placa-Mãe
        $placaMaeCompleta = if ($null -ne $cimBase) { "$($cimBase.Manufacturer) $($cimBase.Product)" } else { "Informação Indisponível" }

        # 3. Serial Number Fallback
        $serialFinal = if ($null -ne $cimBios) { $cimBios.SerialNumber } else { "" }
        $seriaisGenericos = @("System Serial Number", "To be filled by O.E.M.", "Default string", "00000000", "None", "")
        if ($seriaisGenericos -contains $serialFinal -or [string]::IsNullOrWhiteSpace($serialFinal)) {
            $serialFinal = if ($null -ne $cimBase) { $cimBase.SerialNumber } else { "Não Identificado" }
        }

        # 4. Identidade e Usuário (corrigido para evitar regex)
        $loginID = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $displayName = $null
        $msaEmail = $null

        # 4.1 UPN/e-mail via whoami (cobre MicrosoftAccount e AzureAD)
        try {
            $upn = (whoami /upn) 2>$null
            if ($upn -and $upn -match '@') { $msaEmail = $upn.Trim() }
        } catch {}

        # 4.2 Registry (MSA): StoredIdentities -> DisplayName/FriendlyName e e-mail
        try {
            $storedIdentities = "HKCU:\Software\Microsoft\IdentityCRL\StoredIdentities"
            if (Test-Path $storedIdentities) {
                $idKeys = Get-ChildItem -Path $storedIdentities -ErrorAction SilentlyContinue
                foreach ($k in $idKeys) {
                    $props = Get-ItemProperty -Path $k.PSPath -ErrorAction SilentlyContinue
                    if (-not $msaEmail -and $k.PSChildName -match '@') { $msaEmail = $k.PSChildName }
                    if (-not $displayName -and $props.DisplayName)  { $displayName = $props.DisplayName }
                    if (-not $displayName -and $props.FriendlyName) { $displayName = $props.FriendlyName }
                }
            }
        } catch {}

        # 4.3 Registry (MSA): UserExtendedProperties -> tentar DisplayName e e-mail
        try {
            $regUEP = "HKCU:\Software\Microsoft\IdentityCRL\UserExtendedProperties"
            if (Test-Path $regUEP) {
                $first = (Get-ChildItem -Path $regUEP -ErrorAction SilentlyContinue | Select-Object -First 1)
                if ($first) {
                    if (-not $msaEmail -and $first.PSChildName -match '@') { $msaEmail = $first.PSChildName }
                    $uepProps = Get-ItemProperty -Path $first.PSPath -ErrorAction SilentlyContinue
                    if (-not $displayName -and $uepProps.DisplayName) { $displayName = $uepProps.DisplayName }
                }
            }
        } catch {}

        # 4.4 Fallbacks para contas locais e último recurso (sem regex)
        if (-not $displayName) {
            try {
                $local = Get-LocalUser -Name $env:USERNAME -ErrorAction SilentlyContinue
                if ($local -and $local.FullName) { $displayName = $local.FullName }
            } catch {}
        }
        if (-not $displayName) {
            if ($loginID) {
                $lastSlash = $loginID.LastIndexOf('\')
                if ($lastSlash -ge 0 -and $lastSlash -lt ($loginID.Length - 1)) {
                    $displayName = $loginID.Substring($lastSlash + 1)
                } else {
                    $displayName = $loginID
                }
            } else {
                $displayName = $env:USERNAME
            }
        }

        $usuarioFormatado = if ($displayName -and $msaEmail) { "$displayName ($msaEmail)" } elseif ($displayName) { "$displayName [$loginID]" } else { $loginID }

        # 5. Uptime
        $uptimeFormatado = "N/A"
        if ($null -ne $cimOS -and $null -ne $cimOS.LastBootUpTime) {
            $tempoLigado = (Get-Date) - $cimOS.LastBootUpTime
            $uptimeFormatado = "$($tempoLigado.Days)d $($tempoLigado.Hours)h $($tempoLigado.Minutes)m"
        }

        # 6. Hardware e Rede
        $cpu = if ($null -ne $cimProc) { ($cimProc | Select-Object -First 1).Name -replace '\s+', ' ' } else { "N/A" }
        $ram = if ($null -ne $cimCS -and $null -ne $cimCS.TotalPhysicalMemory) { "$([Math]::Round($cimCS.TotalPhysicalMemory / 1GB)) GB" } else { "N/A" }
        $gpus = (Get-CimInstance -Class Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) -join ", "

        $ip = "N/A"; $mac = "N/A"
        $rede = Get-CimInstance -Class Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPEnabled -eq $true } | Select-Object -First 1
        if ($null -ne $rede) {
            if ($rede.IPAddress -and $rede.IPAddress.Count -gt 0) { $ip = $rede.IPAddress[0] }
            if ($rede.MACAddress) { $mac = $rede.MACAddress }
        }

        # --- CONTROLES PARA ITENS NÃO RECONHECIDOS E SMART ---
        $itensNaoReconhecidos = @()
        $smartFalhou = $false

        # 7. Discos e SMART
        $unidadesLogicas = @()
        try {
            $unidadesLogicas = Get-CimInstance -Class Win32_LogicalDisk -Filter "DriveType = 3" -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Size -gt 0) {
                    $total = [math]::Round($_.Size / 1GB, 2)
                    $livre = if ($_.Size -gt 0) { [math]::Round(($_.FreeSpace / $_.Size) * 100, 2) } else { 0 }
                    "$($_.DeviceID) ($($_.VolumeName)) com $total GB ($livre% livres)"
                }
            }
        } catch {}

        # Alerta de Espaço Crítico no Disco C:
        $alertaEspacoC = $null
        $discoC = Get-CimInstance -Class Win32_LogicalDisk -Filter "DriveType = 3" -ErrorAction SilentlyContinue | Where-Object { $_.DeviceID -eq 'C:' }
        if ($null -ne $discoC -and $discoC.FreeSpace -lt 20GB) {
            $alertaEspacoC = "!!! ATENÇÃO: ESPAÇO CRÍTICO NO DISCO C: ($([math]::Round($discoC.FreeSpace / 1GB, 2)) GB RESTANTES) !!!"
        }

        $saudeDiscos = @()
        $alertasSSD = @()
        try {
            $physicalDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.BusType -ne "USB" }
            $rawSmartData  = Get-CimInstance -Namespace "root\wmi" -ClassName MSStorageDriver_ATASmartData -ErrorAction SilentlyContinue
            $failPredict   = Get-CimInstance -Namespace "root\wmi" -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue

            foreach ($disk in $physicalDisks) {
                $friendlyName = $disk.FriendlyName
                $deviceId = $disk.DeviceId
                $vidaExibicao = "N/A"

                # Leitura bruta de firmware (sem wildcard/regex): contains case-insensitive
                $diskRaw = $null
                if ($rawSmartData) {
                    $diskRaw = $rawSmartData | Where-Object {
                        $_.InstanceName -and $deviceId -and ($_.InstanceName.IndexOf($deviceId, [StringComparison]::OrdinalIgnoreCase) -ge 0)
                    } | Select-Object -First 1
                }

                if ($null -ne $diskRaw) {
                    $bytes = $diskRaw.VendorSpecific
                    for ($i = 2; $i -le 500; $i += 12) {
                        if ($bytes[$i] -eq 177 -or $bytes[$i] -eq 231) {
                            $vidaExibicao = "$($bytes[$i+5])%"
                            break
                        }
                    }
                }

                # Fallback de Vida Útil
                if ($vidaExibicao -eq "N/A") {
                    $stats = $disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
                    if ($null -ne $stats -and $null -ne $stats.Wear) {
                        $vidaExibicao = "$([math]::Max(0, 100 - $stats.Wear))%"
                    }
                }

                # Tradução de Status
                $statusBruto = $disk.HealthStatus
                $statusTraduzido = switch ($statusBruto) {
                    "Healthy"   { "Saudável" }
                    "Warning"   { "Atenção" }
                    "Unhealthy" { "Crítico" }
                    Default     { $statusBruto }
                }

                # Verificação de Falha Preditiva (sem wildcard/regex)
                $predictiveFailure = $null
                if ($failPredict) {
                    $predictiveFailure = $failPredict | Where-Object {
                        $_.InstanceName -and $deviceId -and ($_.InstanceName.IndexOf($deviceId, [StringComparison]::OrdinalIgnoreCase) -ge 0)
                    } | Select-Object -First 1
                }
                if ($null -ne $predictiveFailure -and $predictiveFailure.PredictFailure) {
                    $statusTraduzido = if ($statusBruto -eq "Healthy") { "Atenção, verificar manualmente com o CrystalDiskInfo" } else { "CRÍTICO (Falha Preditiva)" }
                }

                if ($statusTraduzido -like "*Atenção*") {
                    $alertasSSD += "!!! ATENÇÃO: DISCO [$friendlyName] (Status: $statusTraduzido)!"
                }

                # SAÍDA AJUSTADA: apenas Status, sem "Vida"
                $saudeDiscos += "$friendlyName -> Status: $statusTraduzido"
            }
        } catch {
            $smartFalhou = $true
            Write-Log ("Telemetria/SMART: {0}" -f $_)
        }

        # Monta string da Saúde dos Discos
        $saudeDiscosStr = ""
        if (-not $smartFalhou -and $saudeDiscos -and $saudeDiscos.Count -gt 0) {
            $saudeDiscosStr = ($saudeDiscos -join "`n")
        } else {
            $itensNaoReconhecidos += "SSD"
        }

        # 8. Softwares Instalados (AJUSTADO: coleta por RegistryView 32/64 em HKLM e HKCU)
        function Get-RegUninstallNames([Microsoft.Win32.RegistryHive]$hive,[Microsoft.Win32.RegistryView]$view){
            $names = New-Object System.Collections.Generic.List[string]
            try{
                $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey($hive,$view)
                foreach($subPath in @('Software\Microsoft\Windows\CurrentVersion\Uninstall','Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')){
                    try{
                        $key=$base.OpenSubKey($subPath)
                        if($key){
                            foreach($sub in $key.GetSubKeyNames()){
                                try{
                                    $sk=$key.OpenSubKey($sub)
                                    if($sk){
                                        $dn=$sk.GetValue('DisplayName')
                                        $sys=$sk.GetValue('SystemComponent')
                                        $releaseType=$sk.GetValue('ReleaseType')
                                        $parent=$sk.GetValue('ParentKeyName')
                                        if($dn -and -not $sys -and -not $parent -and ($releaseType -ne 'Update')){
                                            # Remove NUL e caracteres de controle invalidos para o PostgreSQL.
                                            $nomeLimpo = ([string]$dn).Replace([string][char]0, '').Trim()
                                            if (-not [string]::IsNullOrWhiteSpace($nomeLimpo)) {
                                                [void]$names.Add($nomeLimpo)
                                            }
                                        }
                                    }
                                } catch {}
                            }
                        }
                    } catch {}
                }
            } catch {}
            return $names
        }

        $listaSoftwares = @()
        $listaSoftwares += Get-RegUninstallNames ([Microsoft.Win32.RegistryHive]::LocalMachine) ([Microsoft.Win32.RegistryView]::Registry64)
        $listaSoftwares += Get-RegUninstallNames ([Microsoft.Win32.RegistryHive]::LocalMachine) ([Microsoft.Win32.RegistryView]::Registry32)
        $listaSoftwares += Get-RegUninstallNames ([Microsoft.Win32.RegistryHive]::CurrentUser)  ([Microsoft.Win32.RegistryView]::Registry64)
        $listaSoftwares += Get-RegUninstallNames ([Microsoft.Win32.RegistryHive]::CurrentUser)  ([Microsoft.Win32.RegistryView]::Registry32)

        $softwaresFinais = $listaSoftwares | Where-Object { $_ } | Sort-Object -Unique

        # Coleta independente do usuario interativo (sem modificar identidade legada).
        $guardianIdentidade = Get-GuardianInteractiveIdentity

        # 9. Montagem do Objeto (com null-safe)
        $soCaption = if ($cimOS) { $cimOS.Caption } else { "N/A" }
        $fabMod = if ($cimCS) { "$($cimCS.Manufacturer) $($cimCS.Model)" } else { "N/A" }

        $Criar_Inventario_Sistema = [PSCustomObject]@{
            "Nome do Computador"        = $env:COMPUTERNAME
            "Usuário Adm"               = $usuarioFormatado
            "Login ID"                  = $loginID
            "Usuário Logado"             = $guardianIdentidade.'Usuário Logado'
            "Tipo de Conta"              = $guardianIdentidade.'Tipo de Conta'
            "Permissão do Usuário"        = $guardianIdentidade.'Permissão do Usuário'
            "Guardian Elevado"           = $guardianIdentidade.'Guardian Elevado'
            "Conta de Execução"          = $guardianIdentidade.'Conta de Execução'
            "Sistema Operacional"       = $soCaption
            "Processador (CPU)"         = $cpu
            "Placa-Mãe"                 = $placaMaeCompleta
            "Fabricante e Modelo PC"    = $fabMod
            "Serial Number"             = $serialFinal
            "Memória RAM Total"         = $ram
            "Placas de Vídeo"           = $gpus
            "Armazenamento"             = $saudeDiscosStr
            "Partições"                 = ($unidadesLogicas -join "`n")
            "Endereço IP"               = $ip
            "Endereço MAC"              = $mac
            "Softwares Instalados"      = ($softwaresFinais -join "`n")
        }

        # 10. Exibição e Log (Dual Output)
        #Write-Host "Informações do Inventário" -ForegroundColor Green
        $Criar_Inventario_Sistema | Format-List

        Write-Log "Informações do Inventário"
        $Criar_Inventario_Sistema | Format-List | Out-String | ForEach-Object { Write-Log $_ }

        if ($alertaEspacoC) {
            Write-Host $alertaEspacoC -ForegroundColor White -BackgroundColor Red
            Write-Log $alertaEspacoC
        }

        foreach ($alerta in $alertasSSD) {
            Write-Host $alerta -ForegroundColor White -BackgroundColor DarkBlue
            Write-Log $alerta
        }

        if ($itensNaoReconhecidos.Count -gt 0) {
            $msgResumo = "Atenção: não foi possível reconhecer: $( $itensNaoReconhecidos -join ', ' )"
            Write-Host $msgResumo -ForegroundColor White
            Write-Log $msgResumo
        }

        #Write-Host ""
        #Write-Host "Coleta concluída com Sucesso!" -ForegroundColor Green

    } catch {
        $msgErro = "ERRO CRÍTICO: $_"
        Write-Host $msgErro -ForegroundColor Red
        Write-Log $msgErro
    }
}