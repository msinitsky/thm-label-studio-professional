# THM Label Studio v0.9 — two captured media profiles (experimental)
# Windows 11, Windows PowerShell 5.1, WinForms; tested protocol template from successful ABC456 job.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$qrSource = Join-Path $baseDir 'THM_QR_Encoder.cs'
if (-not (Test-Path -LiteralPath $qrSource)) { throw 'QR encoder source missing' }
if (-not ('THMQRCode' -as [type])) { Add-Type -Path $qrSource -ReferencedAssemblies @('System.Drawing.dll') }
$templatePath = Join-Path $baseDir 'THM_ABC456_CUSTOM_RAW.bin'
if (-not (Test-Path -LiteralPath $templatePath)) { throw "Template missing: $templatePath" }
$expectedHash = 'ABC2D75E0D8D1B69D223DC1A5B0CE93E0C1014D43B25D61656BCA00444B561CD'
if ((Get-FileHash -LiteralPath $templatePath -Algorithm SHA256).Hash -ne $expectedHash) { throw 'Template SHA256 mismatch' }
$template = [IO.File]::ReadAllBytes($templatePath)
# Locate complete PNG by its signature and IEND chunk; preserve all commands outside PNG.
$pngStart = 18
if ($template[$pngStart] -ne 137 -or $template[$pngStart+1] -ne 80) { throw 'Unexpected PNG position in template' }
$pngEnd = -1
for ($i=$pngStart+8; $i -lt $template.Length-8; $i++) {
    if ($template[$i] -eq 73 -and $template[$i+1] -eq 69 -and $template[$i+2] -eq 78 -and $template[$i+3] -eq 68) {
        $pngEnd = $i + 8
        break
    }
}
if ($pngEnd -lt 0) { throw 'PNG IEND not found' }
$prefix = $template[0..($pngStart-1)]
$suffix = $template[$pngEnd..($template.Length-1)]
# Second profile is extracted directly from a successful M-Print PRO USB capture.
$profile45Path = Join-Path $baseDir 'THM_45x15_MPRINT_RAW.bin'
$profile45Hash = 'BA42A62045F93E9671133804AE1BB705CE1F351D1BA3945A1E9A84E282D80132'
if (-not (Test-Path -LiteralPath $profile45Path)) { throw '45x15 captured profile missing' }
if ((Get-FileHash -LiteralPath $profile45Path -Algorithm SHA256).Hash -ne $profile45Hash) { throw '45x15 captured profile SHA256 mismatch' }
$profile45Bytes = [IO.File]::ReadAllBytes($profile45Path)
if ($profile45Bytes.Length -lt 100) { throw '45x15 RAW file too short' }
for ($i=0; $i -lt $pngStart; $i++) { if ($prefix[$i] -ne $profile45Bytes[$i]) { throw '45x15 RAW header mismatch' } }
$profile45PngEnd = -1
for ($i=$pngStart+8; $i -lt $profile45Bytes.Length-8; $i++) {
    if ($profile45Bytes[$i] -eq 73 -and $profile45Bytes[$i+1] -eq 69 -and $profile45Bytes[$i+2] -eq 78 -and $profile45Bytes[$i+3] -eq 68) { $profile45PngEnd=$i+8; break }
}
if ($profile45PngEnd -lt 0) { throw '45x15 PNG end not found' }
$profile45Suffix = $profile45Bytes[$profile45PngEnd..($profile45Bytes.Length-1)]
$profile45SuffixText = [Text.Encoding]::ASCII.GetString($profile45Suffix)
if (-not $profile45SuffixText.Contains('Sl1;0.0,-0.50,16.00,16.00,50.50')) { throw '45x15 feed command mismatch' }


