#Requires -Version 7.0
<# Guardian 360 v2.0 - WPF de acompanhamento (processo independente)
   Nao executa manutencao; apenas observa eventos locais do Guardian.ps1.
   Nenhum LOG, JSON intermediario ou dependencia de API.
#>
param(
    [Parameter(Mandatory)][ValidateRange(1024,65535)][int]$Port,
    [string]$Cliente = 'Cliente nao informado',
    [string]$Computador = $env:COMPUTERNAME,
    [int]$EnginePid = 0,
    [switch]$Preview
)

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# A UI roda em outro pwsh.exe. Resolve o monitor do console do Guardian
# (EnginePid), inclusive quando o console e hospedado pelo Windows Terminal.
# Se a tarefa nao possuir console interativo, usa o monitor principal.
if (-not ('GuardianConsoleMonitor' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class GuardianConsoleMonitor {
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool FreeConsole();
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool AttachConsole(uint processId);
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int count);
}
'@
}

function Get-GuardianConsoleScreen {
    param([int]$EngineProcessId)
    $primary = [System.Windows.Forms.Screen]::PrimaryScreen
    if ($EngineProcessId -le 0) { return $primary }

    # 1. Janela visivel do proprio motor ou de um processo ancestral
    # (WindowsTerminal.exe, powershell.exe, conhost.exe etc.).
    $processId = $EngineProcessId
    for ($i = 0; $i -lt 5 -and $processId -gt 0; $i++) {
        try {
            $proc = [Diagnostics.Process]::GetProcessById($processId)
            $handle = $proc.MainWindowHandle
            if ($handle -ne [IntPtr]::Zero -and [GuardianConsoleMonitor]::IsWindowVisible($handle)) {
                return [System.Windows.Forms.Screen]::FromHandle($handle)
            }
            $cim = Get-CimInstance Win32_Process -Filter "ProcessId = $processId" -ErrorAction Stop
            $parentId = [int]$cim.ParentProcessId
            if ($parentId -le 0 -or $parentId -eq $processId) { break }
            $processId = $parentId
        } catch { break }
    }

    # 2. Console classico: o dono da janela e conhost.exe e o motor pode
    # nao possuir MainWindowHandle. A associacao e apenas temporaria.
    try {
        [void][GuardianConsoleMonitor]::FreeConsole()
        if ([GuardianConsoleMonitor]::AttachConsole([uint32]$EngineProcessId)) {
            try {
                $consoleHandle = [GuardianConsoleMonitor]::GetConsoleWindow()
                if ($consoleHandle -ne [IntPtr]::Zero -and [GuardianConsoleMonitor]::IsWindowVisible($consoleHandle)) {
                    return [System.Windows.Forms.Screen]::FromHandle($consoleHandle)
                }
            } finally { [void][GuardianConsoleMonitor]::FreeConsole() }
        }
    } catch { }

    # 3. Ao iniciar pela interface do Windows Terminal, o terminal pode
    # ser o primeiro plano e nao estar acessivel como processo ancestral.
    try {
        $foreground = [GuardianConsoleMonitor]::GetForegroundWindow()
        if ($foreground -ne [IntPtr]::Zero -and [GuardianConsoleMonitor]::IsWindowVisible($foreground)) {
            $title = [System.Text.StringBuilder]::new(260)
            [void][GuardianConsoleMonitor]::GetWindowText($foreground, $title, $title.Capacity)
            if ($title.ToString() -match '(?i)PowerShell|Windows Terminal|pwsh') {
                return [System.Windows.Forms.Screen]::FromHandle($foreground)
            }
        }
    } catch { }
    return $primary
}


