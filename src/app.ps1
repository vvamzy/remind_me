Param()

Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase

function New-Brush($r,$g,$b){
  $color = [Windows.Media.Color]::FromRgb([byte]$r,[byte]$g,[byte]$b)
  $brush = New-Object Windows.Media.SolidColorBrush $color
  $brush.Freeze() | Out-Null
  return $brush
}

function Lerp($a,$b,$t){ return [math]::Round($a + ($b-$a)*$t) }

$AppName = 'TodoTimer'
# Resolve a writable data directory with fallbacks
function Resolve-WritableDir {
  param([string[]]$Candidates)
  $localFallback = $null
  try {
    $localBase = Split-Path -Parent $PSCommandPath
    if(-not [string]::IsNullOrWhiteSpace($localBase)){
      $localFallback = Join-Path $localBase '..\data'
    }
  } catch { }
  foreach($c in $Candidates){
    try {
      if(-not (Test-Path $c)){ New-Item -Type Directory -Path $c -ErrorAction Stop | Out-Null }
      # probe write access
      $probe = Join-Path $c ".probe"
      "ok" | Set-Content -Path $probe -Encoding UTF8 -ErrorAction Stop
      Remove-Item -Path $probe -Force -ErrorAction Stop
      return $c
    } catch { continue }
  }
  if($localFallback){
    try {
      if(-not (Test-Path $localFallback)){ New-Item -Type Directory -Path $localFallback -ErrorAction Stop | Out-Null }
      return $localFallback
    } catch { }
  }
  return (Join-Path (Get-Location) ".runtime\$AppName")
}
$StorageDir = Resolve-WritableDir @(
  (Join-Path $env:LOCALAPPDATA $AppName),
  (Join-Path $env:APPDATA $AppName),
  (Join-Path $env:TEMP $AppName)
)
$StorageFile = Join-Path $StorageDir 'state.json'

function Load-State {
  if(Test-Path $StorageFile){
    try { return (Get-Content $StorageFile -Raw | ConvertFrom-Json) } catch { }
  }
  return @()
}
function Save-State {
  param($Todos)
  $Todos | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 $StorageFile
}

[string]$SettingsFile = Join-Path $StorageDir 'settings.json'
function Load-Settings {
  if(Test-Path $SettingsFile){
    try { return (Get-Content $SettingsFile -Raw | ConvertFrom-Json) } catch { }
  }
  return [pscustomobject]@{ themeMode = 'Dark' }
}
function Save-Settings {
  param($Settings)
  $Settings | ConvertTo-Json -Depth 3 | Set-Content -Encoding UTF8 $SettingsFile
}
function Get-SystemThemeLight {
  try {
    $v = Get-ItemPropertyValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme'
    return [bool]($v -eq 1)
  } catch { return $false }
}
function Resolve-Mode([string]$m){
  if($m -eq 'Auto'){ if(Get-SystemThemeLight){ return 'Light' } else { return 'Dark' } }
  if($m -eq 'Light'){ return 'Light' } else { return 'Dark' }
}
function Build-Theme([string]$mode){
  if($mode -eq 'Light'){
    $g = New-Object Windows.Media.LinearGradientBrush
    $g.StartPoint = '0,0'
    $g.EndPoint = '0,1'
    $gs1 = New-Object Windows.Media.GradientStop
    $gs1.Color = [Windows.Media.Color]::FromRgb(246,249,252)
    $gs1.Offset = 0
    $gs2 = New-Object Windows.Media.GradientStop
    $gs2.Color = [Windows.Media.Color]::FromRgb(255,255,255)
    $gs2.Offset = 1
    $g.GradientStops.Add($gs1) | Out-Null
    $g.GradientStops.Add($gs2) | Out-Null
    return @{
      WindowBg = $g
      Text = New-Brush 10 15 20
      Muted = New-Brush 75 85 99
      PanelBg = New-Brush 255 255 255
      Border = New-Brush 229 231 235
      BarBg = New-Brush 227 232 238
      Primary = New-Brush 14 165 255
      PrimaryBorder = New-Brush 2 132 199
      Danger = New-Brush 239 68 68
      DangerBorder = New-Brush 127 29 29
      Completed = New-Brush 163 163 171
      Neon = New-Brush 0 229 255
    }
  } else {
    $g = New-Object Windows.Media.LinearGradientBrush
    $g.StartPoint = '0,0'
    $g.EndPoint = '0,1'
    $gs1 = New-Object Windows.Media.GradientStop
    $gs1.Color = [Windows.Media.Color]::FromRgb(11,18,32)
    $gs1.Offset = 0
    $gs2 = New-Object Windows.Media.GradientStop
    $gs2.Color = [Windows.Media.Color]::FromRgb(13,15,18)
    $gs2.Offset = 1
    $g.GradientStops.Add($gs1) | Out-Null
    $g.GradientStops.Add($gs2) | Out-Null
    return @{
      WindowBg = $g
      Text = New-Brush 231 237 243
      Muted = New-Brush 140 160 179
      PanelBg = New-Brush 21 26 32
      Border = New-Brush 31 41 51
      BarBg = New-Brush 27 39 51
      Primary = New-Brush 0 229 255
      PrimaryBorder = New-Brush 0 146 170
      Danger = New-Brush 239 68 68
      DangerBorder = New-Brush 127 29 29
      Completed = New-Brush 63 63 70
      Neon = New-Brush 0 229 255
    }
  }
}
$script:Settings = Load-Settings
$script:Theme = Build-Theme (Resolve-Mode $script:Settings.themeMode)

