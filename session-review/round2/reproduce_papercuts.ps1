# Isolated diagnostics: no desktop actions and no code from the supplied logs is executed.
param([string] $CliModulePath)
$ErrorActionPreference = 'Stop'
if (-not $CliModulePath) {
    $CliModulePath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\potato_cli\PoTAToCli\PoTAToCli.psm1'))
}
$module = Import-Module $CliModulePath -Force -PassThru
Add-Type -AssemblyName WindowsBase
$rectangleFailure = & $module {
    try { ConvertTo-PotatoRectangle -Rectangle ([Windows.Rect]::Empty) | Out-Null; return $false }
    catch { return $true }
}

function Invoke-FixturePredicate { param([scriptblock] $Condition) & $Condition }
function Test-FixtureParameterScope {
    param([string] $ControlType)
    $outer = $PSBoundParameters.ContainsKey('ControlType')
    $inner = Invoke-FixturePredicate -Condition { $PSBoundParameters.ContainsKey('ControlType') }
    [pscustomobject]@{ outerParameterPresent = $outer; innerParameterPresent = $inner }
}
$scope = Test-FixtureParameterScope -ControlType 'Button'

$path = Join-Path ([IO.Path]::GetTempPath()) ('agta-share-probe-' + [guid]::NewGuid() + '.tmp')
$owner = $null
$reader = $null
$exclusiveReaderFailed = $false
$sharedReaderSucceeded = $false
try {
    $owner = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::ReadWrite)
    $owner.WriteByte(80)
    $owner.Flush()
    try { $reader = [IO.File]::OpenRead($path) }
    catch { $exclusiveReaderFailed = $true }
    finally { if ($reader) { $reader.Dispose(); $reader = $null } }
    $reader = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $sharedReaderSucceeded = $reader.ReadByte() -eq 80
}
finally {
    if ($reader) { $reader.Dispose() }
    if ($owner) { $owner.Dispose() }
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
}
[ordered]@{
    powershellVersion = $PSVersionTable.PSVersion.ToString()
    emptyRectangleConversionThrows = $rectangleFailure
    parameterScope = $scope
    openReadFailsWithExistingWriter = $exclusiveReaderFailed
    readWriteSharedReadSucceeds = $sharedReaderSucceeded
} | ConvertTo-Json -Depth 5