function Get-GuardianBitmapImage {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $bitmap = [System.Windows.Media.Imaging.BitmapImage]::new()
        $bitmap.BeginInit()
        $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bitmap.UriSource = [Uri]::new($Path, [UriKind]::Absolute)
        $bitmap.EndInit()
        $bitmap.Freeze()
        return $bitmap
    } catch {
        return $null
    }
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" ResizeMode="CanMinimize"
        Width="1362" Height="768" MinWidth="560" MinHeight="390"
        Background="Transparent" Foreground="#F4F6F8" WindowStartupLocation="Manual"
        FontFamily="Segoe UI" Title="Guardian 360 v2.0" ShowInTaskbar="True">
  <Window.Resources>
    <!-- Barras de progresso com trilho e preenchimento arredondados. -->
    <Style TargetType="{x:Type ProgressBar}">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="{x:Type ProgressBar}">
            <Grid x:Name="PART_Track" Height="{TemplateBinding Height}" SnapsToDevicePixels="True">
              <Border Background="{TemplateBinding Background}" CornerRadius="3"/>
              <Border x:Name="PART_Indicator" Background="{TemplateBinding Foreground}" CornerRadius="3" HorizontalAlignment="Left"/>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border x:Name="RootSurface" BorderBrush="#29383E" BorderThickness="1" CornerRadius="12" Background="#000000">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="47"/>
        <RowDefinition Height="118"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="76"/>
      </Grid.RowDefinitions>

      <Border Grid.Row="0" Background="Transparent" BorderBrush="#263237" BorderThickness="0,0,0,1" CornerRadius="11,11,0,0">
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="44"/></Grid.ColumnDefinitions>
          <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="22,0,0,0">
            <TextBlock Text="●" FontSize="16" Foreground="#FF00FF00" Margin="0,0,10,0"/>
            <TextBlock Text="Guardian 360" FontSize="15" FontWeight="SemiBold" Foreground="#F4F6F8"/>
            <TextBlock Text="  v2.0" FontSize="12" Foreground="#7E9AA5" VerticalAlignment="Center"/>
          </StackPanel>
          <Button x:Name="MinButton" Grid.Column="1" Height="30" BorderThickness="0" Background="Transparent" Cursor="Hand" ToolTip="Minimizar">
            <Button.Template>
              <ControlTemplate TargetType="{x:Type Button}">
                <Border x:Name="MinSurface" Background="Transparent" CornerRadius="0,10,0,0" SnapsToDevicePixels="True">
                  <Grid>
                    <Path Data="M 0,0 L 9,0" Stroke="#D6E4EA" StrokeThickness="1" Width="9" Height="1" Stretch="None" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Grid>
                </Border>
                <ControlTemplate.Triggers>
                  <Trigger Property="IsMouseOver" Value="True">
                    <Setter TargetName="MinSurface" Property="Background" Value="#24343D"/>
                  </Trigger>
                  <Trigger Property="IsPressed" Value="True">
                    <Setter TargetName="MinSurface" Property="Background" Value="#1B2830"/>
                  </Trigger>
                </ControlTemplate.Triggers>
              </ControlTemplate>
            </Button.Template>
          </Button>
        </Grid>
      </Border>

      <!-- Área superior preservada; bg.png agora pertence ao fundo da janela inteira. -->
      <Border Grid.Row="1" Margin="34,8,34,8" Background="Transparent"/>

      <Grid Grid.Row="2" Margin="24,18,24,34">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="3*"/>
          <ColumnDefinition x:Name="RobotGapColumn" Width="20"/>
          <ColumnDefinition x:Name="RobotColumn" Width="220"/>
        </Grid.ColumnDefinitions>
        <Border x:Name="MainCard" Grid.Column="0" BorderBrush="#26363B" BorderThickness="1" CornerRadius="12" Background="#CC101719" Padding="24">
          <Border.RenderTransform><TranslateTransform Y="8"/></Border.RenderTransform>
          <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Focusable="False" Padding="0,0,12,0">
            <ScrollViewer.Resources>
              <Style TargetType="{x:Type ScrollBar}">
                <Setter Property="Width" Value="6"/>
                <Setter Property="Background" Value="#101719"/>
                <Setter Property="Template">
                  <Setter.Value>
                    <ControlTemplate TargetType="{x:Type ScrollBar}">
                      <Border Background="{TemplateBinding Background}" Width="6" HorizontalAlignment="Right" CornerRadius="3">
                        <Track x:Name="PART_Track" Width="6" IsDirectionReversed="True" Focusable="False">
                          <Track.DecreaseRepeatButton>
                            <RepeatButton Focusable="False" Opacity="0" Command="ScrollBar.PageUpCommand"/>
                          </Track.DecreaseRepeatButton>
                          <Track.Thumb>
                            <Thumb>
                              <Thumb.Template>
                                <ControlTemplate TargetType="{x:Type Thumb}">
                                  <Border x:Name="ThumbSurface" Background="#24343D" CornerRadius="3" Margin="1,1"/>
                                  <ControlTemplate.Triggers>
                                    <Trigger Property="IsMouseOver" Value="True">
                                      <Setter TargetName="ThumbSurface" Property="Background" Value="#324854"/>
                                    </Trigger>
                                    <Trigger Property="IsDragging" Value="True">
                                      <Setter TargetName="ThumbSurface" Property="Background" Value="#48616C"/>
                                    </Trigger>
                                  </ControlTemplate.Triggers>
                                </ControlTemplate>
                              </Thumb.Template>
                            </Thumb>
                          </Track.Thumb>
                          <Track.IncreaseRepeatButton>
                            <RepeatButton Focusable="False" Opacity="0" Command="ScrollBar.PageDownCommand"/>
                          </Track.IncreaseRepeatButton>
                        </Track>
                      </Border>
                    </ControlTemplate>
                  </Setter.Value>
                </Setter>
              </Style>
            </ScrollViewer.Resources>
            <StackPanel>
              <TextBlock x:Name="MainHeadline" Text="Estamos cuidando do seu computador." FontSize="22" FontWeight="SemiBold" Foreground="White" TextWrapping="Wrap"/>
              <TextBlock x:Name="MainDescription" Text="A manutenção é executada automaticamente. Você pode minimizar esta janela." TextWrapping="Wrap" Foreground="#AFC0C5" FontSize="14" Margin="0,10,0,26"/>
              <TextBlock x:Name="PhaseText" Text="Preparando manutenção preventiva..." FontSize="18" FontWeight="SemiBold" Foreground="#64D5EB" TextWrapping="Wrap" Margin="0,0,0,24"/>
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="94"/></Grid.ColumnDefinitions>
                <ProgressBar x:Name="MainProgress" Minimum="0" Maximum="100" Value="0" Height="8" Foreground="#8D99A0" Background="#283438" BorderThickness="0"/>
                <TextBlock x:Name="PercentText" Grid.Column="1" Text="0%" FontWeight="SemiBold" FontSize="30" Foreground="#FFFFFF" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,8,0"/>
              </Grid>
              <TextBlock x:Name="ActivityLabel" Text="ATIVIDADE ATUAL" Foreground="#77909A" FontSize="12" FontWeight="Bold" Margin="0,26,0,0"/>
              <TextBlock x:Name="ActivityText" Text="Inicializando o Guardian..." Foreground="#F2F5F6" FontSize="15" Margin="0,10,0,0" TextWrapping="Wrap"/>
              <StackPanel Margin="0,24,0,0">
                <Border Height="1" Background="#28383D" Margin="0,0,0,16"/>
                <TextBlock Text="INVENTÁRIO" FontSize="12" Foreground="#64D5EB" FontWeight="SemiBold" Margin="0,0,0,16"/>
                <Grid x:Name="InventoryPanel">
                  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="14"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                  <StackPanel Grid.Row="0" Grid.Column="0" Margin="0,0,0,24"><TextBlock Text="EMPRESA" FontSize="11" Foreground="#78939C" TextWrapping="Wrap"/><TextBlock x:Name="ClientText" Text="" FontSize="14" Foreground="#E8F0F2" TextWrapping="Wrap"/></StackPanel>
                  <StackPanel Grid.Row="0" Grid.Column="2" Margin="0,0,0,24"><TextBlock Text="COMPUTADOR" FontSize="11" Foreground="#78939C" TextWrapping="Wrap"/><TextBlock x:Name="PCText" Text="" FontSize="14" Foreground="#E8F0F2" TextWrapping="Wrap"/></StackPanel>
                  <StackPanel Grid.Row="1" Grid.Column="2" Margin="0,0,0,24"><TextBlock Text="SISTEMA OPERACIONAL E VERSÃO" FontSize="11" Foreground="#78939C" TextWrapping="Wrap"/><TextBlock x:Name="OsValue" Text="Aguardando inventário" FontSize="14" Foreground="#E8F0F2" TextWrapping="Wrap"/></StackPanel>
                  <StackPanel Grid.Row="1" Grid.Column="0" Margin="0,0,0,24"><TextBlock Text="FABRICANTE / MODELO" FontSize="11" Foreground="#78939C" TextWrapping="Wrap"/><TextBlock x:Name="ComputerModelValue" Text="—" FontSize="14" Foreground="#E8F0F2" TextWrapping="Wrap"/></StackPanel>

                  <StackPanel Grid.Row="2" Grid.Column="0" Margin="0,0,0,24"><TextBlock Text="PROCESSADOR" FontSize="11" Foreground="#78939C" TextWrapping="Wrap"/><TextBlock x:Name="CpuValue" Text="—" FontSize="14" Foreground="#E8F0F2" TextWrapping="Wrap"/></StackPanel>
                  <StackPanel Grid.Row="2" Grid.Column="2" Margin="0,0,0,24"><TextBlock Text="MEMÓRIA RAM" FontSize="11" Foreground="#78939C" TextWrapping="Wrap"/><TextBlock x:Name="RamValue" Text="—" FontSize="14" Foreground="#E8F0F2" TextWrapping="Wrap"/></StackPanel>
                  <StackPanel Grid.Row="3" Grid.Column="0" Margin="0,0,0,24"><TextBlock Text="PLACA DE VÍDEO" FontSize="11" Foreground="#78939C" TextWrapping="Wrap"/><TextBlock x:Name="GpuValue" Text="—" FontSize="14" Foreground="#E8F0F2" TextWrapping="Wrap"/></StackPanel>
                  <StackPanel Grid.Row="3" Grid.Column="2" Margin="0,0,0,24"><TextBlock Text="WINDOWS INSTALADO EM" FontSize="11" Foreground="#78939C" TextWrapping="Wrap"/><TextBlock x:Name="StorageValue" Text="—" FontSize="14" Foreground="#E8F0F2" TextWrapping="Wrap"/></StackPanel>
                </Grid>
              </StackPanel>
              <StackPanel x:Name="EventsPanel" Visibility="Collapsed" Margin="0,26,0,0">
                <Border Height="1" Background="#28383D" Margin="0,0,0,16"/>
                <TextBlock Text="EVENTOS CRÍTICOS NO WINDOWS" FontSize="12" Foreground="#64D5EB" FontWeight="SemiBold" Margin="0,0,0,16"/>
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="14"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                  <StackPanel Grid.Row="0" Grid.Column="0" Margin="0,0,0,26"><TextBlock Text="FALHAS DE HARDWARE (WHEA)" FontSize="11" Foreground="#78939C"/><TextBlock x:Name="WheaDescription" FontSize="12" Foreground="#B8C9CF" TextWrapping="Wrap" Margin="0,6,0,0"/><TextBlock x:Name="WheaValue" Margin="0,6,0,0" Text="Não disponível" Foreground="#E8F0F2" FontSize="14"/></StackPanel>
                  <StackPanel Grid.Row="0" Grid.Column="2" Margin="0,0,0,26"><TextBlock Text="TELAS AZUIS (BSOD)" FontSize="11" Foreground="#78939C"/><TextBlock x:Name="BsodDescription" FontSize="12" Foreground="#B8C9CF" TextWrapping="Wrap" Margin="0,6,0,0"/><TextBlock x:Name="BsodValue" Margin="0,6,0,0" Text="Não disponível" Foreground="#E8F0F2" FontSize="14"/></StackPanel>
                  <StackPanel Grid.Row="1" Grid.Column="0"><TextBlock Text="DESLIGAMENTOS INESPERADOS" FontSize="11" Foreground="#78939C" TextWrapping="Wrap"/><TextBlock x:Name="ShutdownDescription" FontSize="12" Foreground="#B8C9CF" TextWrapping="Wrap" Margin="0,6,0,0"/><TextBlock x:Name="ShutdownValue" Margin="0,6,0,0" Text="Não disponível" Foreground="#E8F0F2" FontSize="14"/></StackPanel>
                  <StackPanel Grid.Row="1" Grid.Column="2"><TextBlock Text="ERROS DE DISCO" FontSize="11" Foreground="#78939C"/><TextBlock x:Name="DiskEventsDescription" FontSize="12" Foreground="#B8C9CF" TextWrapping="Wrap" Margin="0,6,0,0"/><TextBlock x:Name="DiskEventsValue" Margin="0,6,0,0" Text="Não disponível" Foreground="#E8F0F2" FontSize="14"/></StackPanel>
                </Grid>
              </StackPanel>
              <StackPanel x:Name="DurationPanel" Visibility="Collapsed" Margin="0,26,0,0">
                <Border Height="1" Background="#28383D" Margin="0,0,0,16"/>
                <TextBlock Text="RESUMO DA VISTORIA" FontSize="12" Foreground="#64D5EB" FontWeight="SemiBold" Margin="0,0,0,16"/>
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="14"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0">
                  <TextBlock Text="TEMPO DE EXECUÇÃO" FontSize="11" Foreground="#78939C"/>
                  <TextBlock x:Name="DurationValue" Text="" FontSize="14" Foreground="#E8F0F2"/>
                </StackPanel>
                <StackPanel Grid.Column="2">
                  <TextBlock Text="ETAPA IGNORADA" FontSize="11" Foreground="#78939C"/>
                  <TextBlock x:Name="SkippedPhasesValue" Text="Nenhuma" FontSize="13" Foreground="#E8F0F2" TextWrapping="Wrap" Margin="0,4,0,0"/>
                </StackPanel>
                </Grid>
              </StackPanel>
              <StackPanel x:Name="ScoreBreakdownPanel" Visibility="Collapsed" Margin="0,24,0,0">
                <Border Height="1" Background="#28383D" Margin="0,0,0,16"/>
                <TextBlock Text="COMPOSIÇÃO DA SAÚDE GERAL" FontSize="12" Foreground="#64D5EB" FontWeight="SemiBold" Margin="0,0,0,18"/>
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                  <StackPanel x:Name="ScoreBreakdownRows" Grid.Column="0" Margin="0,0,12,0"/>
                </Grid>
              </StackPanel>
              <TextBlock x:Name="EndText" Text="" FontSize="14" Foreground="#FF00FF00" Margin="0,18,0,0" TextWrapping="Wrap"/>
              <StackPanel x:Name="HealthPanel" Visibility="Collapsed" Margin="0,22,0,0">
                <Border Height="1" Background="#28383D" Margin="0,0,0,16"/>
              <Grid Margin="0,0,0,0">
                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <StackPanel VerticalAlignment="Center"><TextBlock Text="SAÚDE GERAL DO SISTEMA" FontSize="12" Foreground="#78939C"/><TextBlock x:Name="HealthClass" Text="" FontSize="15" Foreground="#E8F0F2"/></StackPanel>
                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Bottom" HorizontalAlignment="Right" Margin="0,0,8,0">
                  <TextBlock Text="Nota:" Foreground="#B8C9CF" FontSize="17" FontWeight="SemiBold" VerticalAlignment="Bottom" Margin="0,0,8,4"/>
                  <TextBlock x:Name="HealthScore" Text="" Foreground="#61E3A7" FontSize="30" FontWeight="SemiBold" VerticalAlignment="Bottom"/>
                </StackPanel>
              </Grid>
              </StackPanel>

            </StackPanel>
          </ScrollViewer>
        </Border>

        <Grid x:Name="RobotPanel" Grid.Column="2" VerticalAlignment="Stretch" HorizontalAlignment="Stretch">
          <Border Background="Transparent" BorderBrush="Transparent" BorderThickness="0" Padding="0">
            <Viewbox Stretch="Uniform" HorizontalAlignment="Center" VerticalAlignment="Center">
              <Image x:Name="RobotImage" Width="220" Height="360" Stretch="Uniform" RenderOptions.BitmapScalingMode="HighQuality"/>
            </Viewbox>
          </Border>
        </Grid>
      </Grid>

      <Grid Grid.Row="3" Margin="34,0,34,4">
        <Grid.RowDefinitions><RowDefinition Height="42"/><RowDefinition Height="*"/></Grid.RowDefinitions>
        <Grid Grid.Row="0">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <Button x:Name="FinishButton" Grid.Column="1" Content="Concluir"
                  Width="126" Height="36" FontFamily="Segoe UI" FontSize="13" FontWeight="SemiBold"
                  Foreground="#FFFFFF" Background="#000000" BorderThickness="1" BorderBrush="#31444A"
                  HorizontalAlignment="Right" VerticalAlignment="Bottom" Visibility="Collapsed" Cursor="Hand" Margin="0,0,0,-6">
            <Button.Template>
              <ControlTemplate TargetType="{x:Type Button}">
                <Border x:Name="FinishSurface" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="10" SnapsToDevicePixels="True">
                  <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <ControlTemplate.Triggers>
                  <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="FinishSurface" Property="Background" Value="#1A2529"/></Trigger>
                  <Trigger Property="IsPressed" Value="True"><Setter TargetName="FinishSurface" Property="Background" Value="#25343A"/></Trigger>
                </ControlTemplate.Triggers>
              </ControlTemplate>
            </Button.Template>
          </Button>
        </Grid>

      </Grid>
    </Grid>
  </Border>