# logging
$LogRoot = $StorageDir
$LogDir = Join-Path $LogRoot 'logs'
if(-not (Test-Path $LogDir)){ New-Item -Type Directory -Path $LogDir -ErrorAction SilentlyContinue | Out-Null }
$LogFile = Join-Path $LogDir 'todotimer.log'
function Get-LogLevelValue($lvl){
  switch ($lvl.ToUpper()) { 'DEBUG' {0} 'INFO' {1} 'WARN' {2} 'ERROR' {3} default {1} }
}
$script:LogLevel = $env:TODO_TIMER_LOG_LEVEL
if(-not $script:LogLevel -or $script:LogLevel -eq ''){ $script:LogLevel = 'INFO' }
function Write-Log($level, $message){
  try {
    if((Get-LogLevelValue $level) -lt (Get-LogLevelValue $script:LogLevel)){ return }
    $ts = (Get-Date).ToString('s')
    $line = "$ts [$level] $message"
    $size = 0
    if(Test-Path $LogFile){ $size = (Get-Item $LogFile).Length }
    if($size -gt 2097152){ Move-Item -Force $LogFile ($LogFile + '.1') -ErrorAction SilentlyContinue }
    $line | Add-Content -Path $LogFile -Encoding UTF8
  } catch { }
}
Write-Log 'INFO' 'App starting'

$window = New-Object Windows.Window
$window.Title = 'Todo Timer'
$window.Width = 900
$window.Height = 650
$window.MinWidth = 720
$window.MinHeight = 480
$window.Background = $script:Theme.WindowBg
$window.Foreground = $script:Theme.Text

$root = New-Object Windows.Controls.Grid
$root.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition)) | Out-Null
$root.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition)) | Out-Null
($root.RowDefinitions[0]).Height = 'Auto'
($root.RowDefinitions[1]).Height = '*'
$window.Content = $root

$header = New-Object Windows.Controls.StackPanel
$header.Orientation = 'Vertical'
$header.Margin = '14'
[Windows.Controls.Grid]::SetRow($header,0)
$root.Children.Add($header) | Out-Null

$titleRow = New-Object Windows.Controls.StackPanel
$titleRow.Orientation = 'Horizontal'
$titleRow.HorizontalAlignment = 'Stretch'
$titleRow.Margin = '0,0,0,8'
$header.Children.Add($titleRow) | Out-Null

$titleText = New-Object Windows.Controls.TextBlock
$titleText.Text = 'Todo Timer'
$titleText.FontSize = 22
$titleText.FontWeight = 'Bold'
$titleText.Margin = '0,0,8,0'
$titleRow.Children.Add($titleText) | Out-Null

$versionText = New-Object Windows.Controls.TextBlock
$versionText.Text = 'v0.1.0'
$versionText.VerticalAlignment = 'Center'
$versionText.Foreground = $script:Theme.Muted
$titleRow.Children.Add($versionText) | Out-Null

$form = New-Object Windows.Controls.StackPanel
$form.Orientation = 'Horizontal'
$form.Margin = '0,0,0,8'
$form.HorizontalAlignment = 'Left'
$header.Children.Add($form) | Out-Null

$tbTitle = New-Object Windows.Controls.TextBox
$tbTitle.Width = 420
$tbTitle.ToolTip = 'What do you need to do?'
$tbTitle.Padding = '8'
$tbTitle.Background = $script:Theme.PanelBg
$tbTitle.BorderBrush = $script:Theme.Border
$form.Children.Add($tbTitle) | Out-Null

