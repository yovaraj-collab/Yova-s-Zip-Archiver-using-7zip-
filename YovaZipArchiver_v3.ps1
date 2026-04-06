#Requires -Version 5.1
<#
.SYNOPSIS
    Yova's ZIP Archiver - Advanced
    Packs files from a source folder into independent ZIP archives,
    each kept within a specified size limit. Requires 7-Zip.
#>


# --- Startup diagnostics / preflight ---
$script:StartupLog = Join-Path $env:TEMP "YovaZipArchiver_startup.log"
try {
    "=== YovaZipArchiver startup $(Get-Date -Format s) ===" | Out-File -FilePath $script:StartupLog -Encoding UTF8 -Force
    "PSVersion=$($PSVersionTable.PSVersion)" | Out-File -FilePath $script:StartupLog -Append -Encoding UTF8
    "PSEdition=$($PSVersionTable.PSEdition)" | Out-File -FilePath $script:StartupLog -Append -Encoding UTF8
    "OS=$([System.Environment]::OSVersion.VersionString)" | Out-File -FilePath $script:StartupLog -Append -Encoding UTF8
} catch {}

if (-not $IsWindows -and $env:OS -ne 'Windows_NT') {
    Write-Error "This script requires Windows because it uses System.Windows.Forms."
    Write-Host  "Startup log: $script:StartupLog"
    exit 1
}

try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    [System.Windows.Forms.Application]::EnableVisualStyles()
} catch {
    Write-Error "Failed to load Windows Forms assemblies. $($_.Exception.Message)"
    Write-Host  "Startup log: $script:StartupLog"
    try {
        [void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')
        [System.Windows.Forms.MessageBox]::Show("Failed to start YovaZipArchiver.`r`n`r`n$($_.Exception.Message)`r`n`r`nStartup log: $script:StartupLog","Startup Error") | Out-Null
    } catch {}
    exit 1
}

# =============================================================================
# COLOURS
# =============================================================================
$clrBg           = [System.Drawing.Color]::FromArgb( 18,  18,  22)
$clrPanel        = [System.Drawing.Color]::FromArgb( 28,  28,  36)
$clrPanel2       = [System.Drawing.Color]::FromArgb( 36,  36,  46)
$clrBorder       = [System.Drawing.Color]::FromArgb( 55,  55,  72)
$clrBlue         = [System.Drawing.Color]::FromArgb( 88, 166, 255)
$clrBlueDark     = [System.Drawing.Color]::FromArgb( 42, 100, 190)
$clrRed          = [System.Drawing.Color]::FromArgb(220,  75,  65)
$clrGreen        = [System.Drawing.Color]::FromArgb( 55, 200,  90)
$clrAmber        = [System.Drawing.Color]::FromArgb(240, 170,  45)
$clrText         = [System.Drawing.Color]::FromArgb(220, 220, 232)
$clrMuted        = [System.Drawing.Color]::FromArgb(118, 118, 140)
$clrLogBg        = [System.Drawing.Color]::FromArgb( 16,  16,  22)
$clrErrBg        = [System.Drawing.Color]::FromArgb( 32,  16,  16)
$clrErrText      = [System.Drawing.Color]::FromArgb(255, 115,  95)
$clrBannerOkBg   = [System.Drawing.Color]::FromArgb( 16,  36,  22)
$clrBannerWarnBg = [System.Drawing.Color]::FromArgb( 36,  26,   8)
$clrHeaderBg     = [System.Drawing.Color]::FromArgb( 32,  32,  44)
$clrInputBg      = [System.Drawing.Color]::FromArgb( 36,  36,  48)
$clrBtnBg        = [System.Drawing.Color]::FromArgb( 44,  44,  58)
$clrBtnBorder    = [System.Drawing.Color]::FromArgb( 68,  68,  88)

# =============================================================================
# FONTS
# =============================================================================
$fntUI      = New-Object System.Drawing.Font("Segoe UI", 9)
$fntBold    = New-Object System.Drawing.Font("Segoe UI", 9,  [System.Drawing.FontStyle]::Bold)
$fntMono    = New-Object System.Drawing.Font("Consolas", 8)
$fntTitle   = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
$fntSub     = New-Object System.Drawing.Font("Segoe UI", 8)
$fntSection = New-Object System.Drawing.Font("Segoe UI", 8,  [System.Drawing.FontStyle]::Bold)

# =============================================================================
# CONTROL FACTORY HELPERS
# =============================================================================
function New-Lbl($text, $x, $y, $w=150, $h=22) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text      = $text
    $l.Location  = [System.Drawing.Point]::new($x, $y)
    $l.Size      = [System.Drawing.Size]::new($w, $h)
    $l.Font      = $fntBold
    $l.ForeColor = $clrText
    $l.BackColor = [System.Drawing.Color]::Transparent
    $l.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    return $l
}

function New-MutedLbl($text, $x, $y, $w=260, $h=22) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text      = $text
    $l.Location  = [System.Drawing.Point]::new($x, $y)
    $l.Size      = [System.Drawing.Size]::new($w, $h)
    $l.Font      = $fntSub
    $l.ForeColor = $clrMuted
    $l.BackColor = [System.Drawing.Color]::Transparent
    $l.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    return $l
}

function New-SecLbl($text, $x, $y, $w=700) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text      = $text
    $l.Location  = [System.Drawing.Point]::new($x, $y)
    $l.Size      = [System.Drawing.Size]::new($w, 18)
    $l.Font      = $fntSection
    $l.ForeColor = $clrBlue
    $l.BackColor = [System.Drawing.Color]::Transparent
    return $l
}

function New-HSep($x, $y, $w=700) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Location  = [System.Drawing.Point]::new($x, $y)
    $p.Size      = [System.Drawing.Size]::new($w, 1)
    $p.BackColor = $clrBorder
    return $p
}

function New-TB($x, $y, $w=380, $h=23) {
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location    = [System.Drawing.Point]::new($x, $y)
    $t.Size        = [System.Drawing.Size]::new($w, $h)
    $t.Font        = $fntUI
    $t.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $t.BackColor   = $clrInputBg
    $t.ForeColor   = $clrText
    return $t
}

function New-Btn($text, $x, $y, $w=88, $h=26) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text      = $text
    $b.Location  = [System.Drawing.Point]::new($x, $y)
    $b.Size      = [System.Drawing.Size]::new($w, $h)
    $b.Font      = $fntUI
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderColor = $clrBtnBorder
    $b.BackColor = $clrBtnBg
    $b.ForeColor = $clrText
    $b.Cursor    = [System.Windows.Forms.Cursors]::Hand
    return $b
}

function New-PrimaryBtn($text, $x, $y, $w=140, $h=28) {
    $b = New-Btn $text $x $y $w $h
    $b.BackColor = $clrBlueDark
    $b.ForeColor = [System.Drawing.Color]::White
    $b.Font      = $fntBold
    $b.FlatAppearance.BorderColor = $clrBlue
    return $b
}

