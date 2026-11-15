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
        Width="1050" Height="600" MinWidth="560" MinHeight="390"
        Background="Transparent" Foreground="#F4F6F8" WindowStartupLocation="Manual"
        FontFamily="Segoe UI" Title="Guardian 360 v2.0" ShowInTaskbar="True">
  <Border BorderBrush="#29383E" BorderThickness="1" CornerRadius="12" Background="#000000">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="47"/>
        <RowDefinition Height="118"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="76"/>
      </Grid.RowDefinitions>

      <Border Grid.Row="0" Background="#11181B" BorderBrush="#263237" BorderThickness="0,0,0,1" CornerRadius="11,11,0,0">
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

      <!-- Banner oficial fixo, no topo da área principal, abaixo da barra de título.
           Mantido nas telas de execução e conclusão. -->
      <Border Grid.Row="1" Margin="34,8,34,8" Background="#000000" ClipToBounds="True">
        <Image x:Name="HeaderBackground" HorizontalAlignment="Center"
               VerticalAlignment="Center" Stretch="Uniform"
               StretchDirection="DownOnly" SnapsToDevicePixels="True"
               RenderOptions.BitmapScalingMode="HighQuality"/>
      </Border>

      <Grid Grid.Row="2" Margin="34,0,34,10">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="3*"/>
          <ColumnDefinition x:Name="RobotGapColumn" Width="26"/>
          <ColumnDefinition x:Name="RobotColumn" Width="250"/>
        </Grid.ColumnDefinitions>
        <Border x:Name="MainCard" Grid.Column="0" BorderBrush="#26363B" BorderThickness="1" CornerRadius="12" Background="#101719" Padding="24">
          <Border.RenderTransform><TranslateTransform Y="8"/></Border.RenderTransform>
          <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Focusable="False" Padding="0,0,12,0">
            <ScrollViewer.Resources>
              <Style TargetType="{x:Type ScrollBar}">
                <Setter Property="Width" Value="4"/>
                <Setter Property="Background" Value="#101719"/>
                <Setter Property="Template">
                  <Setter.Value>
                    <ControlTemplate TargetType="{x:Type ScrollBar}">
                      <Border Background="{TemplateBinding Background}" CornerRadius="4">
                        <Track x:Name="PART_Track" IsDirectionReversed="True" Focusable="False">
                          <Track.DecreaseRepeatButton>
                            <RepeatButton Focusable="False" Opacity="0" Command="ScrollBar.PageUpCommand"/>
                          </Track.DecreaseRepeatButton>
                          <Track.Thumb>
                            <Thumb>
                              <Thumb.Template>
                                <ControlTemplate TargetType="{x:Type Thumb}">
                                  <Border x:Name="ThumbSurface" Background="#24343D" CornerRadius="2" Margin="0.5,1"/>
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
              <TextBlock x:Name="MainHeadline" Text="Estamos cuidando do seu computador." FontSize="20" FontWeight="SemiBold" Foreground="White" TextWrapping="Wrap"/>
              <TextBlock x:Name="MainDescription" Text="A manutenção é executada automaticamente. Você pode minimizar esta janela." TextWrapping="Wrap" Foreground="#AFC0C5" FontSize="12" Margin="0,8,0,20"/>
              <TextBlock x:Name="PhaseText" Text="Preparando manutenção preventiva..." FontSize="16" FontWeight="SemiBold" Foreground="#64D5EB" TextWrapping="Wrap" Margin="0,0,0,18"/>
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="52"/></Grid.ColumnDefinitions>
                <ProgressBar x:Name="MainProgress" Minimum="0" Maximum="100" Value="0" Height="11" Foreground="#49DFA1" Background="#283438" BorderThickness="0"/>
                <TextBlock x:Name="PercentText" Grid.Column="1" Text="0%" FontWeight="SemiBold" FontSize="15" Foreground="#61E3A7" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,8,0"/>
              </Grid>
              <TextBlock x:Name="ActivityLabel" Text="ATIVIDADE ATUAL" Foreground="#77909A" FontSize="10" FontWeight="Bold" Margin="0,20,0,0"/>
              <TextBlock x:Name="ActivityText" Text="Inicializando o Guardian..." Foreground="#F2F5F6" FontSize="13" Margin="0,7,0,0" TextWrapping="Wrap"/>
              <StackPanel Margin="0,18,0,0">
                <Border Height="1" Background="#28383D" Margin="0,0,0,12"/>
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="14"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                  <StackPanel Grid.Row="0" Grid.Column="0" Margin="0,0,0,12"><TextBlock Text="EMPRESA" FontSize="9" Foreground="#78939C"/><TextBlock x:Name="ClientText" Foreground="#E8F0F2" FontSize="12" TextWrapping="Wrap"/></StackPanel>
                  <StackPanel Grid.Row="0" Grid.Column="2" Margin="0,0,0,12"><TextBlock Text="COMPUTADOR" FontSize="9" Foreground="#78939C"/><TextBlock x:Name="PCText" Foreground="#E8F0F2" FontSize="12" TextWrapping="Wrap"/></StackPanel>
                  <StackPanel Grid.Row="1" Grid.Column="0" Grid.ColumnSpan="3"><TextBlock Text="SISTEMA OPERACIONAL E VERSÃO" FontSize="9" Foreground="#78939C" TextWrapping="Wrap"/><TextBlock x:Name="OsValue" Text="Aguardando inventário" Foreground="#E8F0F2" FontSize="12" TextWrapping="Wrap"/></StackPanel>
                </Grid>
              </StackPanel>
              <StackPanel x:Name="InventoryPanel" Visibility="Collapsed" Margin="0,18,0,0">
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="14"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                  <StackPanel Grid.Row="0" Grid.Column="0" Margin="0,0,0,12"><TextBlock Text="PROCESSADOR" FontSize="9" Foreground="#78939C"/><TextBlock x:Name="CpuValue" Text="—" FontSize="12" Foreground="#E8F0F2" TextWrapping="Wrap"/></StackPanel>
                  <StackPanel Grid.Row="0" Grid.Column="2" Margin="0,0,0,12"><TextBlock Text="MEMÓRIA RAM" FontSize="9" Foreground="#78939C"/><TextBlock x:Name="RamValue" Text="—" FontSize="12" Foreground="#E8F0F2" TextWrapping="Wrap"/></StackPanel>
                  <StackPanel Grid.Row="1" Grid.Column="0"><TextBlock Text="PLACA DE VÍDEO" FontSize="9" Foreground="#78939C"/><TextBlock x:Name="GpuValue" Text="—" FontSize="12" Foreground="#E8F0F2" TextWrapping="Wrap"/></StackPanel>
                  <StackPanel Grid.Row="1" Grid.Column="2"><TextBlock Text="WINDOWS INSTALADO EM" FontSize="9" Foreground="#78939C" TextWrapping="Wrap"/><TextBlock x:Name="StorageValue" Text="—" FontSize="12" Foreground="#E8F0F2" TextWrapping="Wrap"/></StackPanel>
                </Grid>
              </StackPanel>
              <StackPanel x:Name="EventsPanel" Visibility="Collapsed" Margin="0,20,0,0">
                <Border Height="1" Background="#28383D" Margin="0,0,0,12"/>
                <TextBlock Text="EVENTOS CRÍTICOS NO WINDOWS" FontSize="10" Foreground="#64D5EB" FontWeight="SemiBold" Margin="0,0,0,12"/>
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="14"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                  <StackPanel Grid.Row="0" Grid.Column="0" Margin="0,0,0,12"><TextBlock Text="FALHAS DE HARDWARE (WHEA)" FontSize="9" Foreground="#78939C"/><TextBlock x:Name="WheaValue" Text="Não disponível" Foreground="#E8F0F2" FontSize="12"/></StackPanel>
                  <StackPanel Grid.Row="0" Grid.Column="2" Margin="0,0,0,12"><TextBlock Text="TELAS AZUIS (BSOD)" FontSize="9" Foreground="#78939C"/><TextBlock x:Name="BsodValue" Text="Não disponível" Foreground="#E8F0F2" FontSize="12"/></StackPanel>
                  <StackPanel Grid.Row="1" Grid.Column="0"><TextBlock Text="DESLIGAMENTOS INESPERADOS" FontSize="9" Foreground="#78939C" TextWrapping="Wrap"/><TextBlock x:Name="ShutdownValue" Text="Não disponível" Foreground="#E8F0F2" FontSize="12"/></StackPanel>
                  <StackPanel Grid.Row="1" Grid.Column="2"><TextBlock Text="ERROS DE DISCO" FontSize="9" Foreground="#78939C"/><TextBlock x:Name="DiskEventsValue" Text="Não disponível" Foreground="#E8F0F2" FontSize="12"/></StackPanel>
                </Grid>
              </StackPanel>
              <StackPanel x:Name="DurationPanel" Visibility="Collapsed" Margin="0,18,0,0">
                <TextBlock Text="TEMPO DE EXECUÇÃO" FontSize="9" Foreground="#78939C"/>
                <TextBlock x:Name="DurationValue" Text="" FontSize="12" Foreground="#E8F0F2"/>
              </StackPanel>
              <Grid x:Name="HealthPanel" Visibility="Collapsed" Margin="0,16,0,0">
                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <StackPanel VerticalAlignment="Center"><TextBlock Text="SAÚDE GERAL DO SISTEMA" FontSize="10" Foreground="#78939C"/><TextBlock x:Name="HealthClass" Text="" FontSize="13" Foreground="#E8F0F2"/></StackPanel>
                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Bottom" HorizontalAlignment="Right" Margin="0,0,8,0">
                  <TextBlock Text="Nota:" Foreground="White" FontSize="15" FontWeight="SemiBold" VerticalAlignment="Bottom" Margin="0,0,8,4"/>
                  <TextBlock x:Name="HealthScore" Text="" Foreground="#61E3A7" FontSize="30" FontWeight="SemiBold" VerticalAlignment="Bottom"/>
                </StackPanel>
              </Grid>
              <TextBlock x:Name="EndText" Text="" FontSize="12" Foreground="#FF00FF00" Margin="0,12,0,0" TextWrapping="Wrap"/>

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
        <Border Grid.Row="1" BorderThickness="0" Padding="0,0,0,0">
          <WrapPanel VerticalAlignment="Top" ItemHeight="25">
            <WrapPanel.RenderTransform>
              <TranslateTransform Y="-10"/>
            </WrapPanel.RenderTransform>
            <TextBlock Text="Suporte IT4YOU" Foreground="#E8F0F2" FontSize="12.5" FontWeight="SemiBold" Margin="0,0,16,0"/>
            <Viewbox Width="19.2" Height="19.2" Margin="0,0,6,0" Stretch="Uniform" VerticalAlignment="Center">
              <Path Fill="#00FF00" Data="M380.9 97.1C339 55.1 283.2 32 223.9 32c-122.4 0-222 99.6-222 222 0 39.1 10.2 77.3 29.6 111L0 480l117.7-30.9c32.4 17.7 68.9 27 106.1 27h.1c122.3 0 224.1-99.6 224.1-222 0-59.3-25.2-115-67.1-157zm-157 341.6c-33.2 0-65.7-8.9-94-25.7l-6.7-4-69.8 18.3L72 359.2l-4.4-7c-18.5-29.4-28.2-63.3-28.2-98.2 0-101.7 82.8-184.5 184.6-184.5 49.3 0 95.6 19.2 130.4 54.1 34.8 34.9 56.2 81.2 56.1 130.5 0 101.8-84.9 184.6-186.6 184.6zm101.2-138.2c-5.5-2.8-32.8-16.2-37.9-18-5.1-1.9-8.8-2.8-12.5 2.8-3.7 5.6-14.3 18-17.6 21.8-3.2 3.7-6.5 4.2-12 1.4-32.6-16.3-54-29.1-75.5-66-5.7-9.8 5.7-9.1 16.3-30.3 1.8-3.7.9-6.9-.5-9.7-1.4-2.8-12.5-30.1-17.1-41.2-4.5-10.8-9.1-9.3-12.5-9.5-3.2-.2-6.9-.2-10.6-.2-3.7 0-9.7 1.4-14.8 6.9-5.1 5.6-19.4 19-19.4 46.3 0 27.3 19.9 53.7 22.6 57.4 2.8 3.7 39.1 59.7 94.8 83.8 35.2 15.2 49 16.5 66.6 13.9 10.7-1.6 32.8-13.4 37.4-26.4 4.6-13 4.6-24.1 3.2-26.4-1.3-2.5-5-3.9-10.5-6.6z" Width="448" Height="512" Stretch="Fill"/>
            </Viewbox>
            <TextBlock Text="(11) 9.7191-1500" Foreground="#C8D4D8" FontSize="12.5" Margin="0,0,18,0"/>
            <TextBlock Text="✉" Foreground="#FF00FF00" FontSize="16.8" Margin="0,0,6,0"/>
            <TextBlock Text="suporte@it4you.com.br" Foreground="#C8D4D8" FontSize="12.5" Margin="0,0,18,0"/>
            <!-- Globe / Website: vetor nítido em qualquer DPI -->
            <Viewbox Width="18" Height="18" Margin="0,0,6,0" Stretch="Uniform" VerticalAlignment="Center">
              <Grid Width="18" Height="18">
                <Ellipse Width="15" Height="15" Stroke="#FF00FF00" StrokeThickness="1.25"/>
                <Ellipse Width="7" Height="15" Stroke="#FF00FF00" StrokeThickness="1.1"/>
                <Path Data="M 1.5,9 L 16.5,9" Stroke="#FF00FF00" StrokeThickness="1.1"/>
              </Grid>
            </Viewbox>
            <TextBlock Text="it4you.com.br" Foreground="#C8D4D8" FontSize="12.5"/>
          </WrapPanel>
        </Border>
      </Grid>
    </Grid>
  </Border>