$tbMins = New-Object Windows.Controls.TextBox
$tbMins.Width = 60
$tbMins.Text = '25'
$tbMins.Padding = '8'
$tbMins.TextAlignment = 'Right'
$tbMins.Background = $script:Theme.PanelBg
$tbMins.BorderBrush = $script:Theme.Border
$form.Children.Add($tbMins) | Out-Null

$lblMins = New-Object Windows.Controls.TextBlock
$lblMins.Text = 'mins'
$lblMins.VerticalAlignment = 'Center'
$form.Children.Add($lblMins) | Out-Null

$tbSecs = New-Object Windows.Controls.TextBox
$tbSecs.Width = 60
$tbSecs.Text = '0'
$tbSecs.Padding = '8'
$tbSecs.TextAlignment = 'Right'
$tbSecs.Background = $script:Theme.PanelBg
$tbSecs.BorderBrush = $script:Theme.Border
$form.Children.Add($tbSecs) | Out-Null

$lblSecs = New-Object Windows.Controls.TextBlock
$lblSecs.Text = 'secs'
$lblSecs.VerticalAlignment = 'Center'
$form.Children.Add($lblSecs) | Out-Null

$btnAdd = New-Object Windows.Controls.Button
$btnAdd.Content = 'Add'
$btnAdd.Padding = '8,6'
$btnAdd.Background = $script:Theme.Primary
$btnAdd.BorderBrush = $script:Theme.PrimaryBorder
$form.Children.Add($btnAdd) | Out-Null

$filters = New-Object Windows.Controls.StackPanel
$filters.Orientation = 'Horizontal'
$header.Children.Add($filters) | Out-Null

$cbFilter = New-Object Windows.Controls.ComboBox
@('All','Active','Done') | ForEach-Object { [void]$cbFilter.Items.Add($_) }
$cbFilter.SelectedIndex = 0
$filters.Children.Add($cbFilter) | Out-Null

$btnClearDone = New-Object Windows.Controls.Button
$btnClearDone.Content = 'Clear Done'
$btnClearDone.Padding = '6,4'
$btnClearDone.Background = $script:Theme.Danger
$btnClearDone.BorderBrush = $script:Theme.DangerBorder
$filters.Children.Add($btnClearDone) | Out-Null

$cbTheme = New-Object Windows.Controls.ComboBox
@('Dark','Light','Auto') | ForEach-Object { [void]$cbTheme.Items.Add($_) }
switch ($script:Settings.themeMode) { 'Light'{ $cbTheme.SelectedIndex=1 } 'Auto'{ $cbTheme.SelectedIndex=2 } default{ $cbTheme.SelectedIndex=0 } }
$filters.Children.Add($cbTheme) | Out-Null

[Windows.Controls.ScrollViewer]$sv = New-Object Windows.Controls.ScrollViewer
[Windows.Controls.Grid]::SetRow($sv,1)
$sv.Margin = '14'
$sv.VerticalScrollBarVisibility = 'Auto'
$root.Children.Add($sv) | Out-Null

$itemsPanel = New-Object Windows.Controls.StackPanel
$sv.Content = $itemsPanel

$script:Todos = @()
Load-State | ForEach-Object { $script:Todos += $_ }