function New-DangerBtn($text, $x, $y, $w=100, $h=28) {
    $b = New-Btn $text $x $y $w $h
    $b.BackColor = [System.Drawing.Color]::FromArgb(88, 28, 26)
    $b.ForeColor = [System.Drawing.Color]::FromArgb(255, 155, 135)
    $b.Font      = $fntBold
    $b.FlatAppearance.BorderColor = $clrRed
    return $b
}

function New-ChkBox($text, $x, $y, $w=180, $checked=$false) {
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text      = $text
    $c.Checked   = $checked
    $c.Location  = [System.Drawing.Point]::new($x, $y)
    $c.Size      = [System.Drawing.Size]::new($w, 22)
    $c.Font      = $fntUI
    $c.ForeColor = $clrText
    $c.BackColor = [System.Drawing.Color]::Transparent
    return $c
}

function New-CardPanel($h) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock        = [System.Windows.Forms.DockStyle]::Fill
    $p.BackColor   = $clrPanel
    $p.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $p.Margin      = [System.Windows.Forms.Padding]::new(0, 0, 0, 4)
    if ($h -gt 0) { $p.Height = $h }
    return $p
}

# Wire drag-and-drop onto a TextBox
function Wire-Drop($tb) {
    $tb.AllowDrop = $true
    $tb.Add_DragEnter({
        param($s,$e)
        if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
            $e.Effect = [System.Windows.Forms.DragDropEffects]::Copy
        } else { $e.Effect = [System.Windows.Forms.DragDropEffects]::None }
    })
    $tb.Add_DragDrop({
        param($s,$e)
        $items = $e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
        if ($items -and $items.Count -gt 0) {
            $p = $items[0]
            $s.Text = if (Test-Path $p -PathType Container) { $p } else { Split-Path $p -Parent }
        }
    })
}

# =============================================================================
# MAIN FORM
# =============================================================================
$form               = New-Object System.Windows.Forms.Form
$form.Text          = "Yova's ZIP Archiver"
$form.BackColor     = $clrBg
$form.Font          = $fntUI
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.AllowDrop     = $true

$wa    = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$formW = [Math]::Min(800, $wa.Width)
$formH = $wa.Height
$form.Size     = [System.Drawing.Size]::new($formW, $formH)
$form.Location = [System.Drawing.Point]::new(
    $wa.Left + [int](($wa.Width - $formW) / 2), $wa.Top)
$form.MinimumSize = [System.Drawing.Size]::new(760, 620)

# =============================================================================
# ROOT TABLE LAYOUT  (7 rows)
# =============================================================================
$root = New-Object System.Windows.Forms.TableLayoutPanel
$root.Dock        = [System.Windows.Forms.DockStyle]::Fill
$root.ColumnCount = 1
$root.RowCount    = 7
$root.BackColor   = $clrBg
$root.Padding     = [System.Windows.Forms.Padding]::new(10, 6, 10, 6)
$root.CellBorderStyle = [System.Windows.Forms.TableLayoutPanelCellBorderStyle]::None
$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,  52))) | Out-Null  # 0 title
$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,  42))) | Out-Null  # 1 banner
$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 140))) | Out-Null  # 2 paths
$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 204))) | Out-Null  # 3 settings
$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,  96))) | Out-Null  # 4 run+summary
$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,   60))) | Out-Null  # 5 log
$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,   40))) | Out-Null  # 6 errors
$root.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
$form.Controls.Add($root)

$PAD = 10

# =============================================================================
# ROW 0 - TITLE
# =============================================================================
$pnlTitle           = New-Object System.Windows.Forms.Panel
$pnlTitle.Dock      = [System.Windows.Forms.DockStyle]::Fill
$pnlTitle.BackColor = $clrBg
$pnlTitle.Margin    = [System.Windows.Forms.Padding]::new(0,2,0,2)
$root.Controls.Add($pnlTitle, 0, 0)

$lblTitle           = New-Object System.Windows.Forms.Label
$lblTitle.Text      = "Yova's ZIP Archiver"
$lblTitle.Font      = $fntTitle
$lblTitle.ForeColor = $clrBlue
$lblTitle.BackColor = [System.Drawing.Color]::Transparent
$lblTitle.Location  = [System.Drawing.Point]::new(2, 2)
$lblTitle.AutoSize  = $true
$pnlTitle.Controls.Add($lblTitle)

$lblSub           = New-Object System.Windows.Forms.Label
$lblSub.Text      = "Creates independent ZIP archives each within a size limit  -  Drag & drop folders onto any path field"
$lblSub.Font      = $fntSub
$lblSub.ForeColor = $clrMuted
$lblSub.BackColor = [System.Drawing.Color]::Transparent
$lblSub.Location  = [System.Drawing.Point]::new(2, 30)
$lblSub.AutoSize  = $true
$pnlTitle.Controls.Add($lblSub)

# =============================================================================
# ROW 1 - 7-ZIP BANNER
# =============================================================================
$pnlBanner             = New-Object System.Windows.Forms.Panel
$pnlBanner.Dock        = [System.Windows.Forms.DockStyle]::Fill
$pnlBanner.BackColor   = $clrBannerOkBg
$pnlBanner.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$pnlBanner.Margin      = [System.Windows.Forms.Padding]::new(0, 0, 0, 4)
$root.Controls.Add($pnlBanner, 0, 1)

$lblBannerIcon          = New-Object System.Windows.Forms.Label
$lblBannerIcon.Location = [System.Drawing.Point]::new(8, 5)
$lblBannerIcon.Size     = [System.Drawing.Size]::new(28, 30)
$lblBannerIcon.Font     = New-Object System.Drawing.Font("Segoe UI", 13)
$lblBannerIcon.BackColor= [System.Drawing.Color]::Transparent
$pnlBanner.Controls.Add($lblBannerIcon)

$lblBannerHead          = New-Object System.Windows.Forms.Label
$lblBannerHead.Location = [System.Drawing.Point]::new(42, 4)
$lblBannerHead.Size     = [System.Drawing.Size]::new(600, 17)
$lblBannerHead.Font     = $fntBold
$lblBannerHead.BackColor= [System.Drawing.Color]::Transparent
$pnlBanner.Controls.Add($lblBannerHead)

$lblBannerDetail          = New-Object System.Windows.Forms.Label
$lblBannerDetail.Location = [System.Drawing.Point]::new(42, 21)
$lblBannerDetail.Size     = [System.Drawing.Size]::new(600, 16)
$lblBannerDetail.Font     = $fntSub
$lblBannerDetail.BackColor= [System.Drawing.Color]::Transparent
$pnlBanner.Controls.Add($lblBannerDetail)

$lnkBanner          = New-Object System.Windows.Forms.LinkLabel
$lnkBanner.Location = [System.Drawing.Point]::new(42, 21)
$lnkBanner.Size     = [System.Drawing.Size]::new(420, 16)
$lnkBanner.Font     = $fntSub
$lnkBanner.Text     = "Click here to download 7-Zip from the official website"
$lnkBanner.LinkColor= $clrBlue
$lnkBanner.BackColor= [System.Drawing.Color]::Transparent
$lnkBanner.Visible  = $false
$lnkBanner.Add_LinkClicked({ Start-Process "https://www.7-zip.org/download.html" })
$pnlBanner.Controls.Add($lnkBanner)