if (-not ('THMLabelRaw' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class THMLabelRaw {
 [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
 public struct DOCINFO {
  [MarshalAs(UnmanagedType.LPWStr)] public string pDocName;
  [MarshalAs(UnmanagedType.LPWStr)] public string pOutputFile;
  [MarshalAs(UnmanagedType.LPWStr)] public string pDatatype;
 }
 [DllImport("winspool.drv",EntryPoint="OpenPrinterW",CharSet=CharSet.Unicode,SetLastError=true)]
 public static extern bool OpenPrinter(string name,out IntPtr handle,IntPtr defaults);
 [DllImport("winspool.drv",EntryPoint="StartDocPrinterW",CharSet=CharSet.Unicode,SetLastError=true)]
 public static extern int StartDocPrinter(IntPtr handle,int level,ref DOCINFO info);
 [DllImport("winspool.drv",SetLastError=true)]
 public static extern bool WritePrinter(IntPtr handle,byte[] data,int count,out int written);
 [DllImport("winspool.drv",SetLastError=true)] public static extern bool EndDocPrinter(IntPtr handle);
 [DllImport("winspool.drv",SetLastError=true)] public static extern bool ClosePrinter(IntPtr handle);
}
'@
}


$script:code128Patterns = @('212222','222122','222221','121223','121322','131222','122213','122312','132212','221213','221312','231212','112232','122132','122231','113222','123122','123221','223211','221132','221231','213212','223112','312131','311222','321122','321221','312212','322112','322211','212123','212321','232121','111323','131123','131321','112313','132113','132311','211313','231113','231311','112133','112331','132131','113123','113321','133121','313121','211331','231131','213113','213311','213131','311123','311321','331121','312113','312311','332111','314111','221411','431111','111224','111422','121124','121421','141122','141221','112214','112412','122114','122411','142112','142211','241211','221114','413111','241112','134111','111242','121142','121241','114212','124112','124211','411212','421112','421211','212141','214121','412121','111143','111341','131141','114113','114311','411113','411311','113141','114131','311141','411131','211412','211214','211232','2331112')
function Draw-Code128([System.Drawing.Graphics]$g, [string]$value, [int]$cx, [int]$cy, [int]$width, [int]$height) {
    if ([string]::IsNullOrWhiteSpace($value)) { return }
    $codes = New-Object 'System.Collections.Generic.List[int]'
    $codes.Add(104) # Code128-B
    foreach ($ch in $value.ToCharArray()) {
        $v = [int][char]$ch
        if ($v -lt 32 -or $v -gt 126) { throw 'Code128 supports ASCII 32-126 only' }
        $codes.Add($v - 32)
    }
    $checksum = 104
    for ($i=1; $i -lt $codes.Count; $i++) { $checksum += $i * $codes[$i] }
    $codes.Add($checksum % 103)
    $codes.Add(106)
    $total = 20
    foreach ($idx in $codes) {
        foreach ($c in $script:code128Patterns[$idx].ToCharArray()) { $total += [int]::Parse([string]$c) }
    }
    $moduleWidth = [double]$width / [double]$total
    $pos = [double]($cx - $width / 2.0) + 10 * $moduleWidth
    foreach ($idx in $codes) {
        $pattern = $script:code128Patterns[$idx]
        for ($j=0; $j -lt $pattern.Length; $j++) {
            $units = [int]::Parse([string]$pattern[$j])
            if (($j % 2) -eq 0) {
                $x1 = [int][Math]::Round($pos)
                $x2 = [int][Math]::Round($pos + $units * $moduleWidth)
                if ($x2 -gt $x1) { $g.FillRectangle([System.Drawing.Brushes]::Black,$x1,($cy - [int]($height/2)),($x2-$x1),$height) }
            }
            $pos += $units * $moduleWidth
        }
    }
}

function New-LabelBitmap([object[]]$blocks, [string]$imagePath, [int]$imageX, [int]$imageY, [int]$imageW, [int]$imageH, [string]$barcodeText, [int]$barcodeX, [int]$barcodeY, [int]$barcodeW, [int]$barcodeH, [string]$qrText, [int]$qrX, [int]$qrY, [int]$qrSize) {
    $bmp = [System.Drawing.Bitmap]::new(780,366,[System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.Clear([System.Drawing.Color]::White)
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        if (-not [string]::IsNullOrWhiteSpace($imagePath)) {
            if (-not [IO.File]::Exists($imagePath)) { throw "Image not found: $imagePath" }
            $img = [System.Drawing.Image]::FromFile($imagePath)
            try {
                $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $dest = [System.Drawing.Rectangle]::new([int]($imageX-$imageW/2),[int]($imageY-$imageH/2),$imageW,$imageH)
                $g.DrawImage($img,$dest)
            } finally { $img.Dispose() }
        }
        if (-not [string]::IsNullOrWhiteSpace($qrText)) {
            $qrBitmap = [THMQRCode]::Render($qrText, $qrSize)
            try { $g.DrawImageUnscaled($qrBitmap, ($qrX - [int]($qrSize / 2)), ($qrY - [int]($qrSize / 2))) }
            finally { $qrBitmap.Dispose() }
        }
        Draw-Code128 $g $barcodeText $barcodeX $barcodeY $barcodeW $barcodeH
        foreach ($block in $blocks) {
            if ([string]::IsNullOrWhiteSpace([string]$block.Text)) { continue }
            $style = if ($block.Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
            $font = [System.Drawing.Font]::new([string]$block.Font,[single]$block.Size,$style,[System.Drawing.GraphicsUnit]::Pixel)
            $fmt = New-Object System.Drawing.StringFormat
            try {
                $fmt.Alignment = switch ($block.Align) { 'Left' { [System.Drawing.StringAlignment]::Near } 'Right' { [System.Drawing.StringAlignment]::Far } default { [System.Drawing.StringAlignment]::Center } }
                $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
                $fmt.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter
                $fmt.FormatFlags = [System.Drawing.StringFormatFlags]::LineLimit
                $state = $g.Save()
                try {
                    $g.TranslateTransform([float]$block.X,[float]$block.Y)
                    $g.RotateTransform([float]$block.Rotation)
                    $halfWidth = [single]([double]$block.Width / 2.0)
                    $halfHeight = [single]([double]$block.Height / 2.0)
                    $rect = [System.Drawing.RectangleF]::new(
                        [single](-$halfWidth), [single](-$halfHeight),
                        [single]$block.Width, [single]$block.Height
                    )
                    $g.DrawString([string]$block.Text,$font,[System.Drawing.Brushes]::Black,$rect,$fmt)
                } finally { $g.Restore($state) }
            } finally { $fmt.Dispose(); $font.Dispose() }
        }
    } finally { $g.Dispose() }
    return $bmp
}

function Convert-ToIndexedPng([System.Drawing.Bitmap]$source) {
    $w=$source.Width; $h=$source.Height
    # Convert to indexed 8bpp grayscale with two palette entries (black and white).
    # The previously successful RAW job used indexed PNG.
    $indexed = [System.Drawing.Bitmap]::new($w,$h,[System.Drawing.Imaging.PixelFormat]::Format8bppIndexed)
    $pal = $indexed.Palette
    $pal.Entries[0] = [System.Drawing.Color]::Black
    $pal.Entries[1] = [System.Drawing.Color]::White
    $indexed.Palette = $pal
    $rect = [System.Drawing.Rectangle]::new(0,0,$w,$h)
    $srcData = $source.LockBits($rect,[System.Drawing.Imaging.ImageLockMode]::ReadOnly,[System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $dstData = $indexed.LockBits($rect,[System.Drawing.Imaging.ImageLockMode]::WriteOnly,[System.Drawing.Imaging.PixelFormat]::Format8bppIndexed)
    try {
        $srcBytes = New-Object byte[] ([Math]::Abs($srcData.Stride)*$h)
        [Runtime.InteropServices.Marshal]::Copy($srcData.Scan0,$srcBytes,0,$srcBytes.Length)
        $dstBytes = New-Object byte[] ([Math]::Abs($dstData.Stride)*$h)
        for ($y=0; $y -lt $h; $y++) {
            $srow = if ($srcData.Stride -ge 0) { $y*$srcData.Stride } else { (($h-1)-$y)*(-$srcData.Stride) }
            $drow = if ($dstData.Stride -ge 0) { $y*$dstData.Stride } else { (($h-1)-$y)*(-$dstData.Stride) }
            for ($x=0; $x -lt $w; $x++) {
                $off = $srow + 3*$x
                $lum = ([int]$srcBytes[$off] + [int]$srcBytes[$off+1] + [int]$srcBytes[$off+2]) / 3
                $dstBytes[$drow+$x] = if ($lum -ge 160) { 1 } else { 0 }
            }
        }
        [Runtime.InteropServices.Marshal]::Copy($dstBytes,0,$dstData.Scan0,$dstBytes.Length)
    } finally { $source.UnlockBits($srcData); $indexed.UnlockBits($dstData) }
    $stream = New-Object IO.MemoryStream
    try { $indexed.Save($stream,[System.Drawing.Imaging.ImageFormat]::Png); return ,($stream.ToArray()) }
    finally { $stream.Dispose(); $indexed.Dispose() }
}
function New-RawJob([byte[]]$png, [string]$profile) {
    $chosenSuffix = if ($profile -eq '45x15') { $profile45Suffix } else { $suffix }
    $stream = New-Object IO.MemoryStream
    try {
        $stream.Write($prefix,0,$prefix.Length)
        $stream.Write($png,0,$png.Length)
        $stream.Write($chosenSuffix,0,$chosenSuffix.Length)
        return ,($stream.ToArray())
    } finally { $stream.Dispose() }
}
function Send-Raw([byte[]]$bytes) {
    $printerName = 'THM MultiMark TEST'
    $p = Get-Printer -Name $printerName -ErrorAction Stop
    if ($p.PortName -ne 'USB005' -or $p.PrintProcessor -ne 'winprint' -or $p.Datatype -ne 'RAW') { throw 'Unexpected printer queue configuration' }
    if (@(Get-PrintJob -PrinterName $printerName -ErrorAction Stop).Count -gt 0) { throw 'Queue contains unfinished jobs' }
    $handle = [IntPtr]::Zero; $started = $false
    try {
        if (-not [THMLabelRaw]::OpenPrinter($printerName,[ref]$handle,[IntPtr]::Zero)) { throw 'OpenPrinter failed' }
        $info = New-Object 'THMLabelRaw+DOCINFO'; $info.pDocName = 'THM Label Studio test'; $info.pDatatype = 'RAW'
        $id = [THMLabelRaw]::StartDocPrinter($handle,1,[ref]$info)
        if ($id -le 0) { throw 'StartDocPrinter failed' }
        $started = $true; $written = 0
        if (-not [THMLabelRaw]::WritePrinter($handle,$bytes,$bytes.Length,[ref]$written) -or $written -ne $bytes.Length) { throw "WritePrinter failed ($written/$($bytes.Length))" }
        return $id
    } finally {
        if ($started) { [void][THMLabelRaw]::EndDocPrinter($handle) }
        if ($handle -ne [IntPtr]::Zero) { [void][THMLabelRaw]::ClosePrinter($handle) }
    }
}

# Label Studio v0.6: text, image, Code128, embedded image layouts.
$form = New-Object Windows.Forms.Form
$form.Text = 'THM Label Studio 0.8.2 - tabbed workspace'
# Keep original control coordinates and printing logic unchanged.
# Make the form resizable and scrollable on smaller screens.
$form.AutoScaleMode = [Windows.Forms.AutoScaleMode]::Dpi
$form.ClientSize = [Drawing.Size]::new(1450, 800)
$form.MinimumSize = [Drawing.Size]::new(520, 380)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = [Windows.Forms.FormBorderStyle]::Sizable
$form.MaximizeBox = $true
$form.AutoScroll = $true
$form.AutoScrollMinSize = [Drawing.Size]::new(1100, 700)


function Add-Label($caption,$x,$y,$w=110) {
    $control = New-Object Windows.Forms.Label
    $control.Text=$caption; $control.SetBounds($x,$y,$w,22); $form.Controls.Add($control)
}
function Add-Number($x,$y,$min,$max,$value,$width=65) {
    $control = New-Object Windows.Forms.NumericUpDown
    $control.Minimum=$min; $control.Maximum=$max; $control.Value=$value
    $control.SetBounds($x,$y,$width,25); $form.Controls.Add($control)
    return $control
}
function Add-Combo($x,$y,[string[]]$values,$selected,$width=110) {
    $control = New-Object Windows.Forms.ComboBox
    $control.DropDownStyle='DropDownList'; $control.SetBounds($x,$y,$width,25)
    foreach ($v in $values) { [void]$control.Items.Add($v) }
    $control.SelectedItem=$selected; $form.Controls.Add($control)
    return $control
}

Add-Label 'Block 1 text:' 18 14 140
$textBox = New-Object Windows.Forms.TextBox; $textBox.Text='SEI-2026'; $textBox.SetBounds(18,38,855,32); $form.Controls.Add($textBox)
Add-Label 'Block 2 text (optional):' 18 81 220
$textBox2 = New-Object Windows.Forms.TextBox; $textBox2.Text=''; $textBox2.SetBounds(18,105,855,32); $form.Controls.Add($textBox2)

Add-Label 'Block' 18 153 60
Add-Label 'Font' 85 153 60
Add-Label 'Size px' 264 153 70
Add-Label 'Align' 344 153 70
Add-Label 'Bold' 462 153 60
Add-Label 'X center' 523 153 80
Add-Label 'Y center' 605 153 80
Add-Label 'Rotation' 690 153 90

Add-Label '1' 18 184 30
$fontBox=Add-Combo 85 180 @('Arial','Arial Narrow','Calibri','Consolas','Tahoma','Times New Roman') 'Arial' 165
$sizeBox=Add-Number 264 180 8 250 90 68
$alignBox=Add-Combo 344 180 @('Left','Center','Right') 'Center' 107
$boldBox=New-Object Windows.Forms.CheckBox; $boldBox.Checked=$true; $boldBox.SetBounds(475,181,25,24); $form.Controls.Add($boldBox)
$xBox=Add-Number 523 180 0 780 390 73
$yBox=Add-Number 605 180 0 366 183 73
$rotationBox=Add-Combo 690 180 @('0','90','180','270') '0' 82

Add-Label '2' 18 221 30
$fontBox2=Add-Combo 85 217 @('Arial','Arial Narrow','Calibri','Consolas','Tahoma','Times New Roman') 'Arial' 165
$sizeBox2=Add-Number 264 217 8 250 48 68
$alignBox2=Add-Combo 344 217 @('Left','Center','Right') 'Center' 107
$boldBox2=New-Object Windows.Forms.CheckBox; $boldBox2.Checked=$false; $boldBox2.SetBounds(475,218,25,24); $form.Controls.Add($boldBox2)
$xBox2=Add-Number 523 217 0 780 390 73
$yBox2=Add-Number 605 217 0 366 285 73
$rotationBox2=Add-Combo 690 217 @('0','90','180','270') '0' 82

$note = New-Object Windows.Forms.Label
$note.Text='Verified protocol: 780 x 366 px. Physical stock: 58 x 30 mm. Other sizes are DESIGN-ONLY: RAW export and printing are blocked.'
$note.SetBounds(18,255,855,40); $form.Controls.Add($note)
$preview = New-Object Windows.Forms.PictureBox; $preview.SizeMode='Zoom'; $preview.BorderStyle='FixedSingle'; $preview.BackColor=[Drawing.Color]::White; $preview.SetBounds(18,470,855,385); $form.Controls.Add($preview)

$previewBtn=New-Object Windows.Forms.Button; $previewBtn.Text='Refresh preview'; $previewBtn.SetBounds(18,865,140,32); $form.Controls.Add($previewBtn)
$saveLayoutBtn=New-Object Windows.Forms.Button; $saveLayoutBtn.Text='Save layout'; $saveLayoutBtn.SetBounds(168,865,120,32); $form.Controls.Add($saveLayoutBtn)
$loadLayoutBtn=New-Object Windows.Forms.Button; $loadLayoutBtn.Text='Load layout'; $loadLayoutBtn.SetBounds(298,865,120,32); $form.Controls.Add($loadLayoutBtn)
$saveBtn=New-Object Windows.Forms.Button; $saveBtn.Text='Save RAW'; $saveBtn.SetBounds(428,865,120,32); $form.Controls.Add($saveBtn)
$printBtn=New-Object Windows.Forms.Button; $printBtn.Text='Print ONE label'; $printBtn.SetBounds(713,865,160,32); $form.Controls.Add($printBtn)


# Image import: image is drawn behind text, centered at X/Y.
$script:importedImagePath = ''
Add-Label 'Image:' 18 301 65
$imagePathBox = New-Object Windows.Forms.TextBox
$imagePathBox.ReadOnly=$true; $imagePathBox.SetBounds(80,299,320,25); $form.Controls.Add($imagePathBox)
$imageLoadBtn=New-Object Windows.Forms.Button; $imageLoadBtn.Text='Import PNG/JPG'; $imageLoadBtn.SetBounds(410,298,125,27); $form.Controls.Add($imageLoadBtn)
$imageClearBtn=New-Object Windows.Forms.Button; $imageClearBtn.Text='Remove image'; $imageClearBtn.SetBounds(545,298,120,27); $form.Controls.Add($imageClearBtn)
Add-Label 'X' 18 335 22
$imageXBox=Add-Number 40 330 0 780 390 72
Add-Label 'Y' 125 335 22
$imageYBox=Add-Number 147 330 0 366 183 72
Add-Label 'Width' 235 335 55
$imageWBox=Add-Number 290 330 1 780 180 72
Add-Label 'Height' 380 335 58
$imageHBox=Add-Number 440 330 1 366 120 72
Add-Label 'Drag target' 530 335 90
$dragTarget=Add-Combo 620 330 @('Block 1','Block 2','Image','Code128','QR') 'Block 1' 120
Add-Label 'Mouse mode' 750 301 100
$mouseMode=Add-Combo 750 330 @('Move','Resize') 'Move' 115

# Code128-B controls
Add-Label 'Code128:' 18 373 70
$barcodeBox=New-Object Windows.Forms.TextBox; $barcodeBox.SetBounds(90,371,290,25); $form.Controls.Add($barcodeBox)
Add-Label 'X' 390 373 18
$barcodeXBox=Add-Number 410 370 0 780 390 65
Add-Label 'Y' 485 373 18
$barcodeYBox=Add-Number 505 370 0 366 300 65
Add-Label 'W' 580 373 18
$barcodeWBox=Add-Number 600 370 60 780 400 65
Add-Label 'H' 675 373 18
$barcodeHBox=Add-Number 695 370 10 300 90 65

# Offline QR (versions 1-5, ECC L, UTF-8, no network dependency)
Add-Label 'QR text:' 18 413 70
$qrBox=New-Object Windows.Forms.TextBox; $qrBox.SetBounds(90,411,390,25); $form.Controls.Add($qrBox)
Add-Label 'X' 490 413 18
$qrXBox=Add-Number 510 410 0 780 620 65
Add-Label 'Y' 590 413 18
$qrYBox=Add-Number 610 410 0 366 180 65
Add-Label 'Size' 690 413 40
$qrSizeBox=Add-Number 730 410 40 350 180 65
$qrNote=New-Object Windows.Forms.Label; $qrNote.Text='QR: offline UTF-8, ECC L, max 106 bytes. Leave QR text empty to disable. Scan test recommended.'
$qrNote.SetBounds(18,442,855,22); $form.Controls.Add($qrNote)

$getBlocks = {
    return ,@(
        [pscustomobject]@{Text=$textBox.Text;Font=[string]$fontBox.SelectedItem;Size=[int]$sizeBox.Value;Align=[string]$alignBox.SelectedItem;Bold=[bool]$boldBox.Checked;X=[int]$xBox.Value;Y=[int]$yBox.Value;Rotation=[int]([string]$rotationBox.SelectedItem);Width=700;Height=140},
        [pscustomobject]@{Text=$textBox2.Text;Font=[string]$fontBox2.SelectedItem;Size=[int]$sizeBox2.Value;Align=[string]$alignBox2.SelectedItem;Bold=[bool]$boldBox2.Checked;X=[int]$xBox2.Value;Y=[int]$yBox2.Value;Rotation=[int]([string]$rotationBox2.SelectedItem);Width=700;Height=140}
    )
}
$render = {
    $blocks = & $getBlocks
    $bmp = New-LabelBitmap $blocks $script:importedImagePath ([int]$imageXBox.Value) ([int]$imageYBox.Value) ([int]$imageWBox.Value) ([int]$imageHBox.Value) $barcodeBox.Text ([int]$barcodeXBox.Value) ([int]$barcodeYBox.Value) ([int]$barcodeWBox.Value) ([int]$barcodeHBox.Value) $qrBox.Text ([int]$qrXBox.Value) ([int]$qrYBox.Value) ([int]$qrSizeBox.Value)
    $old=$preview.Image; $preview.Image=$bmp
    if ($old) { $old.Dispose() }
}
$makeJob = {
    $profile=[string]$profileCombo.SelectedItem
    $is60=($profile -eq '60x30 (58x30 physical)' -and $stockWidthBox.Value -eq 58 -and $stockHeightBox.Value -eq 30)
    $is45=($profile -eq '45x15 (43x25 physical)' -and $stockWidthBox.Value -eq 43 -and $stockHeightBox.Value -eq 25)
    if (-not ($is60 -or $is45)) { throw 'Profile and physical stock do not match. Printing is blocked.' }
    $blocks = & $getBlocks
    if (-not (@($blocks | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Text) }).Count) -and [string]::IsNullOrWhiteSpace($script:importedImagePath) -and [string]::IsNullOrWhiteSpace($barcodeBox.Text) -and [string]::IsNullOrWhiteSpace($qrBox.Text)) { throw 'No text or image to print' }
    $bmp = New-LabelBitmap $blocks $script:importedImagePath ([int]$imageXBox.Value) ([int]$imageYBox.Value) ([int]$imageWBox.Value) ([int]$imageHBox.Value) $barcodeBox.Text ([int]$barcodeXBox.Value) ([int]$barcodeYBox.Value) ([int]$barcodeWBox.Value) ([int]$barcodeHBox.Value) $qrBox.Text ([int]$qrXBox.Value) ([int]$qrYBox.Value) ([int]$qrSizeBox.Value)
    try {
        if ($is45) {
            $scaled=[Drawing.Bitmap]::new(596,189,[Drawing.Imaging.PixelFormat]::Format24bppRgb)
            try {
                $g=[Drawing.Graphics]::FromImage($scaled)
                try { $g.Clear([Drawing.Color]::White); $g.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic; $g.DrawImage($bmp,0,0,596,189) }
                finally { $g.Dispose() }
                $png=Convert-ToIndexedPng $scaled
            } finally { $scaled.Dispose() }
            return ,(New-RawJob $png '45x15')
        }
        $png=Convert-ToIndexedPng $bmp
        return ,(New-RawJob $png '60x30')
    } finally { $bmp.Dispose() }
}
$imageLoadBtn.Add_Click({
    try {
        $dlg=New-Object Windows.Forms.OpenFileDialog
        $dlg.Filter='Images (*.png;*.jpg;*.jpeg;*.bmp)|*.png;*.jpg;*.jpeg;*.bmp'
        if ($dlg.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) {
            $script:importedImagePath=$dlg.FileName
            $imagePathBox.Text=$script:importedImagePath
            & $render
        }
    } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Image import error') | Out-Null }
})
$qrHelpBtn=New-Object Windows.Forms.Button
$qrHelpBtn.Text='QR info'
$qrHelpBtn.SetBounds(675,298,115,27)
$form.Controls.Add($qrHelpBtn)
$qrHelpBtn.Add_Click({
    [Windows.Forms.MessageBox]::Show('Enter text in QR text field. Generated offline with UTF-8 encoding, ECC L, version 1-5. Use Size >= 150 px and verify with a QR scanner.','QR help') | Out-Null
})
$imageClearBtn.Add_Click({ $script:importedImagePath=''; $imagePathBox.Text=''; try { & $render } catch {} })
# PictureBox uses Zoom; map mouse location back into the 780 x 366 canvas.
$script:dragging=$false
$preview.Add_MouseDown({ param($sender,$e)
    if ($e.Button -eq [Windows.Forms.MouseButtons]::Left) { $script:dragging=$true }
})
$preview.Add_MouseUp({ $script:dragging=$false })
$preview.Add_MouseMove({ param($sender,$e)
    if (-not $script:dragging) { return }
    $scale=[Math]::Min($preview.ClientSize.Width/780.0,$preview.ClientSize.Height/366.0)
    $drawW=780.0*$scale; $drawH=366.0*$scale
    $offX=($preview.ClientSize.Width-$drawW)/2.0
    $offY=($preview.ClientSize.Height-$drawH)/2.0
    $xx=[Math]::Max(0,[Math]::Min(780,[int][Math]::Round(($e.X-$offX)/$scale)))
    $yy=[Math]::Max(0,[Math]::Min(366,[int][Math]::Round(($e.Y-$offY)/$scale)))
    if ([string]$mouseMode.SelectedItem -eq 'Resize') {
        switch ([string]$dragTarget.SelectedItem) {
            'Image' {
                $imageWBox.Value=[decimal][Math]::Max(1,[Math]::Min(780,2*[Math]::Abs($xx-[int]$imageXBox.Value)))
                $imageHBox.Value=[decimal][Math]::Max(1,[Math]::Min(366,2*[Math]::Abs($yy-[int]$imageYBox.Value)))
            }
            'QR' {
                $qrSizeBox.Value=[decimal][Math]::Max(40,[Math]::Min(350,2*[Math]::Max([Math]::Abs($xx-[int]$qrXBox.Value),[Math]::Abs($yy-[int]$qrYBox.Value))))
            }
            'Code128' {
                $barcodeWBox.Value=[decimal][Math]::Max(60,[Math]::Min(780,2*[Math]::Abs($xx-[int]$barcodeXBox.Value)))
                $barcodeHBox.Value=[decimal][Math]::Max(10,[Math]::Min(300,2*[Math]::Abs($yy-[int]$barcodeYBox.Value)))
            }
        }
        return
    }
    switch ([string]$dragTarget.SelectedItem) {
        'Block 1' { $xBox.Value=$xx; $yBox.Value=$yy }
        'Block 2' { $xBox2.Value=$xx; $yBox2.Value=$yy }
        'Image' { $imageXBox.Value=$xx; $imageYBox.Value=$yy }
        'Code128' { $barcodeXBox.Value=$xx; $barcodeYBox.Value=$yy }
        'QR' { $qrXBox.Value=$xx; $qrYBox.Value=$yy }
    }
})
$preview.Add_MouseUp({ try { & $render } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Preview error') | Out-Null } })
$previewBtn.Add_Click({ try { & $render } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Preview error') | Out-Null } })
$saveLayoutBtn.Add_Click({
    try {
        $dlg=New-Object Windows.Forms.SaveFileDialog; $dlg.Filter='Label layout (*.json)|*.json'; $dlg.FileName='THM_Layout.json'
        if ($dlg.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) {
            $layout=[pscustomobject]@{Version=7;PrintProfile=[string]$profileCombo.SelectedItem;StockWidthMm=[int]$stockWidthBox.Value;StockHeightMm=[int]$stockHeightBox.Value;CanvasWidth=780;CanvasHeight=366;Blocks=(& $getBlocks);Image=[pscustomobject]@{Path=$script:importedImagePath;X=[int]$imageXBox.Value;Y=[int]$imageYBox.Value;Width=[int]$imageWBox.Value;Height=[int]$imageHBox.Value;Data= $(if ($script:importedImagePath -and (Test-Path -LiteralPath $script:importedImagePath)) { [Convert]::ToBase64String([IO.File]::ReadAllBytes($script:importedImagePath)) } else { $null })};Barcode=[pscustomobject]@{Text=$barcodeBox.Text;X=[int]$barcodeXBox.Value;Y=[int]$barcodeYBox.Value;Width=[int]$barcodeWBox.Value;Height=[int]$barcodeHBox.Value};QR=[pscustomobject]@{Text=$qrBox.Text;X=[int]$qrXBox.Value;Y=[int]$qrYBox.Value;Size=[int]$qrSizeBox.Value}}
            $layout | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $dlg.FileName -Encoding UTF8
        }
    } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Save layout error') | Out-Null }
})
$loadLayoutBtn.Add_Click({
    try {
        $dlg=New-Object Windows.Forms.OpenFileDialog; $dlg.Filter='Label layout (*.json)|*.json'
        if ($dlg.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) {
            $layout=Get-Content -LiteralPath $dlg.FileName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($layout.Version -notin @(3,4,5,6,7) -or $layout.CanvasWidth -ne 780 -or $layout.CanvasHeight -ne 366 -or @($layout.Blocks).Count -ne 2) { throw 'Unsupported layout file' }
            if ($layout.Version -eq 7) { if ($layout.PrintProfile -and $profileCombo.Items.Contains([string]$layout.PrintProfile)) { $profileCombo.SelectedItem=[string]$layout.PrintProfile }; $stockWidthBox.Value=[decimal]$layout.StockWidthMm; $stockHeightBox.Value=[decimal]$layout.StockHeightMm } else { $stockWidthBox.Value=58; $stockHeightBox.Value=30 }
            $controls = @(
                ,@($textBox,$fontBox,$sizeBox,$alignBox,$boldBox,$xBox,$yBox,$rotationBox)
                ,@($textBox2,$fontBox2,$sizeBox2,$alignBox2,$boldBox2,$xBox2,$yBox2,$rotationBox2)
            )
            for ($i=0; $i -lt 2; $i++) {
                $block=$layout.Blocks[$i]; $c=$controls[$i]
                $c[0].Text=[string]$block.Text; $c[1].SelectedItem=[string]$block.Font
                $c[2].Value=[decimal]$block.Size; $c[3].SelectedItem=[string]$block.Align
                $c[4].Checked=[bool]$block.Bold; $c[5].Value=[decimal]$block.X
                $c[6].Value=[decimal]$block.Y; $c[7].SelectedItem=[string]$block.Rotation
            }
            $script:importedImagePath=''
            if ($layout.Version -ge 4 -and $null -ne $layout.Image) {
                $script:importedImagePath=[string]$layout.Image.Path
                $imageXBox.Value=[decimal]$layout.Image.X; $imageYBox.Value=[decimal]$layout.Image.Y
                $imageWBox.Value=[decimal]$layout.Image.Width; $imageHBox.Value=[decimal]$layout.Image.Height
            }
            if ($layout.Version -ge 5 -and $layout.Image.Data) {
                $embeddedDir = Join-Path $env:LOCALAPPDATA 'THMLabelStudio'
                [IO.Directory]::CreateDirectory($embeddedDir) | Out-Null
                $embeddedPath = Join-Path $embeddedDir ('embedded_' + [Guid]::NewGuid().ToString('N') + '.png')
                [IO.File]::WriteAllBytes($embeddedPath,[Convert]::FromBase64String([string]$layout.Image.Data))
                $script:importedImagePath = $embeddedPath
            }
            if ($layout.Version -ge 5 -and $layout.Barcode) {
                $barcodeBox.Text=[string]$layout.Barcode.Text
                $barcodeXBox.Value=[decimal]$layout.Barcode.X; $barcodeYBox.Value=[decimal]$layout.Barcode.Y
                $barcodeWBox.Value=[decimal]$layout.Barcode.Width; $barcodeHBox.Value=[decimal]$layout.Barcode.Height
            } else { $barcodeBox.Text='' }
            if ($layout.Version -ge 6 -and $layout.QR) {
                $qrBox.Text=[string]$layout.QR.Text
                $qrXBox.Value=[decimal]$layout.QR.X; $qrYBox.Value=[decimal]$layout.QR.Y
                $qrSizeBox.Value=[decimal]$layout.QR.Size
            } else { $qrBox.Text='' }
            $imagePathBox.Text=$script:importedImagePath
            & $render
        }
    } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Load layout error') | Out-Null }
})
$saveBtn.Add_Click({
    try {
        $job=& $makeJob
        $dlg=New-Object Windows.Forms.SaveFileDialog; $dlg.Filter='RAW binary (*.bin)|*.bin'; $dlg.FileName='THM_Custom_Label.bin'
        if ($dlg.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) { [IO.File]::WriteAllBytes($dlg.FileName,$job); [Windows.Forms.MessageBox]::Show("Saved $($job.Length) bytes",'RAW exported') | Out-Null }
    } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Export error') | Out-Null }
})
$printBtn.Add_Click({
    try {
        $job=& $makeJob
        $answer=[Windows.Forms.MessageBox]::Show("Confirm THM READY, M-Print PRO closed, selected profile and physical stock, ONE label?`n`n$($job.Length) bytes",'Confirm experimental print',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Warning)
        if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }
        $id=Send-Raw $job
        [Windows.Forms.MessageBox]::Show("Sent job #$id. Check printer display for READY or an error.",'Job sent') | Out-Null
    } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Print error') | Out-Null }
})
# Physical media metadata; do not infer THM Sl1/feed commands from PNG pixel dimensions.
Add-Label 'Stock width (mm)' 18 911 135
$stockWidthBox=Add-Number 155 907 1 300 58 78
Add-Label 'Stock height (mm)' 250 911 135
$stockHeightBox=Add-Number 390 907 1 300 30 78
$stockInfo=New-Object Windows.Forms.Label
$stockInfo.SetBounds(485,907,388,48)
$stockInfo.Text='Select captured profile and physical stock.'
$form.Controls.Add($stockInfo)
$profileCombo=New-Object Windows.Forms.ComboBox
$profileCombo.DropDownStyle=[Windows.Forms.ComboBoxStyle]::DropDownList
[void]$profileCombo.Items.Add('60x30 (58x30 physical)')
[void]$profileCombo.Items.Add('45x15 (43x25 physical)')
$profileCombo.SelectedIndex=0
$form.Controls.Add($profileCombo)
$profileLabel=New-Object Windows.Forms.Label
$profileLabel.Text='Captured print profile'; $form.Controls.Add($profileLabel)
$updateStockStatus = {
    $p=[string]$profileCombo.SelectedItem
    $verified=(($p -eq '60x30 (58x30 physical)') -and $stockWidthBox.Value -eq 58 -and $stockHeightBox.Value -eq 30) -or (($p -eq '45x15 (43x25 physical)') -and $stockWidthBox.Value -eq 43 -and $stockHeightBox.Value -eq 25)
    $printBtn.Enabled=$verified; $saveBtn.Enabled=$verified
    if ($verified) { $stockInfo.Text='Profile matches stock. Experimental printing enabled; test ONE label first.'; $stockInfo.ForeColor=[Drawing.Color]::DarkGreen }
    else { $stockInfo.Text='Profile / stock mismatch: preview only, RAW and printing blocked.'; $stockInfo.ForeColor=[Drawing.Color]::DarkRed }
}
$profileCombo.Add_SelectedIndexChanged({
    if ($profileCombo.SelectedIndex -eq 0) { $stockWidthBox.Value=58; $stockHeightBox.Value=30 }
    else { $stockWidthBox.Value=43; $stockHeightBox.Value=25 }
    & $updateStockStatus
})
$stockWidthBox.Add_ValueChanged({ & $updateStockStatus })
$stockHeightBox.Add_ValueChanged({ & $updateStockStatus })
# v0.8.3 compact editor: no horizontal scrolling in the settings panel.
$form.Text = 'THM Label Studio 0.11 TEST - Batch dispatcher'
$form.ClientSize = [Drawing.Size]::new(1280,760)
$form.MinimumSize = [Drawing.Size]::new(1030,680)
$form.AutoScroll = $false
$form.BackColor = [Drawing.Color]::FromArgb(246,247,249)
$tabs = New-Object Windows.Forms.TabControl
$tabs.SetBounds(12,12,450,730)
$tabs.Anchor = [Windows.Forms.AnchorStyles]::Top -bor [Windows.Forms.AnchorStyles]::Bottom -bor [Windows.Forms.AnchorStyles]::Left
$tabText = New-Object Windows.Forms.TabPage; $tabText.Text='Text'
$tabImage = New-Object Windows.Forms.TabPage; $tabImage.Text='Images'
$tabBarcode = New-Object Windows.Forms.TabPage; $tabBarcode.Text='Code 128'
$tabQr = New-Object Windows.Forms.TabPage; $tabQr.Text='QR'
foreach ($tab in @($tabText,$tabImage,$tabBarcode,$tabQr)) {
    $tab.AutoScroll=$true
    $tab.BackColor=[Drawing.Color]::White
    [void]$tabs.TabPages.Add($tab)
}
# Preserve existing controls and event handlers. Move controls to their tabs.
$keep=@($preview,$previewBtn,$saveLayoutBtn,$loadLayoutBtn,$saveBtn,$printBtn,$stockWidthBox,$stockHeightBox,$stockInfo,$profileCombo,$profileLabel,$dragTarget,$mouseMode)
foreach ($ctl in @($form.Controls | ForEach-Object { $_ })) {
    if ($keep -contains $ctl) { continue }
    $y=$ctl.Top
    if ($ctl -eq $qrHelpBtn) { $tabQr.Controls.Add($ctl) }
    elseif ($ctl -is [Windows.Forms.Label] -and ($ctl.Text -eq 'Drag target' -or $ctl.Text -eq 'Mouse mode')) { $form.Controls.Remove($ctl); $ctl.Dispose() }
    elseif ($y -lt 255 -or $ctl -eq $note) { $tabText.Controls.Add($ctl) }
    elseif ($y -ge 298 -and $y -lt 365) { $tabImage.Controls.Add($ctl) }
    elseif ($y -ge 365 -and $y -lt 406) { $tabBarcode.Controls.Add($ctl) }
    elseif ($y -ge 406 -and $y -lt 470) { $tabQr.Controls.Add($ctl) }
}
# The two text blocks remain independently editable, but one is shown at a time.
$blockSelector = New-Object Windows.Forms.ComboBox
$blockSelector.DropDownStyle='DropDownList'
[void]$blockSelector.Items.AddRange([object[]]@('Text 1','Text 2'))
$blockSelector.SelectedIndex=0
$blockSelector.SetBounds(18,42,396,28)
$tabText.Controls.Add($blockSelector)
$sectionTitle=New-Object Windows.Forms.Label
$sectionTitle.Text='TEXT CONTENT'; $sectionTitle.Font=[Drawing.Font]::new('Segoe UI',10,[Drawing.FontStyle]::Bold)
$sectionTitle.SetBounds(18,15,390,22); $tabText.Controls.Add($sectionTitle)
$sectionStyle=New-Object Windows.Forms.Label
$sectionStyle.Text='FONT AND STYLE'; $sectionStyle.Font=[Drawing.Font]::new('Segoe UI',10,[Drawing.FontStyle]::Bold)
$sectionStyle.SetBounds(18,180,390,22); $tabText.Controls.Add($sectionStyle)
$sectionPosition=New-Object Windows.Forms.Label
$sectionPosition.Text='POSITION AND ROTATION'; $sectionPosition.Font=[Drawing.Font]::new('Segoe UI',10,[Drawing.FontStyle]::Bold)
$sectionPosition.SetBounds(18,356,390,22); $tabText.Controls.Add($sectionPosition)
# Reuse both original sets of controls so save/load/render logic stays intact.
$set1=@($textBox,$fontBox,$sizeBox,$alignBox,$boldBox,$xBox,$yBox,$rotationBox)
$set2=@($textBox2,$fontBox2,$sizeBox2,$alignBox2,$boldBox2,$xBox2,$yBox2,$rotationBox2)
foreach($ctl in $set1+$set2) { $ctl.Visible=$false }
function Position-TextEditor([int]$which) {
    $active=if($which -eq 0){$set1}else{$set2}
    $inactive=if($which -eq 0){$set2}else{$set1}
    foreach($ctl in $inactive){$ctl.Visible=$false}
    $active[0].SetBounds(18,108,396,48)
    $active[0].Multiline=$true
    $active[1].SetBounds(18,237,244,28)
    $active[2].SetBounds(282,237,132,28)
    $active[3].SetBounds(18,308,244,28)
    $active[4].SetBounds(284,308,28,28)
    $active[5].SetBounds(18,419,186,28)
    $active[6].SetBounds(228,419,186,28)
    $active[7].SetBounds(18,491,396,28)
    foreach($ctl in $active){$ctl.Visible=$true}
}
$blockSelector.Add_SelectedIndexChanged({ Position-TextEditor $blockSelector.SelectedIndex })
# Remove old labels, replace with grouped captions.
foreach($ctl in @($tabText.Controls | ForEach-Object { $_ })) {
    if ($ctl -is [Windows.Forms.Label] -and $ctl -notin @($sectionTitle,$sectionStyle,$sectionPosition)) {
        $tabText.Controls.Remove($ctl); $ctl.Dispose()
    }
}
function Add-EditorCaption($tab,$caption,$x,$y,$w=160) {
    $l=New-Object Windows.Forms.Label
    $l.Text=$caption; $l.SetBounds($x,$y,$w,22)
    $l.ForeColor=[Drawing.Color]::FromArgb(75,85,99)
    $tab.Controls.Add($l)
}
Add-EditorCaption $tabText 'Content' 18 84
Add-EditorCaption $tabText 'Font family' 18 212
Add-EditorCaption $tabText 'Size (px)' 282 212
Add-EditorCaption $tabText 'Alignment' 18 283
Add-EditorCaption $tabText 'Bold' 282 283
Add-EditorCaption $tabText 'X center' 18 394
Add-EditorCaption $tabText 'Y center' 228 394
Add-EditorCaption $tabText 'Rotation' 18 466
$note=New-Object Windows.Forms.Label
$note.Text='Captured profiles: 60x30 and 45x15. Experimental printing.'
$note.ForeColor=[Drawing.Color]::DarkSlateGray
$note.SetBounds(18,552,396,48)
$tabText.Controls.Add($note)
Position-TextEditor 0
# Compact controls on other tabs: no horizontal scroll.
$imagePathBox.SetBounds(18,68,396,28)
$imageLoadBtn.SetBounds(18,110,190,32)
$imageClearBtn.SetBounds(224,110,190,32)
$imageXBox.SetBounds(18,195,180,28); $imageYBox.SetBounds(234,195,180,28)
$imageWBox.SetBounds(18,270,180,28); $imageHBox.SetBounds(234,270,180,28)
$barcodeBox.SetBounds(18,68,396,30)
$barcodeXBox.SetBounds(18,156,180,28); $barcodeYBox.SetBounds(234,156,180,28)
$barcodeWBox.SetBounds(18,231,180,28); $barcodeHBox.SetBounds(234,231,180,28)
$qrBox.SetBounds(18,68,396,30)
$qrXBox.SetBounds(18,156,180,28); $qrYBox.SetBounds(234,156,180,28)
$qrSizeBox.SetBounds(18,231,180,28)
$qrHelpBtn.SetBounds(234,231,180,30)
$qrNote.SetBounds(18,285,396,55)
foreach($tab in @($tabImage,$tabBarcode,$tabQr)) {
    foreach($ctl in @($tab.Controls | ForEach-Object { $_ })) {
        if ($ctl -is [Windows.Forms.Label] -and $ctl -ne $qrNote) { $tab.Controls.Remove($ctl); $ctl.Dispose() }
    }
}
Add-EditorCaption $tabImage 'Image file' 18 42
Add-EditorCaption $tabImage 'X center' 18 169
Add-EditorCaption $tabImage 'Y center' 234 169
Add-EditorCaption $tabImage 'Width' 18 244
Add-EditorCaption $tabImage 'Height' 234 244
Add-EditorCaption $tabBarcode 'Code 128 content (ASCII)' 18 42 350
Add-EditorCaption $tabBarcode 'X center' 18 130
Add-EditorCaption $tabBarcode 'Y center' 234 130
Add-EditorCaption $tabBarcode 'Width' 18 205
Add-EditorCaption $tabBarcode 'Height' 234 205
Add-EditorCaption $tabQr 'QR content' 18 42
Add-EditorCaption $tabQr 'X center' 18 130
Add-EditorCaption $tabQr 'Y center' 234 130
Add-EditorCaption $tabQr 'Size' 18 205
$form.Controls.Add($tabs)
$objectLabel=New-Object Windows.Forms.Label
$objectLabel.Text='Selected object'; $form.Controls.Add($objectLabel)
$modeLabel=New-Object Windows.Forms.Label
$modeLabel.Text='Mouse action'; $form.Controls.Add($modeLabel)
$previewTitle=New-Object Windows.Forms.Label
$previewTitle.Text='Label preview  |  780 x 366 px'; $form.Controls.Add($previewTitle)
$stockWidthLabel=New-Object Windows.Forms.Label
$stockWidthLabel.Text='Stock width (mm)'; $form.Controls.Add($stockWidthLabel)
$stockHeightLabel=New-Object Windows.Forms.Label
$stockHeightLabel.Text='Stock height (mm)'; $form.Controls.Add($stockHeightLabel)
foreach($ctl in @($form.Controls | ForEach-Object { $_ })) {
    if ($ctl -is [Windows.Forms.Label] -and $ctl -notin @($objectLabel,$modeLabel,$previewTitle,$stockWidthLabel,$stockHeightLabel,$stockInfo)) {
        if ($ctl.Text -in @('Stock width (mm)','Stock height (mm)')) { $form.Controls.Remove($ctl); $ctl.Dispose() }
    }
}
$reflow={
    $left=484; $right=$form.ClientSize.Width-18
    $avail=[Math]::Max(510,$right-$left)
    $objectLabel.SetBounds($left,25,155,22)
    $dragTarget.SetBounds($left,49,180,27)
    $modeLabel.SetBounds(($left+195),25,155,22)
    $mouseMode.SetBounds(($left+195),49,180,27)
    $previewTitle.SetBounds($left,94,330,24)
    $pvW=[Math]::Min($avail,[Math]::Max(400,[int](($form.ClientSize.Height-335)*780.0/366.0)))
    $pvH=[int]($pvW*366.0/780.0)
    $preview.SetBounds($left,124,$pvW,$pvH)
    $by=138+$pvH
    $previewBtn.SetBounds($left,$by,145,34)
    $saveLayoutBtn.SetBounds(($left+153),$by,120,34)
    $loadLayoutBtn.SetBounds(($left+281),$by,120,34)
    $saveBtn.SetBounds(($left+409),$by,95,34)
    $printBtn.SetBounds($left,($by+48),190,38)
    $tabs.Height=$form.ClientSize.Height-26
}
$form.Add_Resize({ & $reflow })
& $reflow
& $updateStockStatus
# Click on the preview selects the nearest existing object, while preserving drag behavior.
$preview.Add_MouseDown({ param($sender,$e)
    if ($e.Button -ne [Windows.Forms.MouseButtons]::Left) { return }
    $iw=780.0; $ih=366.0
    $scale=[Math]::Min($preview.ClientSize.Width/$iw,$preview.ClientSize.Height/$ih)
    if ($scale -le 0) { return }
    $ox=($preview.ClientSize.Width-$iw*$scale)/2
    $oy=($preview.ClientSize.Height-$ih*$scale)/2
    $px=($e.X-$ox)/$scale; $py=($e.Y-$oy)/$scale
    $candidates=@()
    if ($textBox.Text.Trim()) { $candidates+=@([pscustomobject]@{Name='Block 1';X=[double]$xBox.Value;Y=[double]$yBox.Value}) }
    if ($textBox2.Text.Trim()) { $candidates+=@([pscustomobject]@{Name='Block 2';X=[double]$xBox2.Value;Y=[double]$yBox2.Value}) }
    if ($script:importedImagePath) { $candidates+=@([pscustomobject]@{Name='Image';X=[double]$imageXBox.Value;Y=[double]$imageYBox.Value}) }
    if ($barcodeBox.Text.Trim()) { $candidates+=@([pscustomobject]@{Name='Code128';X=[double]$barcodeXBox.Value;Y=[double]$barcodeYBox.Value}) }
    if ($qrBox.Text.Trim()) { $candidates+=@([pscustomobject]@{Name='QR';X=[double]$qrXBox.Value;Y=[double]$qrYBox.Value}) }
    $closest=$candidates | Sort-Object { [Math]::Pow($_.X-$px,2)+[Math]::Pow($_.Y-$py,2) } | Select-Object -First 1
    if ($closest) {
        $dragTarget.SelectedItem=$closest.Name
        if ($closest.Name -eq 'Block 1') { $tabs.SelectedTab=$tabText; $blockSelector.SelectedIndex=0 }
        elseif ($closest.Name -eq 'Block 2') { $tabs.SelectedTab=$tabText; $blockSelector.SelectedIndex=1 }
        elseif ($closest.Name -eq 'Image') { $tabs.SelectedTab=$tabImage }
        elseif ($closest.Name -eq 'Code128') { $tabs.SelectedTab=$tabBarcode }
        elseif ($closest.Name -eq 'QR') { $tabs.SelectedTab=$tabQr }
    }
})

# v0.10: Excel/CSV batch printing. This module reuses the tested RAW generator.
$batchTab=New-Object Windows.Forms.TabPage
$batchTab.Text='Batch Excel'
$batchTab.AutoScroll=$true
$batchTab.BackColor=[Drawing.Color]::White
[void]$tabs.TabPages.Add($batchTab)
function Batch-Label([string]$title,[int]$y) {
    $c=New-Object Windows.Forms.Label
    $c.Text=$title; $c.SetBounds(14,$y,410,22)
    $batchTab.Controls.Add($c)
}
function Batch-Combo([int]$y) {
    $c=New-Object Windows.Forms.ComboBox
    $c.DropDownStyle='DropDownList'; $c.SetBounds(14,$y,404,28)
    $batchTab.Controls.Add($c)
    return $c
}
Batch-Label 'Source: Excel (.xlsx) or CSV (.csv)' 15
$batchOpen=New-Object Windows.Forms.Button
$batchOpen.Text='Open Excel / CSV'; $batchOpen.SetBounds(14,43,180,32); $batchTab.Controls.Add($batchOpen)
$batchFile=New-Object Windows.Forms.Label
$batchFile.SetBounds(14,82,410,40); $batchFile.Text='No file loaded'; $batchTab.Controls.Add($batchFile)
Batch-Label 'CSV delimiter (only for CSV files)' 125
$batchDelimiter=Batch-Combo 150
[void]$batchDelimiter.Items.AddRange([object[]]@('Semicolon ;','Comma ,','Tab'))
$batchDelimiter.SelectedIndex=0
Batch-Label 'Column -> Text 1' 191
$batchText1=Batch-Combo 215
Batch-Label 'Column -> Text 2' 253
$batchText2=Batch-Combo 277
Batch-Label 'Column -> Code 128' 315
$batchCode=Batch-Combo 339
Batch-Label 'Column -> QR' 377
$batchQr=Batch-Combo 401
Batch-Label 'Column -> Copies (optional)' 439
$batchQty=Batch-Combo 463
$batchSummary=New-Object Windows.Forms.Label
$batchSummary.SetBounds(14,505,410,46)
$batchSummary.Text='Load a file, then map its columns.'
$batchTab.Controls.Add($batchSummary)
$batchPrev=New-Object Windows.Forms.Button
$batchPrev.Text='Preview row 1'; $batchPrev.SetBounds(14,557,188,34); $batchTab.Controls.Add($batchPrev)
$batchPrint=New-Object Windows.Forms.Button
$batchPrint.Text='Print batch'; $batchPrint.SetBounds(213,557,205,34); $batchTab.Controls.Add($batchPrint)
$batchStatus=New-Object Windows.Forms.Label
$batchStatus.SetBounds(14,603,410,75); $batchStatus.Text='Test with 2-5 rows first. Limit: 100 labels per run.'
$batchTab.Controls.Add($batchStatus)
# Persistent, navigable batch preview: do not restore editor values on a modal OK.
$batchPrevRow=New-Object Windows.Forms.Button
$batchPrevRow.Text='< Previous'; $batchPrevRow.SetBounds(14,685,125,32); $batchTab.Controls.Add($batchPrevRow)
$batchNextRow=New-Object Windows.Forms.Button
$batchNextRow.Text='Next >'; $batchNextRow.SetBounds(148,685,125,32); $batchTab.Controls.Add($batchNextRow)
$batchBack=New-Object Windows.Forms.Button
$batchBack.Text='Return to layout'; $batchBack.SetBounds(282,685,136,32); $batchTab.Controls.Add($batchBack)
$batchPrevRow.Enabled=$false
$batchNextRow.Enabled=$false
$batchBack.Enabled=$false
$script:batchPreviewActive=$false
$script:batchPreviewIndex=0
$script:batchRows=@()
$script:batchColumns=@()
$script:batchSource=''
$script:batchOriginal=@{}
function Batch-ReadRows([string]$path) {
    if ([IO.Path]::GetExtension($path).ToLowerInvariant() -eq '.csv') {
        $delimiter= switch ($batchDelimiter.SelectedIndex) { 1 { ',' } 2 { "`t" } default { ';' } }
        return @(Import-Csv -LiteralPath $path -Delimiter $delimiter -Encoding UTF8 -ErrorAction Stop)
    }
    # Excel desktop automation is used only to read a local workbook; no macros are run.
    $excel=$null; $book=$null; $sheet=$null; $range=$null
    try {
        $excel=New-Object -ComObject Excel.Application
        $excel.Visible=$false; $excel.DisplayAlerts=$false
        $excel.AutomationSecurity=3
        $book=$excel.Workbooks.Open($path,0,$true)
        $sheet=$book.Worksheets.Item(1)
        $range=$sheet.UsedRange
        $nRows=[int]$range.Rows.Count; $nCols=[int]$range.Columns.Count
        if ($nRows -gt 10001 -or $nCols -gt 100) { throw 'Workbook too large (max 10000 rows, 100 columns)' }
        if ($nRows -lt 2) { throw 'Workbook has no data rows' }
        $headers=@()
        for($c=1;$c -le $nCols;$c++) {
            $h=[string]$range.Cells.Item(1,$c).Text
            if ([string]::IsNullOrWhiteSpace($h)) { $h="Column$c" }
            if ($headers -contains $h) { $h="${h}_$c" }
            $headers+= $h
        }
        $rows=New-Object System.Collections.ArrayList
        for($r=2;$r -le $nRows;$r++) {
            $entry=[ordered]@{}; $hasData=$false
            for($c=1;$c -le $nCols;$c++) {
                $v=[string]$range.Cells.Item($r,$c).Text
                if ($v.Trim()) { $hasData=$true }
                $entry[$headers[$c-1]]=$v
            }
            if ($hasData) { [void]$rows.Add([pscustomobject]$entry) }
        }
        return $rows.ToArray()
    } finally {
        if ($book) { $book.Close($false) | Out-Null }
        if ($excel) { $excel.Quit() }
        foreach($obj in @($range,$sheet,$book,$excel)) {
            if ($obj) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($obj) }
        }
    }
}
function Batch-Cell($row,$combo) {
    $column=[string]$combo.SelectedItem
    if (-not $column -or $column -eq '(none)') { return '' }
    return [string]$row.PSObject.Properties[$column].Value
}
function Batch-SetRow($row) {
    $textBox.Text=Batch-Cell $row $batchText1
    $textBox2.Text=Batch-Cell $row $batchText2
    $barcodeBox.Text=Batch-Cell $row $batchCode
    $qrBox.Text=Batch-Cell $row $batchQr
}
function Batch-Copies($row) {
    $value=Batch-Cell $row $batchQty
    if (-not $value.Trim()) { return 1 }
    $qty=0
    if (-not [int]::TryParse($value,[ref]$qty) -or $qty -lt 1 -or $qty -gt 100) { throw "Invalid copies '$value'; expected 1-100" }
    return $qty
}
function Batch-Remember {
    $script:batchOriginal=@{T1=$textBox.Text;T2=$textBox2.Text;Code=$barcodeBox.Text;QR=$qrBox.Text}
}
function Batch-Restore {
    $textBox.Text=$script:batchOriginal.T1
    $textBox2.Text=$script:batchOriginal.T2
    $barcodeBox.Text=$script:batchOriginal.Code
    $qrBox.Text=$script:batchOriginal.QR
    & $render
}
function Batch-ExitPreview {
    if (-not $script:batchPreviewActive) { return }
    $script:batchPreviewActive=$false
    Batch-Restore
    $batchPrevRow.Enabled=$false
    $batchNextRow.Enabled=$false
    $batchBack.Enabled=$false
    $batchPrev.Text='Preview row 1'
    $batchStatus.Text='Original layout restored. Batch source and mapping are preserved.'
}
function Batch-ShowPreviewRow([int]$index) {
    if ($script:batchRows.Count -eq 0) { return }
    if ($index -lt 0 -or $index -ge $script:batchRows.Count) { return }
    if (-not $script:batchPreviewActive) {
        Batch-Remember
        $script:batchPreviewActive=$true
    }
    $script:batchPreviewIndex=$index
    Batch-SetRow $script:batchRows[$index]
    & $render
    $rowNumber=$index+1
    $batchStatus.Text="PREVIEW ONLY: row $rowNumber / $($script:batchRows.Count). No print job sent. Use Return to layout to restore editor values."
    $batchPrevRow.Enabled=($index -gt 0)
    $batchNextRow.Enabled=($index -lt ($script:batchRows.Count-1))
    $batchBack.Enabled=$true
    $batchPrev.Text="Preview row $rowNumber"
}
$batchPrevRow.Add_Click({
    try { Batch-ShowPreviewRow ($script:batchPreviewIndex-1) }
    catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Preview error') | Out-Null }
})
$batchNextRow.Add_Click({
    try { Batch-ShowPreviewRow ($script:batchPreviewIndex+1) }
    catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Preview error') | Out-Null }
})
$batchBack.Add_Click({ Batch-ExitPreview })
$batchOpen.Add_Click({
    try {
        Batch-ExitPreview
        $dlg=New-Object Windows.Forms.OpenFileDialog
        $dlg.Filter='Excel or CSV (*.xlsx;*.csv)|*.xlsx;*.csv|Excel (*.xlsx)|*.xlsx|CSV (*.csv)|*.csv'
        if ($dlg.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { return }
        $script:batchRows=@(Batch-ReadRows $dlg.FileName)
        if ($script:batchRows.Count -eq 0) { throw 'No data rows found' }
        if ($script:batchRows[0] -is [System.Array]) { throw 'Nested row array detected. Batch import was cancelled.' }
        $script:batchColumns=@($script:batchRows[0].PSObject.Properties.Name)
        if ($script:batchColumns.Count -lt 1 -or $script:batchColumns.Count -gt 100) { throw 'Invalid columns in imported file.' }
        $script:batchSource=$dlg.FileName
        foreach($combo in @($batchText1,$batchText2,$batchCode,$batchQr,$batchQty)) {
            $combo.Items.Clear()
            [void]$combo.Items.Add('(none)')
            foreach($column in $script:batchColumns) { [void]$combo.Items.Add([string]$column) }
            $combo.SelectedIndex=0
        }
        # Prefer named columns for a consistent, safe first preview.
        foreach($pair in @(@($batchText1,'Text1'),@($batchText2,'Text2'),@($batchCode,'Code128'),@($batchQr,'QR'),@($batchQty,'Copies'))) {
            $idx=$pair[0].Items.IndexOf($pair[1])
            if ($idx -ge 0) { $pair[0].SelectedIndex=$idx }
        }
        if ($batchText1.SelectedIndex -eq 0 -and $batchColumns.Count -gt 0) { $batchText1.SelectedIndex=1 }
        $batchFile.Text=[IO.Path]::GetFileName($dlg.FileName)
        $batchSummary.Text="Rows: $($script:batchRows.Count) | Columns: $($script:batchColumns.Count)"
        $batchStatus.Text='File loaded. Set column mapping, preview, then print.'
    } catch { $script:batchRows=@(); [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Import error') | Out-Null }
})
$batchPrev.Add_Click({
    if ($script:batchRows.Count -eq 0) { return }
    try {
        if ($script:batchPreviewActive) {
            Batch-ShowPreviewRow $script:batchPreviewIndex
        } else {
            Batch-ShowPreviewRow 0
        }
    } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Preview error') | Out-Null }
})
# v0.11 dispatcher. Send-Raw and the captured printer profiles remain unchanged.
# Accepted means submitted to Windows spooler, NOT physical printing confirmation.
$batchPrint.Text='Start batch'
$batchStartLabel=New-Object Windows.Forms.Label
$batchStartLabel.Text='Start at Excel row (1-based)'; $batchStartLabel.SetBounds(14,735,240,22)
$batchTab.Controls.Add($batchStartLabel)
$batchStartAt=New-Object Windows.Forms.NumericUpDown
$batchStartAt.Minimum=1; $batchStartAt.Maximum=10000; $batchStartAt.Value=1
$batchStartAt.SetBounds(270,731,148,28); $batchTab.Controls.Add($batchStartAt)
$batchStop=New-Object Windows.Forms.Button
$batchStop.Text='Pause dispatch'; $batchStop.SetBounds(14,774,190,34)
$batchStop.Enabled=$false; $batchTab.Controls.Add($batchStop)
$batchResume=New-Object Windows.Forms.Button
$batchResume.Text='Resume pending'; $batchResume.SetBounds(213,774,205,34)
$batchResume.Enabled=$false; $batchTab.Controls.Add($batchResume)
$batchProgress=New-Object Windows.Forms.ProgressBar
$batchProgress.Minimum=0; $batchProgress.Maximum=1; $batchProgress.Value=0
$batchProgress.SetBounds(14,822,404,22); $batchTab.Controls.Add($batchProgress)
$batchLogTitle=New-Object Windows.Forms.Label
$batchLogTitle.Text='Dispatch journal (submitted to Windows; not verified printed)'
$batchLogTitle.SetBounds(14,861,410,33); $batchTab.Controls.Add($batchLogTitle)
$batchLog=New-Object Windows.Forms.TextBox
$batchLog.Multiline=$true; $batchLog.ReadOnly=$true; $batchLog.ScrollBars='Vertical'
$batchLog.SetBounds(14,899,404,142); $batchTab.Controls.Add($batchLog)
$script:batchTasks=@()
$script:batchCursor=0
$script:batchRunning=$false
$script:batchBusy=$false
$script:batchCsvLog=''
$script:batchRunId=''
$script:batchOriginalSaved=$false
$batchTimer=New-Object Windows.Forms.Timer
$batchTimer.Interval=650
function Batch-WriteJournal([string]$result,[string]$details,[int]$jobId) {
    $task=$null
    if ($script:batchCursor -lt $script:batchTasks.Count) { $task=$script:batchTasks[$script:batchCursor] }
    $rowNumber=if($task){[int]$task.RowNumber}else{0}
    $copyNumber=if($task){[int]$task.CopyNumber}else{0}
    $at=[DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')
    $line="$at | $result | row $rowNumber | copy $copyNumber | spool $jobId | $details"
    $batchLog.AppendText($line+[Environment]::NewLine)
    if ($script:batchCsvLog) {
        $record=[pscustomobject][ordered]@{
            Timestamp=$at;RunId=$script:batchRunId;Source=$script:batchSource
            ExcelRow=$rowNumber;Copy=$copyNumber;Result=$result;SpoolJobId=$jobId;Details=$details
        }
        $record | Export-Csv -LiteralPath $script:batchCsvLog -NoTypeInformation -Encoding UTF8 -Append
    }
}
function Batch-UpdateDispatcher {
    $count=$script:batchTasks.Count
    $batchProgress.Maximum=[Math]::Max(1,$count)
    $batchProgress.Value=[Math]::Min($script:batchCursor,$batchProgress.Maximum)
    $batchStop.Enabled=$script:batchRunning
    $batchResume.Enabled=(-not $script:batchRunning -and $script:batchCursor -lt $count -and $count -gt 0)
    $batchPrint.Enabled=(-not $script:batchRunning)
    $batchOpen.Enabled=(-not $script:batchRunning)
    $batchStartAt.Enabled=(-not $script:batchRunning)
    if ($count) {
        $status=if($script:batchRunning){'Dispatching'}elseif($script:batchCursor -eq $count){'All jobs submitted'}else{'Paused'}
        $batchStatus.Text="$status. Submitted: $($script:batchCursor) / $count. NOT physically verified.`nLog: $($script:batchCsvLog)"
    }
}
function Batch-FinishDispatcher([string]$message) {
    $batchTimer.Stop()
    $script:batchRunning=$false
    if ($script:batchOriginalSaved) { Batch-Restore; $script:batchOriginalSaved=$false }
    Batch-UpdateDispatcher
    $batchLog.AppendText($message+[Environment]::NewLine)
}
$batchTimer.Add_Tick({
    if (-not $script:batchRunning -or $script:batchBusy) { return }
    $batchTimer.Stop()
    $script:batchBusy=$true
    try {
        if ($script:batchCursor -ge $script:batchTasks.Count) {
            Batch-FinishDispatcher 'All tasks submitted to Windows spooler; check physical labels and READY state.'
            return
        }
        # Send-Raw itself requires an empty Windows queue. Do not enqueue a second job early.
        $pending=@(Get-PrintJob -PrinterName 'THM MultiMark TEST' -ErrorAction Stop)
        if ($pending.Count -gt 0) {
            $batchStatus.Text="Waiting for Windows spooler to clear ($($pending.Count) job(s)); submitted $($script:batchCursor)/$($script:batchTasks.Count). Not physical confirmation."
            return
        }
        $task=$script:batchTasks[$script:batchCursor]
        Batch-SetRow $script:batchRows[$task.RowIndex]
        $raw=& $makeJob
        $jobId=Send-Raw $raw
        # Advance only after Send-Raw reports submission; failed jobs stay pending.
        Batch-WriteJournal 'Submitted' 'Windows spooler accepted the RAW job; physical output NOT confirmed' ([int]$jobId)
        $script:batchCursor++
        Batch-UpdateDispatcher
        if ($script:batchCursor -ge $script:batchTasks.Count) {
            Batch-FinishDispatcher 'All tasks submitted. Verify actual labels and printer READY state.'
        }
    } catch {
        try { Batch-WriteJournal 'Error' $_.Exception.Message 0 } catch {}
        Batch-FinishDispatcher ('Paused after error: '+$_.Exception.Message)
        [Windows.Forms.MessageBox]::Show("Dispatch paused. Pending tasks were NOT marked submitted.`n$($_.Exception.Message)",'Batch dispatch error') | Out-Null
    } finally {
        $script:batchBusy=$false
        if ($script:batchRunning) { $batchTimer.Start() }
    }
})
$batchStop.Add_Click({
    if ($script:batchRunning) {
        $batchTimer.Stop(); $script:batchRunning=$false
        if ($script:batchOriginalSaved) { Batch-Restore; $script:batchOriginalSaved=$false }
        Batch-UpdateDispatcher
        $batchLog.AppendText("PAUSED at $($script:batchCursor) / $($script:batchTasks.Count). Already submitted jobs cannot be cancelled by this control."+[Environment]::NewLine)
    }
})
$batchResume.Add_Click({
    if ($script:batchRunning -or $script:batchCursor -ge $script:batchTasks.Count) { return }
    # An uncertain printer/driver failure can lead to a duplicate on retry. Require confirmation.
    $answer=[Windows.Forms.MessageBox]::Show("Resume from pending task $($script:batchCursor+1)?`nPreviously submitted jobs will NOT be resent by the app.`nIf Windows reported an ambiguous error, inspect printed labels first to avoid duplicates.",'Resume batch',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Warning)
    if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }
    Batch-Remember; $script:batchOriginalSaved=$true
    $script:batchRunning=$true
    Batch-UpdateDispatcher
    $batchTimer.Start()
})
$batchPrint.Add_Click({
    if ($script:batchRunning -or $script:batchRows.Count -eq 0) { return }
    try {
        Batch-ExitPreview
        $start=[int]$batchStartAt.Value
        if ($start -gt $script:batchRows.Count) { throw 'Start row exceeds the imported data row count.' }
        $tasks=New-Object System.Collections.ArrayList
        for ($r=$start-1; $r -lt $script:batchRows.Count; $r++) {
            $qty=Batch-Copies $script:batchRows[$r]
            for ($k=1; $k -le $qty; $k++) {
                [void]$tasks.Add([pscustomobject]@{RowIndex=$r;RowNumber=($r+1);CopyNumber=$k})
                if ($tasks.Count -gt 100) { throw 'More than 100 labels requested. Split into smaller batches.' }
            }
        }
        if ($tasks.Count -eq 0) { throw 'No labels to print.' }
        $answer=[Windows.Forms.MessageBox]::Show("Start NEW batch: $($tasks.Count) jobs from Excel row $start?`nCheck correct stock and printer READY before proceeding.`nJobs accepted by Windows are not proof of physical printing. Re-running the same batch can print duplicates.",'Confirm NEW batch',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Warning)
        if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }
        $script:batchTasks=@($tasks.ToArray())
        $script:batchCursor=0
        $script:batchRunId=[DateTime]::Now.ToString('yyyyMMdd_HHmmss_fff')
        $directory=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'THMLabelStudio\Logs'
        if (-not (Test-Path -LiteralPath $directory)) { [void](New-Item -ItemType Directory -Path $directory -Force) }
        $script:batchCsvLog=Join-Path $directory ("batch_$($script:batchRunId).csv")
        # Create header before dispatch; no jobs submitted if logging cannot start.
        'Timestamp,RunId,Source,ExcelRow,Copy,Result,SpoolJobId,Details' | Set-Content -LiteralPath $script:batchCsvLog -Encoding UTF8
        $batchLog.Clear()
        $batchLog.AppendText("New batch: $($script:batchTasks.Count) RAW tasks; Excel row $start onward."+[Environment]::NewLine)
        Batch-Remember; $script:batchOriginalSaved=$true
        $script:batchRunning=$true
        Batch-UpdateDispatcher
        $batchTimer.Start()
    } catch {
        [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Cannot start batch') | Out-Null
    }
})
$form.Add_FormClosing({
    if ($script:batchRunning) {
        $decision=[Windows.Forms.MessageBox]::Show('Batch dispatch is active. Stop submitting further jobs and close? Already submitted jobs may still print.','Close during batch',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Warning)
        if ($decision -ne [Windows.Forms.DialogResult]::Yes) { $_.Cancel=$true; return }
        $script:batchRunning=$false
        $batchTimer.Stop()
    }
})

# v0.10.3: preserve profile controls during initial reparenting so the profile Label is not disposed.
# Print profile controls live in a visible, dedicated tab.
# Keep the established RAW profile and batch-print handlers unchanged.
$stockTab=New-Object Windows.Forms.TabPage
$stockTab.Text='Print / Stock'
$stockTab.AutoScroll=$true
$stockTab.BackColor=[Drawing.Color]::White
[void]$tabs.TabPages.Add($stockTab)
foreach($control in @($profileLabel,$profileCombo,$stockWidthLabel,$stockWidthBox,$stockHeightLabel,$stockHeightBox,$stockInfo)) {
    $stockTab.Controls.Add($control)
}
$profileLabel.Text='Captured print profile (M-Print PRO)'
$profileLabel.SetBounds(18,22,395,24)
$profileCombo.SetBounds(18,52,395,30)
$profileCombo.DropDownWidth=410
$stockWidthLabel.SetBounds(18,110,180,24)
$stockWidthBox.SetBounds(18,138,170,28)
$stockHeightLabel.SetBounds(225,110,180,24)
$stockHeightBox.SetBounds(225,138,170,28)
$stockInfo.SetBounds(18,192,395,75)
$stockInfo.AutoSize=$false
$stockInfo.MaximumSize=[Drawing.Size]::new(395,0)
$stockHelp=New-Object Windows.Forms.Label
$stockHelp.Text="60 x 30 profile: 58 x 30 mm physical labels on 60 mm backing.`n45 x 15 profile: 43 x 25 mm physical labels on 45 mm backing.`n`nSelect a profile before printing or running an Excel batch."
$stockHelp.SetBounds(18,292,395,120)
$stockHelp.ForeColor=[Drawing.Color]::FromArgb(75,85,99)
$stockTab.Controls.Add($stockHelp)
& $updateStockStatus
& $render
$form.Add_FormClosed({ if ($preview.Image) { $preview.Image.Dispose() } })
[void]$form.ShowDialog()