function New-TodoPanel($todo){
  $panel = New-Object Windows.Controls.Border
  $panel.Margin = '0,0,0,4'
  $panel.Background = $script:Theme.PanelBg
  $panel.BorderBrush = $script:Theme.Border
  $panel.BorderThickness = '1'
  $panel.Padding = '8'
  $grid = New-Object Windows.Controls.Grid
  $grid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition)) | Out-Null
  $grid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition)) | Out-Null
  ($grid.ColumnDefinitions[0]).Width = 'Auto'
  ($grid.ColumnDefinitions[1]).Width = '*'
  $panel.Child = $grid
  $fx = New-Object Windows.Media.Effects.DropShadowEffect
  $fx.BlurRadius = 10
  $fx.Color = ([Windows.Media.Color]::FromRgb(0,229,255))
  $fx.Opacity = 0.15
  $fx.Direction = 270
  $fx.ShadowDepth = 1
  $panel.Effect = $fx

  $left = New-Object Windows.Controls.StackPanel
  $left.Orientation = 'Horizontal'
  [Windows.Controls.Grid]::SetColumn($left,0)
  $grid.Children.Add($left) | Out-Null

  $chk = New-Object Windows.Controls.CheckBox
  $chk.IsChecked = [bool]$todo.done
  $left.Children.Add($chk) | Out-Null

  $title = New-Object Windows.Controls.TextBlock
  $title.Text = $todo.title
  $title.FontWeight = 'SemiBold'
  $title.Width = 300
  $title.TextTrimming = 'CharacterEllipsis'
  $left.Children.Add($title) | Out-Null

  $due = New-Object Windows.Controls.TextBlock
  $due.Foreground = $script:Theme.Muted
  $left.Children.Add($due) | Out-Null

  $right = New-Object Windows.Controls.StackPanel
  $right.Orientation = 'Horizontal'
  $right.HorizontalAlignment = 'Right'
  [Windows.Controls.Grid]::SetColumn($right,1)
  $grid.Children.Add($right) | Out-Null

  $stack = New-Object Windows.Controls.StackPanel
  $stack.Width = 260
  $right.Children.Add($stack) | Out-Null

  $bar = New-Object Windows.Controls.ProgressBar
  $bar.Minimum = 0
  $bar.Maximum = 100
  $bar.Height = 10
  $bar.Background = $script:Theme.BarBg
  $bar.BorderBrush = $script:Theme.Border
  $bar.Value = 0
  $stack.Children.Add($bar) | Out-Null

  $timeText = New-Object Windows.Controls.TextBlock
  $timeText.Foreground = $script:Theme.Muted
  $timeText.FontSize = 12
  $stack.Children.Add($timeText) | Out-Null

  $btnDel = New-Object Windows.Controls.Button
  $btnDel.Content = 'Delete'
  $btnDel.Padding = '6,4'
  $btnDel.Background = $script:Theme.Danger
  $btnDel.BorderBrush = $script:Theme.DangerBorder
  $right.Children.Add($btnDel) | Out-Null

  $panel.Tag = [pscustomobject]@{
    CheckBox = $chk
    Title = $title
    Due = $due
    Bar = $bar
    TimeText = $timeText
    Delete = $btnDel
    Todo = $todo
  }

  $chk.Add_Checked({
    $panel.Tag.Todo.done = $true
    $panel.Tag.Todo.doneAt = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
    Save-State $script:Todos
    Update-Panel $panel
    Write-Log 'INFO' ("Completed todo: " + $panel.Tag.Todo.title)
  })
  $chk.Add_Unchecked({
    $panel.Tag.Todo.done = $false
    $panel.Tag.Todo.doneAt = $null
    Save-State $script:Todos
    Update-Panel $panel
    Write-Log 'INFO' ("Reopened todo: " + $panel.Tag.Todo.title)
  })
  $btnDel.Add_Click({
    $script:Todos = $script:Todos | Where-Object { $_.id -ne $panel.Tag.Todo.id }
    $itemsPanel.Children.Remove($panel) | Out-Null
    Save-State $script:Todos
    Write-Log 'INFO' ("Deleted todo: " + $todo.title)
  })

  Update-Panel $panel
  return $panel
}

function Format-HMS($ms){
  $neg = $ms -lt 0
  if($neg){ $ms = -$ms }
  $s = [math]::Floor($ms/1000)
  $h = [math]::Floor($s/3600)
  $m = [math]::Floor(($s%3600)/60)
  $sec = $s%60
  $str = ('{0:00}:{1:00}:{2:00}' -f $h,$m,$sec)
  if($neg){ "-$str" } else { $str }
}

function Update-Panel($panel){
  $t = $panel.Tag.Todo
  $now = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
  $elapsed = [math]::Max(0, [math]::Min($t.totalMs, $now - $t.createdAt))
  $frac = if($t.totalMs -eq 0){ 1 } else { $elapsed / $t.totalMs }
  $remaining = $t.dueAt - $now
  $pct = [math]::Round($frac*100)

  $dueDt = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$t.dueAt).LocalDateTime
  $panel.Tag.Due.Text = (' due {0:HH:mm}' -f $dueDt)

  $panel.Tag.Bar.Value = $pct
  if($t.done){
    $panel.Tag.TimeText.Text = 'Completed'
    $panel.Tag.Title.TextDecorations = [Windows.TextDecorations]::Strikethrough
    $panel.Tag.Bar.Foreground = $script:Theme.Completed
  } else {
    $panel.Tag.Title.TextDecorations = $null
    if($remaining -ge 0){
      $panel.Tag.TimeText.Text = ("{0} remaining" -f (Format-HMS $remaining))
    } else {
      $panel.Tag.TimeText.Text = ("{0} overdue" -f (Format-HMS $remaining))
    }
    $r = Lerp 0 255 $frac
    $g = Lerp 180 0 $frac
    $panel.Tag.Bar.Foreground = New-Brush $r $g 0
  }
}

