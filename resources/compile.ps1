# create a single resource file pasc.lrs
# should run every time resource files change
$StartDir = Get-Location
$CurrentDir = Join-Path -Path $StartDir -ChildPath "resources"
Write-Host $StartDir
Write-Host $CurrentDir
Set-Location $CurrentDir
lazres `
  ..\src\utils\pasc.lrs `
  .\gitignore.txt `
  .\launchjson.txt `
  .\tasksjson.txt `
  .\projectlpi.txt `
  .\projectlpr.txt `
  .\update-path-ps1.txt `
  .\update-path-sh.txt `
  .\tests\fpcunitprojectlpi.txt `
  .\tests\fpcunitprojectlpr.txt `
  .\tests\testcase1pas.txt
Set-Location $StartDir