</Window>
'@

$baseDir = Split-Path -Parent $PSScriptRoot
$robotExecPath = Join-Path $baseDir 'Assets\Images\guardian_robot_execucao.png'
$robotFinalPath = Join-Path $baseDir 'Assets\Images\guardian_robot_final.png'
$backgroundPath = Join-Path $baseDir 'Assets\Images\bg.png'
$robotExecImage = Get-GuardianBitmapImage -Path $robotExecPath
$robotFinalImage = Get-GuardianBitmapImage -Path $robotFinalPath
$backgroundImage = Get-GuardianBitmapImage -Path $backgroundPath

# Centraliza no MESMO monitor do console do Guardian. Se nao houver
# console visivel, seleciona o monitor principal. Mantem as dimensoes da UI 29.
$guardianScreen = Get-GuardianConsoleScreen -EngineProcessId $EnginePid
$preferredWidth = 1050.0
$preferredHeight = 600.0

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
$cpuValue = $window.FindName('CpuValue')
$ramValue = $window.FindName('RamValue')
$gpuValue = $window.FindName('GpuValue')
$storageValue = $window.FindName('StorageValue')
$healthScore = $window.FindName('HealthScore')
$healthClass = $window.FindName('HealthClass')
$osValue = $window.FindName('OsValue')
$eventsPanel = $window.FindName('EventsPanel')
$wheaValue = $window.FindName('WheaValue')
$bsodValue = $window.FindName('BsodValue')
$shutdownValue = $window.FindName('ShutdownValue')
$diskEventsValue = $window.FindName('DiskEventsValue')
$durationPanel = $window.FindName('DurationPanel')
$durationValue = $window.FindName('DurationValue')
$robotGapColumn = $window.FindName('RobotGapColumn')
$robotColumn = $window.FindName('RobotColumn')