function Refresh-List(){
  $itemsPanel.Children.Clear()
  $view = switch($cbFilter.SelectedItem){
    'Active' { $script:Todos | Where-Object { -not $_.done } }
    'Done'   { $script:Todos | Where-Object { $_.done } }
    default  { $script:Todos }
  }
  $view = $view | Sort-Object @{Expression={$_.done}}, @{Expression={$_.dueAt}}, @{Expression={$_.createdAt}}
  if(-not $view -or $view.Count -eq 0){
    $empty = New-Object Windows.Controls.TextBlock
    $empty.Text = 'No todos yet. Add your first above.'
    $empty.Margin = '8'
    $empty.HorizontalAlignment = 'Center'
    $empty.Foreground = $script:Theme.Muted
    $itemsPanel.Children.Add($empty) | Out-Null
    return
  }
  foreach($t in $view){
    $itemsPanel.Children.Add((New-TodoPanel $t)) | Out-Null
  }
}

$cbTheme.Add_SelectionChanged({
  $sel = $cbTheme.SelectedItem.ToString()
  $script:Settings.themeMode = $sel
  Save-Settings $script:Settings
  $script:Theme = Build-Theme (Resolve-Mode $sel)
  Write-Log 'INFO' ("Theme changed to " + $sel)
  $window.Background = $script:Theme.WindowBg
  $window.Foreground = $script:Theme.Text
  $versionText.Foreground = $script:Theme.Muted
  $tbTitle.Background = $script:Theme.PanelBg
  $tbTitle.BorderBrush = $script:Theme.Border
  $tbMins.Background = $script:Theme.PanelBg
  $tbMins.BorderBrush = $script:Theme.Border
  $tbSecs.Background = $script:Theme.PanelBg
  $tbSecs.BorderBrush = $script:Theme.Border
  $btnAdd.Background = $script:Theme.Primary
  $btnAdd.BorderBrush = $script:Theme.PrimaryBorder
  $btnClearDone.Background = $script:Theme.Danger
  $btnClearDone.BorderBrush = $script:Theme.DangerBorder
  foreach($child in $itemsPanel.Children){
    if($child.Tag){
      $child.Background = $script:Theme.PanelBg
      $child.BorderBrush = $script:Theme.Border
      $child.Tag.Due.Foreground = $script:Theme.Muted
      $child.Tag.TimeText.Foreground = $script:Theme.Muted
      $child.Tag.Bar.Background = $script:Theme.BarBg
    }
  }
})

$btnAdd.Add_Click({
  $title = ($tbTitle.Text).Trim()
  if([string]::IsNullOrWhiteSpace($title)){ return }
  $mins = [int]::TryParse($tbMins.Text, [ref]([int]$null)); $mins = [int]$tbMins.Text
  $secs = [int]::TryParse($tbSecs.Text, [ref]([int]$null)); $secs = [int]$tbSecs.Text
  if($mins -lt 0){ $mins = 0 }
  if($secs -lt 0){ $secs = 0 } elseif($secs -gt 59){ $secs = 59 }
  $total = [math]::Max(0, ($mins*60 + $secs)*1000)
  $now = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
  $t = [pscustomobject]@{
    id = ([guid]::NewGuid().ToString('n'))
    title = $title
    totalMs = $total
    createdAt = $now
    dueAt = $now + $total
    done = $false
    doneAt = $null
  }
  $script:Todos += $t
  Save-State $script:Todos
  $tbTitle.Text = ''
  Refresh-List
  Write-Log 'INFO' ("Added todo: " + $title + " (" + $total + " ms)")
})

$cbFilter.Add_SelectionChanged({ Refresh-List })
$btnClearDone.Add_Click({
  $script:Todos = $script:Todos | Where-Object { -not $_.done }
  Save-State $script:Todos
  Refresh-List
  Write-Log 'INFO' 'Cleared completed todos'
})

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(250)
$timer.Add_Tick({
  foreach($child in $itemsPanel.Children){
    if($child.Tag -and $child.Tag.Todo){
      Update-Panel $child
    }
  }
})
$timer.Start()

Refresh-List
try {
  [void]$window.ShowDialog()
} catch {
  $msg = "Unhandled exception: " + $_.Exception.Message
  Write-Log 'ERROR' ($msg + "`n" + $_.ScriptStackTrace)
  try {
    Add-Type -AssemblyName PresentationFramework | Out-Null
    [System.Windows.MessageBox]::Show($msg, 'Todo Timer', 'OK', 'Error') | Out-Null
  } catch {}
}