# =============================================================================
# ROW 2 - FOLDERS AND PATHS
# =============================================================================
$pnlPaths = New-CardPanel 140
$root.Controls.Add($pnlPaths, 0, 2)

$ry2 = 6
$pnlPaths.Controls.Add((New-SecLbl "FOLDERS AND PATHS  - drag & drop a folder onto any field" $PAD $ry2))
$ry2 += 18 ; $pnlPaths.Controls.Add((New-HSep $PAD $ry2)) ; $ry2 += 6

$pnlPaths.Controls.Add((New-Lbl "Source folder:" $PAD $ry2 148))
$txtSource = New-TB 160 $ry2 428 23
Wire-Drop $txtSource
$pnlPaths.Controls.Add($txtSource)
$btnBrowseSrc = New-Btn "Browse..." 594 ($ry2-1) 82 25
$pnlPaths.Controls.Add($btnBrowseSrc)
$ry2 += 28

$pnlPaths.Controls.Add((New-Lbl "Output folder:" $PAD $ry2 148))
$txtOutput = New-TB 160 $ry2 428 23
Wire-Drop $txtOutput
$pnlPaths.Controls.Add($txtOutput)
$btnBrowseOut = New-Btn "Browse..." 594 ($ry2-1) 82 25
$pnlPaths.Controls.Add($btnBrowseOut)
$ry2 += 28

$lbl7ZipDot           = New-Object System.Windows.Forms.Label
$lbl7ZipDot.Text      = "*"
$lbl7ZipDot.ForeColor = $clrMuted
$lbl7ZipDot.BackColor = [System.Drawing.Color]::Transparent
$lbl7ZipDot.Location  = [System.Drawing.Point]::new($PAD, $ry2)
$lbl7ZipDot.Size      = [System.Drawing.Size]::new(14, 22)
$lbl7ZipDot.Font      = New-Object System.Drawing.Font("Segoe UI", 7)
$lbl7ZipDot.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$pnlPaths.Controls.Add($lbl7ZipDot)

$pnlPaths.Controls.Add((New-Lbl "7-Zip (7z.exe) path:" 26 $ry2 132))
$txt7Zip = New-TB 160 $ry2 428 23
$pnlPaths.Controls.Add($txt7Zip)
$btnBrowse7Z = New-Btn "Browse..." 594 ($ry2-1) 82 25
$pnlPaths.Controls.Add($btnBrowse7Z)
$ry2 += 28

$btnReDetect = New-Btn "Re-Detect 7-Zip" 160 $ry2 118 24
$pnlPaths.Controls.Add($btnReDetect)

# =============================================================================
# ROW 3 - ARCHIVE SETTINGS
# =============================================================================
$pnlSettings = New-CardPanel 232
$root.Controls.Add($pnlSettings, 0, 3)

$ry3 = 6
$pnlSettings.Controls.Add((New-SecLbl "ARCHIVE SETTINGS" $PAD $ry3))
$ry3 += 18 ; $pnlSettings.Controls.Add((New-HSep $PAD $ry3)) ; $ry3 += 6

$pnlSettings.Controls.Add((New-Lbl "Base archive name:" $PAD $ry3 148))
$txtBaseName = New-TB 160 $ry3 148 23
$pnlSettings.Controls.Add($txtBaseName)

$pnlSettings.Controls.Add((New-Lbl "Max ZIP size (MB):" 320 $ry3 132))
$txtMaxMB = New-TB 454 $ry3 68 23
$pnlSettings.Controls.Add($txtMaxMB)

$pnlSettings.Controls.Add((New-Lbl "Reserve (MB):" 534 $ry3 86))
$txtReserveMB = New-TB 622 $ry3 56 23
$pnlSettings.Controls.Add($txtReserveMB)
$ry3 += 30

$pnlSettings.Controls.Add((New-Lbl "Compression:" $PAD $ry3 120))
$txtCompression = New-TB 130 $ry3 46 23
$pnlSettings.Controls.Add($txtCompression)
$pnlSettings.Controls.Add((New-MutedLbl "0=store - 5=normal - 9=ultra" 184 $ry3 200))

$pnlSettings.Controls.Add((New-Lbl "Sort order:" 396 $ry3 84))
$cboSort = New-Object System.Windows.Forms.ComboBox
$cboSort.Location      = [System.Drawing.Point]::new(482, $ry3)
$cboSort.Size          = [System.Drawing.Size]::new(196, 23)
$cboSort.Font          = $fntUI
$cboSort.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cboSort.BackColor     = $clrInputBg
$cboSort.ForeColor     = $clrText
[void]$cboSort.Items.AddRange(@("By name (A to Z)", "Largest files first", "Smallest files first"))
$cboSort.SelectedIndex = 0
$pnlSettings.Controls.Add($cboSort)
$ry3 += 30

$chkRecurse       = New-ChkBox "Include subfolders"         $PAD $ry3 160 $true
$chkPreservePaths = New-ChkBox "Preserve folder structure"  172  $ry3 190 $true
$chkCreateReport  = New-ChkBox "Create CSV report"          366  $ry3 150 $true
$chkOpenOutput    = New-ChkBox "Open output when done"      520  $ry3 178 $false
$pnlSettings.Controls.Add($chkRecurse)
$pnlSettings.Controls.Add($chkPreservePaths)
$pnlSettings.Controls.Add($chkCreateReport)
$pnlSettings.Controls.Add($chkOpenOutput)
$ry3 += 30

$pnlSettings.Controls.Add((New-Lbl "ZIP password:" $PAD $ry3 120))
$txtPassword = New-TB 130 $ry3 220 23
$txtPassword.UseSystemPasswordChar = $true
$pnlSettings.Controls.Add($txtPassword)

$chkShowPassword = New-ChkBox "Show password" 360 $ry3 120 $false
$chkShowPassword.Add_CheckedChanged({
    $txtPassword.UseSystemPasswordChar = -not $chkShowPassword.Checked
})
$pnlSettings.Controls.Add($chkShowPassword)

$chkEncryptZip = New-ChkBox "Encrypt ZIP with AES-256" 490 $ry3 190 $true
$pnlSettings.Controls.Add($chkEncryptZip)
$ry3 += 26

$chkSplitVolumes = New-ChkBox "Enable split volumes for oversized single files" $PAD $ry3 310 $false
$pnlSettings.Controls.Add($chkSplitVolumes)
$ry3 += 24

$pnlSettings.Controls.Add((New-MutedLbl "Leave password blank to create a normal ZIP without encryption. AES-256 password protection uses 7-Zip ZIP encryption." $PAD $ry3 680 18))
$ry3 += 20

$pnlSettings.Controls.Add((New-MutedLbl "Preserve folder structure stores files with relative paths inside each ZIP (e.g. SubFolder\file.txt). Split volumes are only used when one file cannot fit into the effective size limit by itself." $PAD $ry3 680 18))
$ry3 += 20

$pnlSettings.Controls.Add((New-MutedLbl "Split-volume archives require all parts to extract correctly. They are not independently openable like the normal grouped ZIPs created by this tool." $PAD $ry3 680 18))

