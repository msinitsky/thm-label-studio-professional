$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { throw 'Не найден dotnet. Установите .NET 10 SDK.' }
dotnet restore .\src\LabelStudio.App\LabelStudio.App.csproj -r win-x64
if ($LASTEXITCODE -ne 0) { throw 'Restore failed' }
dotnet publish .\src\LabelStudio.App\LabelStudio.App.csproj -c Release -r win-x64 --no-restore --self-contained true -p:PublishSingleFile=true -o .\dist\LabelStudioProfessional
if ($LASTEXITCODE -ne 0) { throw 'Publish failed' }
if (!(Test-Path .\dist\LabelStudioProfessional\LabelStudio.App.exe)) { throw 'EXE not found' }
Copy-Item .\sample.csv .\dist\LabelStudioProfessional\
Copy-Item .\sample.label.json .\dist\LabelStudioProfessional\
Write-Host 'Готово: dist\LabelStudioProfessional\LabelStudio.App.exe'
