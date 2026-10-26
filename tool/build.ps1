# 编译 Windows 版。用法(项目根目录):pwsh tool/build.ps1 [-Mode release|debug]
#
# 路径里有中文(D:\桌面)时 Flutter 的 Windows 编译会失败,所以临时把上一级文件夹
# 映射成一个纯英文盘符再编译(同 Penna 的 build_release.ps1)。项目搬到纯英文路径后可删掉映射。
param([ValidateSet('release', 'debug')][string]$Mode = 'release')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$drive = 'N:'
if (Get-Process nlaptxd -ErrorAction SilentlyContinue) { throw 'NLaptXD 正在运行,程序文件被占用。先关掉它再编译。' }
if (Test-Path "$drive\") { throw "$drive 盘符已被占用,改脚本里的 `$drive" }

subst $drive (Split-Path $root -Parent)
try {
  Push-Location "$drive\$(Split-Path $root -Leaf)"
  flutter build windows "--$Mode"
  if ($LASTEXITCODE -ne 0) { throw "flutter build 失败(退出码 $LASTEXITCODE)" }
} finally {
  Pop-Location
  subst $drive /D
  # 在映射盘下编译后这里记着 N:\ 的路径,不删的话 flutter test 会报 PathNotFoundException。
  Remove-Item (Join-Path $root '.dart_tool\hooks_runner') -Recurse -Force -ErrorAction SilentlyContinue
}
$dir = if ($Mode -eq 'release') { 'Release' } else { 'Debug' }
"产物:$root\build\windows\x64\runner\$dir\nlaptxd.exe"

# Release 版复制到 dist\(flutter clean 不会清它),桌面快捷方式「NLaptXD」指向这里。
if ($Mode -eq 'release') {
  $dist = Join-Path $root 'dist'
  robocopy "$root\build\windows\x64\runner\Release" $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "复制到 $dist 失败(robocopy $LASTEXITCODE)" }
  $exe = Join-Path $dist 'nlaptxd.exe'
  $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'NLaptXD.lnk'
  $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
  $shortcut.TargetPath = $exe
  $shortcut.WorkingDirectory = $dist
  $shortcut.Description = 'NLaptXD 标注台'
  $shortcut.Save()
  "快捷方式:$lnk -> $exe"
}
exit 0 # robocopy 成功时也可能留下 1,别让调用方当成失败