# =============================================================================
# ROW 4 - RUN CONTROLS + SUMMARY
# =============================================================================
$pnlRow4 = New-Object System.Windows.Forms.Panel
$pnlRow4.Dock      = [System.Windows.Forms.DockStyle]::Fill
$pnlRow4.BackColor = $clrBg
$pnlRow4.Margin    = [System.Windows.Forms.Padding]::new(0,0,0,4)
$root.Controls.Add($pnlRow4, 0, 4)

# Left: Run controls
$pnlRun             = New-Object System.Windows.Forms.Panel
$pnlRun.BackColor   = $clrPanel
$pnlRun.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$pnlRun.Location    = [System.Drawing.Point]::new(0, 0)
$pnlRun.Size        = [System.Drawing.Size]::new(330, 92)
$pnlRow4.Controls.Add($pnlRun)

$ry4 = 5
$pnlRun.Controls.Add((New-SecLbl "RUN" $PAD $ry4 290))
$ry4 += 18 ; $pnlRun.Controls.Add((New-HSep $PAD $ry4 308)) ; $ry4 += 8

$btnStart  = New-PrimaryBtn ">  Start Archiving" $PAD $ry4 148 28
$btnCancel = New-DangerBtn  "X  Cancel"          164  $ry4 100 28
$btnCancel.Enabled = $false
$pnlRun.Controls.Add($btnStart)
$pnlRun.Controls.Add($btnCancel)
$ry4 += 34

$pnlRun.Controls.Add((New-Lbl "Status:" $PAD ($ry4+1) 56 20))
$lblStatus           = New-Object System.Windows.Forms.Label
$lblStatus.Text      = "Ready."
$lblStatus.Font      = $fntUI
$lblStatus.ForeColor = $clrMuted
$lblStatus.BackColor = [System.Drawing.Color]::Transparent
$lblStatus.Location  = [System.Drawing.Point]::new(68, ($ry4+1))
$lblStatus.Size      = [System.Drawing.Size]::new(255, 20)
$pnlRun.Controls.Add($lblStatus)
$ry4 += 20

$pnlRun.Controls.Add((New-Lbl "Progress:" $PAD ($ry4+1) 64 18))
$progressBar          = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = [System.Drawing.Point]::new(76, ($ry4+1))
$progressBar.Size     = [System.Drawing.Size]::new(204, 16)
$progressBar.Minimum  = 0
$progressBar.Maximum  = 100
$progressBar.Style    = [System.Windows.Forms.ProgressBarStyle]::Continuous
$pnlRun.Controls.Add($progressBar)

$lblPct           = New-Object System.Windows.Forms.Label
$lblPct.Text      = "0%"
$lblPct.Font      = $fntBold
$lblPct.ForeColor = $clrText
$lblPct.BackColor = [System.Drawing.Color]::Transparent
$lblPct.Location  = [System.Drawing.Point]::new(284, ($ry4+1))
$lblPct.Size      = [System.Drawing.Size]::new(38, 18)
$pnlRun.Controls.Add($lblPct)

# Right: Summary
$pnlSummary             = New-Object System.Windows.Forms.Panel
$pnlSummary.BackColor   = $clrPanel
$pnlSummary.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$pnlSummary.Location    = [System.Drawing.Point]::new(336, 0)
$pnlSummary.Size        = [System.Drawing.Size]::new(200, 92)
$pnlRow4.Controls.Add($pnlSummary)

$ry4s = 5
$pnlSummary.Controls.Add((New-SecLbl "RUN SUMMARY" $PAD $ry4s))
$ry4s += 18 ; $pnlSummary.Controls.Add((New-HSep $PAD $ry4s 180)) ; $ry4s += 6

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location                         = [System.Drawing.Point]::new($PAD, $ry4s)
$grid.Size                             = [System.Drawing.Size]::new(180, 56)
$grid.Font                             = $fntUI
$grid.AllowUserToAddRows               = $false
$grid.AllowUserToDeleteRows            = $false
$grid.ReadOnly                         = $true
$grid.RowHeadersVisible                = $false
$grid.BackgroundColor                  = $clrPanel
$grid.GridColor                        = $clrBorder
$grid.BorderStyle                      = [System.Windows.Forms.BorderStyle]::None
$grid.ScrollBars                       = [System.Windows.Forms.ScrollBars]::None
$grid.SelectionMode                    = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$grid.AutoSizeColumnsMode              = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
$grid.ColumnHeadersDefaultCellStyle.BackColor = $clrHeaderBg
$grid.ColumnHeadersDefaultCellStyle.ForeColor = $clrBlue
$grid.ColumnHeadersDefaultCellStyle.Font      = $fntBold
$grid.DefaultCellStyle.BackColor              = $clrPanel2
$grid.DefaultCellStyle.ForeColor              = $clrText
$grid.AlternatingRowsDefaultCellStyle.BackColor = $clrPanel
$grid.ColumnHeadersHeight              = 22
foreach ($col in @("Total","Packed","Archives","Too Large","Failed","CSV Report")) {
    [void]$grid.Columns.Add($col, $col)
}
[void]$grid.Rows.Add(@("0","0","0","0","0","-"))
$pnlSummary.Controls.Add($grid)

# Resize: summary panel fills remaining row4 width
$pnlRow4.Add_Resize({
    $pnlRun.Height     = $pnlRow4.Height
    $pnlSummary.Height = $pnlRow4.Height
    $w2 = $pnlRow4.Width - 336
    if ($w2 -lt 100) { $w2 = 100 }
    $pnlSummary.Width = $w2
    $grid.Width       = [Math]::Max(10, $w2 - ($PAD * 2))
    foreach ($ctrl in $pnlSummary.Controls) {
        if ($ctrl -is [System.Windows.Forms.Panel] -and $ctrl.Height -eq 1) {
            $ctrl.Width = [Math]::Max(10, $w2 - ($PAD * 2))
        }
    }
})

# =============================================================================
# ROW 5 - PROCESS LOG
# =============================================================================
$pnlLog             = New-CardPanel 0
$pnlLog.Margin      = [System.Windows.Forms.Padding]::new(0,0,0,4)
$root.Controls.Add($pnlLog, 0, 5)

$pnlLog.Controls.Add((New-SecLbl "PROCESS LOG" $PAD 5))
$pnlLog.Controls.Add((New-HSep $PAD 23))