$finishButton = $window.FindName('FinishButton')
$minButton = $window.FindName('MinButton')
$robotPanel = $window.FindName('RobotPanel')
$robotImage = $window.FindName('RobotImage')
$headerBackground = $window.FindName('HeaderBackground')
if ($backgroundImage) { $headerBackground.Source = $backgroundImage }
$window.FindName('ClientText').Text = "$Cliente"
$window.FindName('PCText').Text = "$Computador"

if ($robotExecImage) {
    $robotImage.Source = $robotExecImage
} elseif ($robotFinalImage) {
    $robotImage.Source = $robotFinalImage
} else {
    $robotPanel.Visibility = [System.Windows.Visibility]::Collapsed
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

$window.Add_SizeChanged({ Update-RobotLayout })
$minButton.Add_Click({ $window.WindowState = [System.Windows.WindowState]::Minimized })
$script:Finished = $false
$script:UiStarted = Get-Date
$window.Add_Closing({ param($sender,$args) if (-not $script:Finished) { $args.Cancel = $true } })
$finishButton.Add_Click({ if ($script:Finished) { $window.Close() } })

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
    $healthClass.Text = 'Boa (exemplo de prévia)'
    $progress.Value = 100
    $percentText.Text = '100%'
    if ($robotFinalImage) { $robotImage.Source = $robotFinalImage }
    $finishButton.Visibility = [System.Windows.Visibility]::Visible
    Update-RobotLayout
    [void]$window.ShowDialog()
    return
}
# Uma janela independente, com listener restrito exclusivamente a localhost.
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
                if ($robotFinalImage) { $robotImage.Source = $robotFinalImage; Update-RobotLayout }
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
                            $progress.Value = [int]$message.percent
                            if ($robotExecImage) { $robotImage.Source = $robotExecImage; Update-RobotLayout }
                        }
                        'step'  {
                            $activityText.Text = ([string]$message.label -replace '-', ' ')
                            $progress.Value = [int]$message.percent
                        }
                        'complete' {
                            $script:Finished = $true
                            $progress.Value = 100
                            $activityLabel.Text = 'RESULTADO DA MANUTENÇÃO'
                            $finishButton.Content = 'Concluir'
                            $finishButton.Visibility = [System.Windows.Visibility]::Visible
                            if ($robotFinalImage) { $robotImage.Source = $robotFinalImage; Update-RobotLayout }
                            if ($null -ne $message.data) {
                                if ($message.data.duration) {
                                    $durationValue.Text = [string]$message.data.duration
                                    $durationPanel.Visibility = [System.Windows.Visibility]::Visible
                                }
                                if ($null -ne $message.data.events) {
                                    $wheaValue.Text = [string]$message.data.events.whea
                                    $bsodValue.Text = [string]$message.data.events.bsod
                                    $shutdownValue.Text = [string]$message.data.events.shutdown
                                    $diskEventsValue.Text = [string]$message.data.events.disk
                                    $eventsPanel.Visibility = [System.Windows.Visibility]::Visible
                                }
                            }
                            if ($null -ne $message.data -and $null -ne $message.data.score) {
                                $healthScore.Text = ('{0}' -f [int]$message.data.score)
                                $healthClass.Text = [string]$message.data.classification
                                $healthPanel.Visibility = [System.Windows.Visibility]::Visible
                            }
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
