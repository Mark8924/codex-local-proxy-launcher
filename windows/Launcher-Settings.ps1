param([switch]$SelfTest)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot "Launcher.Common.ps1")
[Windows.Forms.Application]::EnableVisualStyles()
$chinese = [Globalization.CultureInfo]::CurrentUICulture.Name.StartsWith("zh")
function Get-Label([string]$Chinese, [string]$English) {
    if ($chinese) { return $Chinese }; return $English
}
$config = Import-LauncherConfig $PSScriptRoot
$form = New-Object Windows.Forms.Form
$form.Text = Get-Label "Codex Launcher 设置" "Codex Launcher Settings"
$form.ClientSize = New-Object Drawing.Size(610, 270)
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.StartPosition = "CenterScreen"
$form.AutoScaleMode = "Dpi"
$form.Font = New-Object Drawing.Font("Segoe UI", 10)

function Add-FieldLabel([string]$Title, [int]$Top) {
    $label = New-Object Windows.Forms.Label
    $label.Text = $Title
    $label.Location = New-Object Drawing.Point(20, $Top)
    $label.Size = New-Object Drawing.Size(110, 28)
    $form.Controls.Add($label)
}
function Add-TextField([int]$Top, [string]$Value) {
    $field = New-Object Windows.Forms.TextBox
    $field.Location = New-Object Drawing.Point(130, $Top)
    $field.Size = New-Object Drawing.Size(340, 28)
    $field.Text = $Value
    $form.Controls.Add($field)
    return $field
}
Add-FieldLabel (Get-Label "代理地址" "Proxy host") 25
$hostField = Add-TextField 22 (Get-ConfigValue $config "CODEX_PROXY_HOST" "127.0.0.1")
Add-FieldLabel (Get-Label "端口" "Port") 68
$portField = Add-TextField 65 (Get-ConfigValue $config "CODEX_PROXY_PORT" "10808")
$portField.Width = 130
$schemeField = New-Object Windows.Forms.ComboBox
$schemeField.DropDownStyle = "DropDownList"
$schemeField.Location = New-Object Drawing.Point(280, 65)
$schemeField.Size = New-Object Drawing.Size(190, 28)
$null = $schemeField.Items.AddRange(@("HTTP", "HTTPS"))
$schemeField.SelectedItem = (Get-ConfigValue $config "CODEX_PROXY_SCHEME" "http").ToUpperInvariant()
if ($schemeField.SelectedIndex -lt 0) { $schemeField.SelectedIndex = 0 }
$form.Controls.Add($schemeField)
Add-FieldLabel (Get-Label "桌面应用" "Desktop app") 111
$exeField = Add-TextField 108 (Get-ConfigValue $config "CHATGPT_EXE" (Get-ConfigValue $config "CODEX_EXE" ""))
$browse = New-Object Windows.Forms.Button
$browse.Text = Get-Label "选择…" "Browse…"
$browse.Location = New-Object Drawing.Point(485, 106)
$browse.Size = New-Object Drawing.Size(105, 30)
$browse.Add_Click({
    $dialog = New-Object Windows.Forms.OpenFileDialog
    $dialog.Filter = "Application (*.exe)|*.exe"
    if ($dialog.ShowDialog() -eq "OK") { $exeField.Text = $dialog.FileName }
    $dialog.Dispose()
})
$form.Controls.Add($browse)
$status = New-Object Windows.Forms.Label
$status.Location = New-Object Drawing.Point(20, 208)
$status.Size = New-Object Drawing.Size(570, 52)
$form.Controls.Add($status)

function Get-FormSettings {
    $values = @{
        CODEX_PROXY_HOST = $hostField.Text.Trim()
        CODEX_PROXY_PORT = $portField.Text.Trim()
        CODEX_PROXY_SCHEME = ([string]$schemeField.SelectedItem).ToLowerInvariant()
        CHATGPT_EXE = $exeField.Text.Trim()
    }
    $proxy = Get-LauncherProxy $values ""
    $values.CODEX_PROXY_URL = $proxy.Url
    if ($values.CHATGPT_EXE -and -not (Test-Path -LiteralPath $values.CHATGPT_EXE -PathType Leaf)) {
        throw (Get-Label "桌面应用路径不存在。" "Desktop app path does not exist.")
    }
    return $values
}
function Save-FormSettings {
    try {
        $values = Get-FormSettings
        $path = Get-LauncherSettingsPath
        $directory = Split-Path -Parent $path
        $null = New-Item -ItemType Directory -Path $directory -Force
        $temporary = Join-Path $directory ([Guid]::NewGuid().ToString("N") + ".tmp")
        try {
            [IO.File]::WriteAllText($temporary, ($values | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
            if ([IO.File]::Exists($path)) { [IO.File]::Replace($temporary, $path, $null) }
            else { [IO.File]::Move($temporary, $path) }
        } finally {
            if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
        }
        $status.Text = Get-Label "已保存。下次从原启动器打开时生效。" "Saved. Applies next time you open the original launcher."
        return $true
    } catch {
        $null = [Windows.Forms.MessageBox]::Show($_.Exception.Message, $form.Text, "OK", "Error")
        return $false
    }
}
$save = New-Object Windows.Forms.Button
$save.Text = Get-Label "保存设置" "Save settings"
$save.Location = New-Object Drawing.Point(130, 159)
$save.Size = New-Object Drawing.Size(130, 34)
$save.Add_Click({ $null = Save-FormSettings })
$form.Controls.Add($save)
$test = New-Object Windows.Forms.Button
$test.Text = Get-Label "检测代理" "Test proxy"
$test.Location = New-Object Drawing.Point(280, 159)
$test.Size = New-Object Drawing.Size(130, 34)
$test.Add_Click({
    try {
        $values = Get-FormSettings
        $proxy = Get-LauncherProxy $values ""
        if (Test-LauncherProxy $proxy) { $status.Text = Get-Label "代理端口可连接。" "Proxy port is reachable." }
        else { $status.Text = Get-Label "代理端口不可连接，请检查客户端和端口。" "Proxy port is not reachable. Check your client and port." }
    } catch { $status.Text = $_.Exception.Message }
})
$form.Controls.Add($test)

if ($SelfTest) {
    $hostField.Text = "127.0.0.1"
    $portField.Text = "7890"
    $schemeField.SelectedIndex = 0
    $exeField.Text = ""
    if ((Get-FormSettings).CODEX_PROXY_URL -ne "http://127.0.0.1:7890") { throw "GUI values were not validated correctly" }
    if ($form.Controls.Count -lt 10) { throw "Settings controls were not created" }
    $form.Dispose()
    Write-Host "Windows settings UI checks passed."
    return
}
[Windows.Forms.Application]::Run($form)
$form.Dispose()