$logBox             = New-Object System.Windows.Forms.RichTextBox
$logBox.Location    = [System.Drawing.Point]::new($PAD, 28)
$logBox.Font        = $fntMono
$logBox.BackColor   = $clrLogBg
$logBox.ForeColor   = $clrText
$logBox.ReadOnly    = $true
$logBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$logBox.ScrollBars  = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$logBox.Anchor      = [System.Windows.Forms.AnchorStyles]::Top -bor `
                      [System.Windows.Forms.AnchorStyles]::Bottom -bor `
                      [System.Windows.Forms.AnchorStyles]::Left -bor `
                      [System.Windows.Forms.AnchorStyles]::Right
$pnlLog.Controls.Add($logBox)
$pnlLog.Add_Resize({ $logBox.Size = [System.Drawing.Size]::new([Math]::Max(10,$pnlLog.Width-($PAD*2)-2), [Math]::Max(10,$pnlLog.Height-32)) })

# =============================================================================
# ROW 6 - ERRORS / WARNINGS
# =============================================================================
$pnlErrors             = New-CardPanel 0
$pnlErrors.Margin      = [System.Windows.Forms.Padding]::new(0,0,0,0)
$root.Controls.Add($pnlErrors, 0, 6)

$pnlErrors.Controls.Add((New-SecLbl "FILES THAT COULD NOT FIT OR FAILED" $PAD 5))
$pnlErrors.Controls.Add((New-HSep $PAD 23))

$errorBox             = New-Object System.Windows.Forms.RichTextBox
$errorBox.Location    = [System.Drawing.Point]::new($PAD, 28)
$errorBox.Font        = $fntMono
$errorBox.BackColor   = $clrErrBg
$errorBox.ForeColor   = $clrErrText
$errorBox.ReadOnly    = $true
$errorBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$errorBox.ScrollBars  = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$errorBox.Anchor      = [System.Windows.Forms.AnchorStyles]::Top -bor `
                        [System.Windows.Forms.AnchorStyles]::Bottom -bor `
                        [System.Windows.Forms.AnchorStyles]::Left -bor `
                        [System.Windows.Forms.AnchorStyles]::Right
$pnlErrors.Controls.Add($errorBox)
$pnlErrors.Add_Resize({ $errorBox.Size = [System.Drawing.Size]::new([Math]::Max(10,$pnlErrors.Width-($PAD*2)-2), [Math]::Max(10,$pnlErrors.Height-32)) })

# =============================================================================
# DEFAULTS
# =============================================================================
$txtBaseName.Text    = "Archive"
$txtMaxMB.Text       = "100"
$txtReserveMB.Text   = "1"
$txtCompression.Text = "9"

# =============================================================================
# STATE
# =============================================================================
$script:stopRequested = $false

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================
function Append-Log($msg) {
    $logBox.AppendText("$msg`r`n")
    $logBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-Progress($pct) {
    $pct = [Math]::Max(0, [Math]::Min(100, $pct))
    $progressBar.Value = $pct
    $lblPct.Text       = "$pct%"
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-Summary($total,$packed,$archives,$toolarge,$failed,$report) {
    $grid.Rows[0].SetValues(@($total,$packed,$archives,$toolarge,$failed,$report))
}

function Set-Status($msg, $color=$clrMuted) {
    $lblStatus.Text      = $msg
    $lblStatus.ForeColor = $color
    [System.Windows.Forms.Application]::DoEvents()
}

function Invoke-7ZipAdd($exePath, $archivePath, $itemPath, $compressionLevel, $password, $useAes256) {
    $args = @("a", "-tzip", "-y", "-mx=$compressionLevel")
    if (-not [string]::IsNullOrWhiteSpace($password)) {
        $args += "-p$password"
        if ($useAes256) { $args += "-mem=AES256" }
    }
    $args += @($archivePath, $itemPath)
    $null = & $exePath @args 2>&1
    return $LASTEXITCODE
}

function Invoke-7ZipDelete($exePath, $archivePath, $itemPath, $password) {
    $args = @("d", "-y")
    if (-not [string]::IsNullOrWhiteSpace($password)) {
        $args += "-p$password"
    }
    $args += @($archivePath, $itemPath)
    $null = & $exePath @args 2>&1
    return $LASTEXITCODE
}

function Invoke-7ZipAddSplit($exePath, $archivePath, $itemPath, $compressionLevel, $password, $useAes256, $volumeBytes) {
    $args = @("a", "-tzip", "-y", "-mx=$compressionLevel", ("-v{0}b" -f $volumeBytes))
    if (-not [string]::IsNullOrWhiteSpace($password)) {
        $args += "-p$password"
        if ($useAes256) { $args += "-mem=AES256" }
    }
    $args += @($archivePath, $itemPath)
    $null = & $exePath @args 2>&1
    return $LASTEXITCODE
}

function Get-SplitArchiveBytes($archivePath) {
    $dir = Split-Path $archivePath -Parent
    $name = Split-Path $archivePath -Leaf
    $sum = 0
    foreach ($f in @(Get-ChildItem -Path $dir -File -EA SilentlyContinue | Where-Object { $_.Name -eq $name -or $_.Name -like ($name + ".*") })) {
        $sum += $f.Length
    }
    return [int64]$sum
}

function Toggle-Buttons($running) {
    $btnStart.Enabled  = -not $running
    $btnCancel.Enabled = $running
}

function Format-Bytes($b) {
    $b = [long]$b
    if     ($b -lt 1KB) { return "$b B" }
    elseif ($b -lt 1MB) { return "{0:N2} KB" -f ($b/1KB) }
    elseif ($b -lt 1GB) { return "{0:N2} MB" -f ($b/1MB) }
    else                { return "{0:N2} GB" -f ($b/1GB) }
}

function CsvEsc($v)  { '"' + ([string]$v).Replace('"','""') + '"' }
function CsvRow($status,$rel,$srcB,$arch,$archB,$notes) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    return "$(CsvEsc $ts),$(CsvEsc $status),$(CsvEsc $rel),$(CsvEsc $srcB),$(CsvEsc $arch),$(CsvEsc $archB),$(CsvEsc $notes)"
}

function Build-ArchivePath($outDir,$base,$idx) {
    return Join-Path $outDir ("{0}_{1:D3}.zip" -f $base,$idx)
}

function Count-Archives($outDir,$base) {
    # Count distinct logical archives: each "Base_NNN.zip" (and any split parts
    # "Base_NNN.zip.001" etc.) counts as ONE archive, not one per part file.
    $files = @(Get-ChildItem -Path $outDir -File -EA SilentlyContinue |
               Where-Object { $_.Name -like "${base}_*.zip" -or $_.Name -like "${base}_*.zip.*" })
    $distinct = $files | ForEach-Object {
        if ($_.Name -match '^(.+\.zip)\.\d+$') { $Matches[1] } else { $_.Name }
    } | Sort-Object -Unique
    return $distinct.Count
}

# =============================================================================
# 7-ZIP DETECTION
# =============================================================================
function Find-7Zip {
    $candidates = @(
        "C:\Program Files\7-Zip\7z.exe",
        "C:\Program Files (x86)\7-Zip\7z.exe",
        "$env:ProgramW6432\7-Zip\7z.exe",
        "$env:LOCALAPPDATA\Programs\7-Zip\7z.exe"
    )
    foreach ($p in $candidates) {
        if ($p -and (Test-Path $p -PathType Leaf)) { return $p }
    }
    foreach ($rp in @("HKLM:\SOFTWARE\7-Zip","HKLM:\SOFTWARE\WOW6432Node\7-Zip")) {
        try {
            $v = Get-ItemProperty $rp -EA Stop
            foreach ($prop in @("Path64","Path")) {
                if ($v.$prop) {
                    $c = Join-Path $v.$prop "7z.exe"
                    if (Test-Path $c -PathType Leaf) { return $c }
                }
            }
        } catch {}
    }
    try {
        $w = where.exe 7z.exe 2>$null
        if ($w -and (Test-Path $w[0] -PathType Leaf)) { return $w[0] }
    } catch {}
    return $null
}

function Get-7ZipVersion($path) {
    try {
        foreach ($line in (& $path i 2>&1 | Select-Object -First 6)) {
            if ($line -match "7-Zip") { return $line.Trim() }
        }
    } catch {}
    return ""
}

function Show-BannerOK($path) {
    $ver = Get-7ZipVersion $path
    $pnlBanner.BackColor       = $clrBannerOkBg
    $lblBannerIcon.Text        = "v"
    $lblBannerIcon.ForeColor   = $clrGreen
    $lblBannerHead.Text        = "7-Zip detected"
    $lblBannerHead.ForeColor   = $clrGreen
    $detail = "Path: $path"
    if ($ver) { $detail += "   -   $ver" }
    $lblBannerDetail.Text      = $detail
    $lblBannerDetail.ForeColor = $clrText
    $lblBannerDetail.Visible   = $true
    $lnkBanner.Visible         = $false
    $lbl7ZipDot.ForeColor      = $clrGreen
}

function Show-BannerWarn {
    $pnlBanner.BackColor       = $clrBannerWarnBg
    $lblBannerIcon.Text        = "!"
    $lblBannerIcon.ForeColor   = $clrAmber
    $lblBannerHead.Text        = "7-Zip not found - browse to 7z.exe or install 7-Zip"
    $lblBannerHead.ForeColor   = $clrAmber
    $lblBannerDetail.Visible   = $false
    $lnkBanner.Visible         = $true
    $lbl7ZipDot.ForeColor      = $clrRed
}

function Invoke-Detect7Zip {
    $found = Find-7Zip
    if ($found) { $txt7Zip.Text = $found ; Show-BannerOK $found }
    else        { $txt7Zip.Text = ""     ; Show-BannerWarn       }
}

# =============================================================================
# BROWSE HANDLERS
# =============================================================================
$btnBrowseSrc.Add_Click({
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = "Select source folder" ; $d.ShowNewFolderButton = $false
    if ($d.ShowDialog() -eq "OK") { $txtSource.Text = $d.SelectedPath }
})

$btnBrowseOut.Add_Click({
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = "Select output folder" ; $d.ShowNewFolderButton = $true
    if ($d.ShowDialog() -eq "OK") { $txtOutput.Text = $d.SelectedPath }
})

$btnBrowse7Z.Add_Click({
    $d = New-Object System.Windows.Forms.OpenFileDialog
    $d.Title = "Select 7z.exe"
    $d.Filter = "7z.exe|7z.exe|Executables (*.exe)|*.exe|All files (*.*)|*.*"
    $d.InitialDirectory = "C:\Program Files\7-Zip"
    if ($d.ShowDialog() -eq "OK") {
        $txt7Zip.Text = $d.FileName
        if (Test-Path $d.FileName -PathType Leaf) { Show-BannerOK $d.FileName } else { Show-BannerWarn }
    }
})

$btnReDetect.Add_Click({ Invoke-Detect7Zip })

# Form-level drag-and-drop
$form.Add_DragEnter({
    param($s,$e)
    if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
        $e.Effect = [System.Windows.Forms.DragDropEffects]::Copy
    } else { $e.Effect = [System.Windows.Forms.DragDropEffects]::None }
})
$form.Add_DragDrop({
    param($s,$e)
    $items = $e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
    if ($items -and $items.Count -gt 0) {
        $p = $items[0]
        $folder = if (Test-Path $p -PathType Container) { $p } else { Split-Path $p -Parent }
        if ([string]::IsNullOrWhiteSpace($txtSource.Text))      { $txtSource.Text = $folder }
        elseif ([string]::IsNullOrWhiteSpace($txtOutput.Text))  { $txtOutput.Text = $folder }
        else                                                     { $txtSource.Text = $folder }
    }
})