</Window>
'@

$baseDir = Split-Path -Parent $PSScriptRoot
$robotExecPath = Join-Path $baseDir 'Assets\Images\guardian_robot_execucao.png'
$robotFinalPath = Join-Path $baseDir 'Assets\Images\guardian_robot_final.png'
$robotWarningPath = Join-Path $baseDir 'Assets\Images\guardian_robot_ressalvas.png'
$robotErrorPath = Join-Path $baseDir 'Assets\Images\guardian_robot_critico.png'
$robotApiPath = Join-Path $baseDir 'Assets\Images\guardian_robot_api_pendente.png'
$backgroundPath = Join-Path $baseDir 'Assets\Images\bg.png'
$robotExecImage = Get-GuardianBitmapImage -Path $robotExecPath
$robotFinalImage = Get-GuardianBitmapImage -Path $robotFinalPath
$robotWarningImage = Get-GuardianBitmapImage -Path $robotWarningPath
$robotErrorImage = Get-GuardianBitmapImage -Path $robotErrorPath
$robotApiImage = Get-GuardianBitmapImage -Path $robotApiPath
# Imagens exclusivas de cada fase; carregadas uma vez e reutilizadas.
$script:GuardianPhaseRobotImages = @{}
$phaseRobotFiles = @{
    1 = 'guardian_robot_inventario.png'
    3 = 'guardian_robot_otimizacoes.png'
    4 = 'guardian_robot_limpeza.png'
    5 = 'guardian_robot_windows_update.png'
    6 = 'guardian_robot_winget.png'
    7 = 'guardian_robot_componentes.png'
    8 = 'guardian_robot_armazenamento.png'
    9 = 'guardian_robot_seguranca.png'
}
foreach ($phaseId in $phaseRobotFiles.Keys) {
    $script:GuardianPhaseRobotImages[$phaseId] = Get-GuardianBitmapImage -Path (Join-Path $baseDir ('Assets\Images\' + $phaseRobotFiles[$phaseId]))
}
$backgroundImage = Get-GuardianBitmapImage -Path $backgroundPath

# Centraliza no MESMO monitor do console do Guardian. Se nao houver
# console visivel, seleciona o monitor principal. Mantem as dimensoes da UI 29.
$guardianScreen = Get-GuardianConsoleScreen -EngineProcessId $EnginePid
$preferredWidth = 1362.0
$preferredHeight = 768.0

$xmlReader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($xmlReader)
# SourceInitialized fornece o HwndSource para converter pixels de monitor
# em unidades WPF (DIP), respeitando a escala de exibicao do Windows.
$window.Add_SourceInitialized({
    try {
        $source = [System.Windows.Interop.HwndSource]::FromVisual($window)
        $scaleX = $source.CompositionTarget.TransformFromDevice.M11
        $scaleY = $source.CompositionTarget.TransformFromDevice.M22
        $bounds = $guardianScreen.WorkingArea
        $areaLeft = $bounds.Left * $scaleX
        $areaTop = $bounds.Top * $scaleY
        $areaWidth = $bounds.Width * $scaleX
        $areaHeight = $bounds.Height * $scaleY
        $targetWidth = [Math]::Min($preferredWidth, [Math]::Max(440.0, $areaWidth - 32.0))
        $targetHeight = [Math]::Min($preferredHeight, [Math]::Max(360.0, $areaHeight - 32.0))
        $window.MinWidth = [Math]::Min(560.0, $targetWidth)
        $window.MinHeight = [Math]::Min(390.0, $targetHeight)
        $window.Width = $targetWidth
        $window.Height = $targetHeight
        $window.Left = $areaLeft + [Math]::Max(0, ($areaWidth - $targetWidth) / 2)
        $window.Top = $areaTop + [Math]::Max(0, ($areaHeight - $targetHeight) / 2)
    } catch {
        # Sem console/monitor valido, comportamento anterior: centralizar.
        $area = [System.Windows.SystemParameters]::WorkArea
        $window.Width = [Math]::Min($preferredWidth, [Math]::Max(440.0, $area.Width - 32.0))
        $window.Height = [Math]::Min($preferredHeight, [Math]::Max(360.0, $area.Height - 32.0))
        $window.Left = $area.Left + ($area.Width - $window.Width) / 2
        $window.Top = $area.Top + ($area.Height - $window.Height) / 2
    }
})

$phaseText = $window.FindName('PhaseText')
$activityText = $window.FindName('ActivityText')
$progress = $window.FindName('MainProgress')
$percentText = $window.FindName('PercentText')
$endText = $window.FindName('EndText')
$headline = $window.FindName('MainHeadline')
$description = $window.FindName('MainDescription')
$activityLabel = $window.FindName('ActivityLabel')
$inventoryPanel = $window.FindName('InventoryPanel')
$healthPanel = $window.FindName('HealthPanel')
$computerModelValue = $window.FindName('ComputerModelValue')
$cpuValue = $window.FindName('CpuValue')
$ramValue = $window.FindName('RamValue')
$gpuValue = $window.FindName('GpuValue')
$storageValue = $window.FindName('StorageValue')
$healthScore = $window.FindName('HealthScore')
$healthClass = $window.FindName('HealthClass')
$scoreBreakdownPanel = $window.FindName('ScoreBreakdownPanel')
$scoreBreakdownRows = $window.FindName('ScoreBreakdownRows')
$osValue = $window.FindName('OsValue')
$eventsPanel = $window.FindName('EventsPanel')
$wheaValue = $window.FindName('WheaValue')
$bsodValue = $window.FindName('BsodValue')
$shutdownValue = $window.FindName('ShutdownValue')
$diskEventsValue = $window.FindName('DiskEventsValue')
$wheaDescription = $window.FindName('WheaDescription')
$bsodDescription = $window.FindName('BsodDescription')
$shutdownDescription = $window.FindName('ShutdownDescription')
$diskEventsDescription = $window.FindName('DiskEventsDescription')
$durationPanel = $window.FindName('DurationPanel')
$durationValue = $window.FindName('DurationValue')
$skippedPhasesValue = $window.FindName('SkippedPhasesValue')
# Rotulos dos IDs validos do PulaFases (Fase 2 pertence ao Guardian Ghost).
$script:GuardianSkippedPhaseTitles = @{
    3 = 'Otimizações Estruturais'
    4 = 'Limpezas do Windows'
    5 = 'Atualizações do Windows'
    6 = 'Atualizações de aplicativos via Winget'
    7 = 'Pós-atualização / Componentes'
    8 = 'Otimização de Armazenamento'
    9 = 'Segurança'
}
$robotGapColumn = $window.FindName('RobotGapColumn')
$robotColumn = $window.FindName('RobotColumn')

$finishButton = $window.FindName('FinishButton')
$minButton = $window.FindName('MinButton')
$robotPanel = $window.FindName('RobotPanel')
$robotImage = $window.FindName('RobotImage')
# bg.png como fundo da janela inteira (1362 x 768 unidades WPF).
# O Border principal preserva os cantos arredondados.
# Sem imagem, o fundo preto original e mantido.
if ($backgroundImage) {
    $rootSurface = $window.FindName('RootSurface')
    $fullBackground = [System.Windows.Media.ImageBrush]::new($backgroundImage)
    $fullBackground.Stretch = [System.Windows.Media.Stretch]::Fill
    $fullBackground.AlignmentX = [System.Windows.Media.AlignmentX]::Center
    $fullBackground.AlignmentY = [System.Windows.Media.AlignmentY]::Center
    $rootSurface.Background = $fullBackground
}
$window.FindName('ClientText').Text = "$Cliente"
$window.FindName('PCText').Text = "$Computador"

function Set-GuardianRobotState {
    param([ValidateSet('exec','success','warning','error','api')][string]$State)
    switch ($State) {
        'exec'    { $img = if ($robotExecImage) { $robotExecImage } elseif ($robotFinalImage) { $robotFinalImage } else { $null } }
        'success' { $img = if ($robotFinalImage) { $robotFinalImage } elseif ($robotExecImage) { $robotExecImage } else { $null } }
        'warning' { $img = if ($robotWarningImage) { $robotWarningImage } elseif ($robotFinalImage) { $robotFinalImage } elseif ($robotExecImage) { $robotExecImage } else { $null } }
        'error'   { $img = if ($robotErrorImage) { $robotErrorImage } elseif ($robotWarningImage) { $robotWarningImage } elseif ($robotFinalImage) { $robotFinalImage } elseif ($robotExecImage) { $robotExecImage } else { $null } }
        'api'     { $img = if ($robotApiImage) { $robotApiImage } elseif ($robotWarningImage) { $robotWarningImage } elseif ($robotFinalImage) { $robotFinalImage } elseif ($robotExecImage) { $robotExecImage } else { $null } }
    }
    if ($img) {
        $robotImage.Source = $img
        Update-RobotLayout
    } elseif ($robotPanel) {
        $robotPanel.Visibility = [System.Windows.Visibility]::Collapsed
        Update-RobotLayout
    }
}

function Set-GuardianRobotPhase {
    param([int]$PhaseId)
    $phaseImage = $script:GuardianPhaseRobotImages[$PhaseId]
    if ($phaseImage) {
        $robotImage.Source = $phaseImage
        Update-RobotLayout
    } else {
        # Se faltar o PNG da fase, preserva o comportamento original.
        Set-GuardianRobotState -State 'exec'
    }
}

function Update-RobotLayout {
    if ($null -eq $robotPanel) { return }
    $compact = ($window.ActualWidth -lt 900 -or -not $robotImage.Source)
    if ($compact) {
        $robotPanel.Visibility = [System.Windows.Visibility]::Collapsed
        $robotColumn.Width = [System.Windows.GridLength]::new(0)
        $robotGapColumn.Width = [System.Windows.GridLength]::new(0)
    } else {
        $robotColumn.Width = [System.Windows.GridLength]::new(250)
        $robotGapColumn.Width = [System.Windows.GridLength]::new(26)
        $robotPanel.Visibility = [System.Windows.Visibility]::Visible
    }
}

if ($robotExecImage -or $robotFinalImage -or $robotWarningImage -or $robotErrorImage -or $robotApiImage) {
    Set-GuardianRobotState -State 'exec'
} else {
    $robotPanel.Visibility = [System.Windows.Visibility]::Collapsed
}

$window.Add_SizeChanged({ Update-RobotLayout })
$minButton.Add_Click({ $window.WindowState = [System.Windows.WindowState]::Minimized })
$script:Finished = $false
$script:UiStarted = Get-Date
$window.Add_Closing({ param($sender,$args) if (-not $script:Finished) { $args.Cancel = $true } })
$finishButton.Add_Click({ if ($script:Finished) { $window.Close() } })

# Cor da Nota Geral: variacao visual independente da classificacao e da formula.
function Set-GuardianHealthScoreColor {
    param([double]$Score)
    $color = if ($Score -lt 50) { '#EB7777' }
             elseif ($Score -le 70) { '#F0A35B' }
             elseif ($Score -le 90) { '#E8CD69' }
             else { '#62DDA5' }
    $brush = [System.Windows.Media.BrushConverter]::new().ConvertFromString($color)
    $healthScore.Foreground = $brush
    $healthClass.Foreground = $brush
}

if ($Preview) {
    $script:Finished = $true
    $headline.Text = 'Seu computador está pronto!'
    $description.Text = 'Vistoria realizada com sucesso!'
    $phaseText.Text = 'Manutenção concluída'
    $activityLabel.Text = 'RESULTADO'
    $activityText.Text = 'Equipamento avaliado.'
    $endText.Text = ''
    $healthPanel.Visibility = [System.Windows.Visibility]::Visible
    $healthScore.Text = '86'
    Set-GuardianHealthScoreColor -Score 86
    $healthClass.Text = 'Boa (exemplo de prévia)'
    $progress.Value = 100
    $percentText.Text = '100%'
    Set-GuardianRobotState -State 'success'
    $finishButton.Visibility = [System.Windows.Visibility]::Visible
    Update-RobotLayout
    [void]$window.ShowDialog()
    return
}
# Apenas apresentacao dos eventos ja coletados: nao altera a telemetria nem a nota.
function Set-GuardianEventDisplay {
    param($CountValue, $CountText, $DescriptionText)
    $total = 0
    if ($null -eq $CountValue -or -not [int]::TryParse(([string]$CountValue).Trim(), [ref]$total) -or $total -lt 0) {
        $CountText.Text = 'Não disponível'
        $CountText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#E8F0F2')
        $DescriptionText.Text = 'Dados não disponíveis.'
        return
    }
    $CountText.Text = [string]$total
    if ($total -eq 0) {
        $color = '#6FE2AE'
        $reason = 'Nenhuma ocorrência registrada.'
    } elseif ($total -le 10) {
        $color = '#E5CE79'
        $reason = 'Ocorrências registradas para acompanhamento.'
    } elseif ($total -le 50) {
        $color = '#EBA56D'
        $reason = 'Volume elevado de registros. Sujeito à avaliação técnica.'
    }
    else {
        $color = '#EB7777'
        $reason = 'Volume muito elevado de registros. Sujeito à avaliação técnica.'
    }
    $CountText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($color)
    $DescriptionText.Text = $reason
}

# Uma janela independente, com listener restrito exclusivamente a localhost.
# Mostra apenas os indicadores que ja vieram do JSON final, sem calcular pontuacoes.
function Show-GuardianScoreBreakdown {
    param($Details, $Reasons)
    if ($null -eq $Details) { return }
    $items = @(
        @{ Key = 'Atualizacoes'; Label = 'Atualizações' },
        @{ Key = 'Particoes'; Label = 'Espaço Livre' },
        @{ Key = 'IntegridadeSistema'; Label = 'Integridade do Sistema' },
        @{ Key = 'Limpezas'; Label = 'Limpezas' },
        @{ Key = 'Backup'; Label = 'Macrium Reflect' },
        @{ Key = 'Rede'; Label = 'Rede' },
        @{ Key = 'Seguranca'; Label = 'Windows Defender' }
    )
    $scoreBreakdownRows.Children.Clear()
    foreach ($item in $items) {
        $property = $Details.PSObject.Properties[$item.Key]
        if ($null -eq $property -or $null -eq $property.Value) { continue }
        $value = 0.0
        if (-not [double]::TryParse([string]$property.Value, [ref]$value)) { continue }
        $value = [Math]::Max(0, [Math]::Min(100, $value))
        $color = if ($value -ge 90) { '#62DDA5' } elseif ($value -ge 75) { '#E8CD69' } elseif ($value -ge 50) { '#F0A35B' } else { '#EB7777' }
        $brush = [System.Windows.Media.BrushConverter]::new().ConvertFromString($color)

        $row = [System.Windows.Controls.StackPanel]::new()
        $row.Margin = [System.Windows.Thickness]::new(0,0,0,22)
        $line = [System.Windows.Controls.Grid]::new()
        [void]$line.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new())
        $numCol = [System.Windows.Controls.ColumnDefinition]::new()
        $numCol.Width = [System.Windows.GridLength]::Auto
        [void]$line.ColumnDefinitions.Add($numCol)

        $label = [System.Windows.Controls.TextBlock]::new()
        $label.Text = [string]$item.Label
        $label.FontSize = 15
        $label.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#E8F0F2')
        [void]$line.Children.Add($label)

        $number = [System.Windows.Controls.TextBlock]::new()
        $number.Text = ('{0}/100' -f ([Math]::Round($value,0)))
        $number.FontSize = 15
        $number.FontWeight = [System.Windows.FontWeights]::SemiBold
        $number.Foreground = $brush
        $number.Margin = [System.Windows.Thickness]::new(8,0,0,0)
        [System.Windows.Controls.Grid]::SetColumn($number,1)
        [void]$line.Children.Add($number)
        [void]$row.Children.Add($line)

        $bar = [System.Windows.Controls.ProgressBar]::new()
        $bar.Minimum = 0
        $bar.Maximum = 100
        $bar.Value = $value
        $bar.Height = 8
        $bar.Foreground = $brush
        $bar.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#2A3940')
        $bar.BorderThickness = [System.Windows.Thickness]::new(0)
        $bar.Margin = [System.Windows.Thickness]::new(0,9,0,0)
        [void]$row.Children.Add($bar)

        # Explicacao recebida dos dados reais da vistoria, sem inferir pela nota.
        $explanation = $null
        if ($null -ne $Reasons) {
            $reasonProp = $Reasons.PSObject.Properties[$item.Key]
            if ($null -ne $reasonProp -and -not [string]::IsNullOrWhiteSpace([string]$reasonProp.Value)) {
                $explanation = [string]$reasonProp.Value
            }
        }
        if ($explanation) {
            $detailText = [System.Windows.Controls.TextBlock]::new()
            $detailText.Text = $explanation
            $detailText.FontSize = 14
            $detailText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#AABFC7')
            $detailText.TextWrapping = [System.Windows.TextWrapping]::Wrap
            $detailText.Margin = [System.Windows.Thickness]::new(0,8,0,0)
            [void]$row.Children.Add($detailText)
        }
        [void]$scoreBreakdownRows.Children.Add($row)
    }
    if ($scoreBreakdownRows.Children.Count -gt 0) {
        $scoreBreakdownPanel.Visibility = [System.Windows.Visibility]::Visible
    }
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback,$Port)
$listener.Start()
$timer = [System.Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromMilliseconds(170)
$timer.Add_Tick({
    try {
        if (-not $script:Finished -and $EnginePid -gt 0 -and ((Get-Date) - $script:UiStarted).TotalSeconds -gt 5) {
            if (-not (Get-Process -Id $EnginePid -ErrorAction SilentlyContinue)) {
                $script:Finished = $true
                $phaseText.Text = 'Execução interrompida'
                $activityText.Text = 'O processo do Guardian foi encerrado antes da finalização.'
                $headline.Text = 'A manutenção não foi concluída.'
                $description.Text = 'A janela pode ser fechada. Se necessário, execute o Guardian novamente.'
                $endText.Text = 'Verificação manual recomendada.'
                $progress.Value = [Math]::Min(100,[Math]::Max(0,[int]$progress.Value))
                $percentText.Text = ('{0}%' -f [int]$progress.Value)
                $activityLabel.Text = 'RESULTADO DA MANUTENÇÃO'
                $finishButton.Content = 'Fechar'
                $finishButton.Visibility = [System.Windows.Visibility]::Visible
                Set-GuardianRobotState -State 'error'
            }
        }
        while ($listener.Pending()) {
            $client = $listener.AcceptTcpClient()
            try {
                $client.ReceiveTimeout = 100
                $reader = [System.IO.StreamReader]::new($client.GetStream(), [System.Text.Encoding]::UTF8)
                try {
                    $message = $reader.ReadToEnd() | ConvertFrom-Json -ErrorAction Stop
                    switch ([string]$message.type) {
                        'inventory' {
                            if ($null -ne $message.data) {
                                # Campos opcionais: nao inventar dados ausentes na mensagem de inventario.
                                $modelField = @('Fabricante e Modelo PC','fabricanteModelo','fabricante_modelo','computerModel','computer_model','modelo_computador','model') | Where-Object { $message.data.PSObject.Properties[$_] -and $message.data.$_ } | Select-Object -First 1
                                if ($modelField) { $computerModelValue.Text = [string]$message.data.$modelField }
                                else {
                                    # Fallback local: a mensagem inventory pode nao conter fabricante/modelo.
                                    # Consulta o mesmo equipamento que esta executando esta interface.
                                    try {
                                        $pcSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
                                        $pcManufacturer = ([string]$pcSystem.Manufacturer).Trim()
                                        $pcModel = ([string]$pcSystem.Model).Trim()
                                        if ($pcManufacturer -and $pcModel) {
                                            if ($pcModel.StartsWith($pcManufacturer, [System.StringComparison]::OrdinalIgnoreCase)) {
                                                $computerModelValue.Text = $pcModel
                                            } else {
                                                $computerModelValue.Text = "$pcManufacturer $pcModel"
                                            }
                                        } elseif ($pcModel) { $computerModelValue.Text = $pcModel }
                                        elseif ($pcManufacturer) { $computerModelValue.Text = $pcManufacturer }
                                    } catch { } # Mantem o travessao caso a consulta CIM nao esteja disponivel.
                                }
                                $cpuValue.Text = [string]$message.data.cpu
                                $ramValue.Text = [string]$message.data.ram
                                $gpuValue.Text = [string]$message.data.gpu
                                $storageValue.Text = [string]$message.data.storage
                                if ($message.data.os) { $osValue.Text = [string]$message.data.os }
                                $inventoryPanel.Visibility = [System.Windows.Visibility]::Visible
                            }
                        }
                        'phase' {
                            $phaseText.Text = [string]$message.label
                            $activityText.Text = 'Preparando atividades desta etapa...'
                            $progress.Value = [int]$message.percent
                            if ($null -ne $message.data -and $null -ne $message.data.phaseId) {
                                Set-GuardianRobotPhase -PhaseId ([int]$message.data.phaseId)
                            } else {
                                Set-GuardianRobotState -State 'exec'
                            }
                        }
                        'activity' {
                            $activityText.Text = [string]$message.label
                        }
                        'step' {
                            # A atividade ja foi anunciada antes da execucao.
                            # Aqui apenas atualizamos o progresso da tarefa concluida.
                            $progress.Value = [int]$message.percent
                        }
                        'complete' {
                            $script:Finished = $true
                            $progress.Value = 100
                            $activityLabel.Text = 'RESULTADO DA MANUTENÇÃO'
                            $finishButton.Content = 'Concluir'
                            $finishButton.Visibility = [System.Windows.Visibility]::Visible
                            if ($null -ne $message.data) {
                                if ($message.data.duration) {
                                    $durationValue.Text = [string]$message.data.duration
                                    $durationPanel.Visibility = [System.Windows.Visibility]::Visible
                                }
                                # Exibe somente os IDs efetivamente informados em PulaFases.
                                # Os dados chegam no evento de conclusao, sem ler JSON nem arquivos temporarios.
                                $ignored = @($message.data.skippedPhases | ForEach-Object { [int]$_ } | Where-Object { $script:GuardianSkippedPhaseTitles.ContainsKey($_) } | Sort-Object -Unique)
                                if ($ignored.Count -gt 0) {
                                    $skippedPhasesValue.Text = (($ignored | ForEach-Object { '{0} {1}' -f $_, $script:GuardianSkippedPhaseTitles[$_] }) -join [Environment]::NewLine)
                                } else {
                                    $skippedPhasesValue.Text = 'Nenhuma'
                                }
                                $durationPanel.Visibility = [System.Windows.Visibility]::Visible
                                if ($null -ne $message.data.events) {
                                     Set-GuardianEventDisplay $message.data.events.whea $wheaValue $wheaDescription
                                     Set-GuardianEventDisplay $message.data.events.bsod $bsodValue $bsodDescription
                                     Set-GuardianEventDisplay $message.data.events.shutdown $shutdownValue $shutdownDescription
                                     Set-GuardianEventDisplay $message.data.events.disk $diskEventsValue $diskEventsDescription
                                    $eventsPanel.Visibility = [System.Windows.Visibility]::Visible
                                }
                            }
                            $finalScore = $null
                            if ($null -ne $message.data -and $null -ne $message.data.score) {
                                $finalScore = [double]$message.data.score
                                $healthScore.Text = ('{0}' -f [int]$message.data.score)
                                Set-GuardianHealthScoreColor -Score $finalScore
                                $healthClass.Text = [string]$message.data.classification
                                $healthPanel.Visibility = [System.Windows.Visibility]::Visible
                                if ($null -ne $message.data.breakdown) {
                                    Show-GuardianScoreBreakdown -Details $message.data.breakdown -Reasons $message.data.scoreReasons
                                }
                            }
                            $robotState = 'success'
                            if ([string]$message.status -eq 'error') {
                                $robotState = 'error'
                            } elseif ($null -ne $message.data -and [string]$message.data.apiStatus -eq 'pending') {
                                $robotState = 'api'
                            } elseif ([string]$message.status -eq 'warning' -or ($null -ne $finalScore -and $finalScore -lt 70)) {
                                $robotState = 'warning'
                            }
                            Set-GuardianRobotState -State $robotState
                            switch ([string]$message.status) {
                                'ok' {
                                    $headline.Text = 'Seu computador está pronto!'
                                    $description.Text = 'Vistoria realizada com sucesso!'
                                    $phaseText.Text = 'Manutenção concluída'
                                    $activityText.Text = 'Confira o resumo do equipamento abaixo.'
                                    $endText.Text = ''
                                }
                                'warning' {
                                    $headline.Text = 'Manutenção finalizada.'
                                    $description.Text = 'A vistoria terminou e requer avaliação técnica.'
                                    $phaseText.Text = 'Manutenção com ressalvas'
                                    $activityText.Text = 'A equipe IT4YOU poderá verificar as pendências.'
                                    $endText.Text = ''
                                }
                                default {
                                    $headline.Text = 'Não foi possível concluir a manutenção.'
                                    $description.Text = 'A equipe IT4YOU poderá verificar o ocorrido.'
                                    $phaseText.Text = 'Manutenção encerrada com falha'
                                    $finishButton.Content = 'Fechar'
                                    $activityText.Text = 'Entre em contato com o suporte IT4YOU.'
                                    $endText.Text = ''
                                }
                            }
                            if ($robotState -eq 'api') {
                                $phaseText.Text = 'Manutenção concluída — integração com a API pendente.'
                            }
                        }
                    }
                    $percentText.Text = ('{0}%' -f [int]$progress.Value)
                } finally { $reader.Dispose() }
            } finally { $client.Dispose() }
        }
    } catch { } # Mensagens individuais malformadas nao derrubam a janela.
})
$window.Add_Loaded({ Update-RobotLayout })
$window.Add_Closed({ $timer.Stop(); $listener.Stop() })
$timer.Start()
[void]$window.ShowDialog()