# =============================================================================
# CANCEL
# =============================================================================
$btnCancel.Add_Click({
    $script:stopRequested = $true
    Set-Status "Cancellation requested..." $clrAmber
    Append-Log "Cancellation requested - stopping after current file..."
})

# =============================================================================
# START - ARCHIVING LOGIC
# =============================================================================
$btnStart.Add_Click({

    $srcFolder     = $txtSource.Text.Trim()
    $outFolder     = $txtOutput.Text.Trim()
    $szPath        = $txt7Zip.Text.Trim()
    $baseName      = $txtBaseName.Text.Trim()
    $maxMBStr      = $txtMaxMB.Text.Trim()
    $compStr       = $txtCompression.Text.Trim()
    $resMBStr      = $txtReserveMB.Text.Trim()
    $recurse       = $chkRecurse.Checked
    $keepPaths     = $chkPreservePaths.Checked
    $makeReport    = $chkCreateReport.Checked
    $openWhenDone  = $chkOpenOutput.Checked
    $sortMode      = switch ($cboSort.SelectedIndex) { 1 {"largest"} 2 {"smallest"} default {"name"} }
    $zipPassword   = $txtPassword.Text
    $useAes256     = $chkEncryptZip.Checked
    $splitMode     = $chkSplitVolumes.Checked

    if (-not $srcFolder -or -not $outFolder -or -not $szPath -or -not $baseName) {
        [System.Windows.Forms.MessageBox]::Show("Please fill in Source folder, Output folder, 7-Zip path, and Base archive name.","Validation","OK","Exclamation") | Out-Null ; return
    }
    $maxMB = 0.0
    if (-not [double]::TryParse($maxMBStr,[ref]$maxMB) -or $maxMB -le 0) {
        [System.Windows.Forms.MessageBox]::Show("Max ZIP size must be a positive number.","Validation","OK","Exclamation") | Out-Null ; return
    }
    $compLvl = 0
    if (-not [int]::TryParse($compStr,[ref]$compLvl) -or $compLvl -lt 0 -or $compLvl -gt 9) {
        [System.Windows.Forms.MessageBox]::Show("Compression level must be 0-9.","Validation","OK","Exclamation") | Out-Null ; return
    }
    $resMB = 0.0
    if ($resMBStr -eq "") { $resMBStr = "0" }
    if (-not [double]::TryParse($resMBStr,[ref]$resMB) -or $resMB -lt 0) {
        [System.Windows.Forms.MessageBox]::Show("Safety reserve must be 0 or positive.","Validation","OK","Exclamation") | Out-Null ; return
    }
    if (-not (Test-Path $srcFolder -PathType Container)) {
        [System.Windows.Forms.MessageBox]::Show("Source folder does not exist.","Validation","OK","Exclamation") | Out-Null ; return
    }
    if (-not (Test-Path $outFolder -PathType Container)) {
        [System.Windows.Forms.MessageBox]::Show("Output folder does not exist.","Validation","OK","Exclamation") | Out-Null ; return
    }
    if (-not (Test-Path $szPath -PathType Leaf)) {
        $ans = [System.Windows.Forms.MessageBox]::Show("7z.exe not found.`r`n`r`nOpen download page?","7-Zip Not Found","YesNo","Exclamation")
        if ($ans -eq "Yes") { Start-Process "https://www.7-zip.org/download.html" }
        return
    }

    $maxBytes = [long]($maxMB * 1MB)
    $resBytes = [long]($resMB * 1MB)
    $effMax   = $maxBytes - $resBytes
    if ($effMax -le 0) {
        [System.Windows.Forms.MessageBox]::Show("Safety reserve must be smaller than the max ZIP size.","Validation","OK","Exclamation") | Out-Null ; return
    }

    $script:stopRequested = $false
    $logBox.Clear()
    $errorBox.Clear()
    Set-Status "Collecting files..." $clrBlue
    Set-Progress 0
    Set-Summary 0 0 0 0 0 "-"
    Toggle-Buttons $true

    $tooLargeList = [System.Collections.Generic.List[string]]::new()
    $failedList   = [System.Collections.Generic.List[string]]::new()
    $reportLines  = [System.Collections.Generic.List[string]]::new()
    $reportLines.Add("Timestamp,Status,Relative Path,Source Bytes,Archive Name,Archive Bytes,Notes")
    $tooLargeCnt  = 0

    Append-Log "Source : $srcFolder"
    Append-Log "Output : $outFolder"

    $gcArgs = @{ Path=$srcFolder; File=$true; ErrorAction="SilentlyContinue" }
    if ($recurse) { $gcArgs.Recurse = $true }
    $allFiles = @(Get-ChildItem @gcArgs)

    if ($allFiles.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No files found in the source folder.","No Files","OK","Information") | Out-Null
        Set-Status "No files found." $clrAmber ; Toggle-Buttons $false ; return
    }

    $allFiles = switch ($sortMode) {
        "largest"  { $allFiles | Sort-Object Length -Descending }
        "smallest" { $allFiles | Sort-Object Length }
        default    { $allFiles | Sort-Object FullName }
    }

    $total = $allFiles.Count
    Set-Summary $total 0 0 0 0 "-"

    if (-not $splitMode) {
        $oversized = @($allFiles | Where-Object { $_.Length -gt $effMax })
        if ($oversized.Count -gt 0) {
            $preview = @($oversized | Select-Object -First 15 | ForEach-Object {
                $rp = $_.FullName.Substring($srcFolder.Length).TrimStart('\')
                " - {0} ({1})" -f $rp, (Format-Bytes $_.Length)
            })
            $msg = "Some selected files are larger than the effective ZIP limit and cannot fit into a normal independent archive.`r`n`r`nEffective limit: {0}`r`nOversized items: {1}`r`n`r`n{2}" -f (Format-Bytes $effMax), $oversized.Count, ($preview -join "`r`n")
            if ($oversized.Count -gt 15) { $msg += "`r`n ... and more" }
            $msg += "`r`n`r`nPress OK to skip those files and continue, or Cancel to stop.`r`n`r`nTip: enable 'Split volumes for oversized single files' if you want those files written as multi-part ZIP sets."
            $choice = [System.Windows.Forms.MessageBox]::Show($msg, "Oversized Items Detected", [System.Windows.Forms.MessageBoxButtons]::OKCancel, [System.Windows.Forms.MessageBoxIcon]::Warning)
            if ($choice -ne [System.Windows.Forms.DialogResult]::OK) {
                Set-Status "Cancelled before archiving." $clrAmber
                Toggle-Buttons $false
                return
            }
            $skipSet = New-Object 'System.Collections.Generic.HashSet[string]'
            foreach ($o in $oversized) { [void]$skipSet.Add($o.FullName) }
            foreach ($o in $oversized) {
                $rel = $o.FullName.Substring($srcFolder.Length).TrimStart('\')
                $note = ("Skipped before archiving - source size exceeds effective limit ({0})" -f (Format-Bytes $effMax))
                $tooLargeCnt++
                $tooLargeList.Add("$rel  |  $note")
                $reportLines.Add((CsvRow "SKIPPED_TOO_LARGE" $rel $o.Length "-" 0 $note))
                Append-Log ("SKIP oversized: {0}  |  {1}" -f $rel, (Format-Bytes $o.Length))
            }
            $allFiles = @($allFiles | Where-Object { -not $skipSet.Contains($_.FullName) })
            $total = $allFiles.Count
            if ($total -eq 0) {
                Set-Summary 0 0 0 $tooLargeCnt 0 "-"
                Set-Status "Nothing left to archive after skipping oversized files." $clrAmber
                Toggle-Buttons $false
                [System.Windows.Forms.MessageBox]::Show("All selected files were skipped because they exceed the effective ZIP size limit.","Nothing To Archive","OK","Exclamation") | Out-Null
                return
            }
            Set-Summary $total 0 0 $tooLargeCnt 0 "-"
        }
    }

    Append-Log ("Files: {0}  |  Max: {1:N2} MB  |  Reserve: {2:N2} MB  |  Effective: {3:N2} MB  |  Compression: {4}  |  Preserve paths: {5}  |  Password: {6}  |  Split volumes: {7}" -f $total,$maxMB,$resMB,($effMax/1MB),$compLvl,$keepPaths,($(if ([string]::IsNullOrWhiteSpace($zipPassword)) { "Off" } else { if ($useAes256) { "AES-256" } else { "On" } })),($(if ($splitMode) { "On" } else { "Off" })))
    Append-Log ("-" * 64)

    $archIdx      = 1
    $archPath     = Build-ArchivePath $outFolder $baseName $archIdx
    if (Test-Path $archPath) { Remove-Item $archPath -Force }
    $archHasFiles = $false
    $packedCnt    = 0
    $failedCnt    = 0
    $prevDir      = $PWD.Path

    Set-Status "Compressing..." $clrBlue

    for ($i = 0; $i -lt $total; $i++) {
        if ($script:stopRequested) { break }

        $file     = $allFiles[$i]
        $relPath  = $file.FullName.Substring($srcFolder.Length).TrimStart('\')
        $srcBytes = $file.Length

        Set-Progress ([int](($i / $total) * 100))
        Append-Log ("[{0}/{1}] {2}" -f ($i+1),$total,$relPath)

        # --- Add to current archive ---
        if ($keepPaths) {
            Set-Location $srcFolder
            $rc = Invoke-7ZipAdd $szPath $archPath $relPath $compLvl $zipPassword $useAes256
            Set-Location $prevDir
        } else {
            $rc = Invoke-7ZipAdd $szPath $archPath $file.FullName $compLvl $zipPassword $useAes256
        }

        if ($rc -ne 0) {
            $failedCnt++
            $msg = "Add failed (exit $rc)"
            $failedList.Add("$relPath  |  $msg")
            $reportLines.Add((CsvRow "FAILED" $relPath $srcBytes (Split-Path $archPath -Leaf) 0 $msg))
            Append-Log "  -> FAILED: $msg"
            Set-Summary $total $packedCnt (Count-Archives $outFolder $baseName) $tooLargeCnt $failedCnt "-"
            continue
        }

        $sz = if (Test-Path $archPath) { (Get-Item $archPath).Length } else { 0 }

        if ($sz -le $effMax) {
            $packedCnt++
            $archHasFiles = $true
            Append-Log ("  -> {0}  |  {1}" -f (Split-Path $archPath -Leaf),(Format-Bytes $sz))
            $reportLines.Add((CsvRow "PACKED" $relPath $srcBytes (Split-Path $archPath -Leaf) $sz "Packed into current archive"))
        } else {
            # Overflow - roll back this one file
            if ($keepPaths) {
                Set-Location $srcFolder
                $rc2  = Invoke-7ZipDelete $szPath $archPath $relPath $zipPassword
                Set-Location $prevDir
            } else {
                $rc2  = Invoke-7ZipDelete $szPath $archPath $file.Name $zipPassword
            }

            if ($rc2 -ne 0) {
                $failedCnt++
                $msg = "Rollback failed (exit $rc2)"
                $failedList.Add("$relPath  |  $msg")
                $reportLines.Add((CsvRow "FAILED" $relPath $srcBytes (Split-Path $archPath -Leaf) $sz $msg))
                Append-Log "  -> FAILED rollback: exit $rc2"
                Set-Summary $total $packedCnt (Count-Archives $outFolder $baseName) $tooLargeCnt $failedCnt "-"
                continue
            }

            # Remove empty archive if nothing was in it before this file
            if (-not $archHasFiles -and (Test-Path $archPath)) { Remove-Item $archPath -Force }

            # Open a fresh archive
            $archIdx++
            $archPath     = Build-ArchivePath $outFolder $baseName $archIdx
            if (Test-Path $archPath) { Remove-Item $archPath -Force }
            $archHasFiles = $false

            # Add to fresh archive
            if ($keepPaths) {
                Set-Location $srcFolder
                $rc3  = Invoke-7ZipAdd $szPath $archPath $relPath $compLvl $zipPassword $useAes256
                Set-Location $prevDir
            } else {
                $rc3  = Invoke-7ZipAdd $szPath $archPath $file.FullName $compLvl $zipPassword $useAes256
            }

            if ($rc3 -ne 0) {
                $failedCnt++
                $msg = "Failed adding to new archive (exit $rc3)"
                $failedList.Add("$relPath  |  $msg")
                $reportLines.Add((CsvRow "FAILED" $relPath $srcBytes (Split-Path $archPath -Leaf) 0 $msg))
                Append-Log "  -> FAILED new archive: exit $rc3"
                Set-Summary $total $packedCnt (Count-Archives $outFolder $baseName) $tooLargeCnt $failedCnt "-"
                continue
            }

            $sz2 = if (Test-Path $archPath) { (Get-Item $archPath).Length } else { 0 }
            if ($sz2 -gt $effMax) {
                if (Test-Path $archPath) { Remove-Item $archPath -Force }
                if ($splitMode) {
                    if ($keepPaths) {
                        Set-Location $srcFolder
                        $rc4 = Invoke-7ZipAddSplit $szPath $archPath $relPath $compLvl $zipPassword $useAes256 $effMax
                        Set-Location $prevDir
                    } else {
                        $rc4 = Invoke-7ZipAddSplit $szPath $archPath $file.FullName $compLvl $zipPassword $useAes256 $effMax
                    }

                    if ($rc4 -ne 0) {
                        $failedCnt++
                        $msg = "Split-volume create failed (exit $rc4)"
                        $failedList.Add("$relPath  |  $msg")
                        $reportLines.Add((CsvRow "FAILED" $relPath $srcBytes (Split-Path $archPath -Leaf) 0 $msg))
                        Append-Log "  -> FAILED split-volume creation."
                    } else {
                        $packedCnt++
                        $splitBytes = Get-SplitArchiveBytes $archPath
                        Append-Log ("  -> Split-volume archive: {0}*  |  total {1}" -f (Split-Path $archPath -Leaf),(Format-Bytes $splitBytes))
                        $reportLines.Add((CsvRow "PACKED_SPLIT" $relPath $srcBytes (Split-Path $archPath -Leaf) $splitBytes "Packed as split-volume ZIP set"))
                        $archIdx++
                        $archPath     = Build-ArchivePath $outFolder $baseName $archIdx
                        if (Test-Path $archPath) { Remove-Item $archPath -Force }
                        $archHasFiles = $false
                    }
                } else {
                    $tooLargeCnt++
                    $msg = ("Exceeds effective limit ({0:N2} MB) even alone" -f ($effMax/1MB))
                    $tooLargeList.Add("$relPath  |  $msg")
                    $reportLines.Add((CsvRow "TOO_LARGE" $relPath $srcBytes (Split-Path $archPath -Leaf) $sz2 $msg))
                    Append-Log "  -> TOO LARGE even alone."
                }
            } else {
                $packedCnt++
                $archHasFiles = $true
                Append-Log ("  -> New archive: {0}  |  {1}" -f (Split-Path $archPath -Leaf),(Format-Bytes $sz2))
                $reportLines.Add((CsvRow "PACKED" $relPath $srcBytes (Split-Path $archPath -Leaf) $sz2 "Packed into new archive"))
            }
        }

        Set-Summary $total $packedCnt (Count-Archives $outFolder $baseName) $tooLargeCnt $failedCnt "-"
    }

    Set-Progress 100

    $reportStatus = "-"
    if ($makeReport) {
        $ts  = Get-Date -Format "yyyyMMdd_HHmmss"
        $rpt = Join-Path $outFolder "${baseName}_report_${ts}.csv"
        try {
            $reportLines | Out-File -FilePath $rpt -Encoding UTF8 -Force
            $reportStatus = Split-Path $rpt -Leaf
            Append-Log "CSV report: $rpt"
        } catch {
            $reportStatus = "WRITE FAILED"
            Append-Log "Could not write CSV: $_"
        }
    }

    $finalArchCnt = Count-Archives $outFolder $baseName
    Set-Summary $total $packedCnt $finalArchCnt $tooLargeCnt $failedCnt $reportStatus

    $errText = ""
    if ($tooLargeList.Count -gt 0) {
        $errText += "FILES TOO LARGE FOR SIZE LIMIT`r`n" + ("-"*60) + "`r`n" + ($tooLargeList -join "`r`n") + "`r`n`r`n"
    }
    if ($failedList.Count -gt 0) {
        $errText += "FILES THAT FAILED`r`n" + ("-"*60) + "`r`n" + ($failedList -join "`r`n")
    }
    $errorBox.Text = $errText

    if ($script:stopRequested) {
        Set-Status "Stopped by user." $clrAmber
        [System.Windows.Forms.MessageBox]::Show("Process stopped by user.","Stopped","OK","Exclamation") | Out-Null
    } elseif ($tooLargeCnt -gt 0 -or $failedCnt -gt 0) {
        Set-Status "Completed with warnings." $clrAmber
        [System.Windows.Forms.MessageBox]::Show("Completed with warnings.`r`nCheck the error panel and CSV report.","Warnings","OK","Exclamation") | Out-Null
    } else {
        Set-Status "Completed successfully." $clrGreen
        [System.Windows.Forms.MessageBox]::Show("All files packed successfully.","Done","OK","Information") | Out-Null
    }

    if ($openWhenDone) { Start-Process explorer.exe $outFolder }
    Toggle-Buttons $false
})

# =============================================================================
# STARTUP + RUN
# =============================================================================
$form.Add_Shown({ Invoke-Detect7Zip })
[void]$form.ShowDialog()
