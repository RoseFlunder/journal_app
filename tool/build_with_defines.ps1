param(
  [Parameter(Position = 0)]
  [ValidateSet('appbundle', 'windows', 'web')]
  [string] $Target = 'web',

  [Parameter(Position = 1)]
  [string] $DefinesFile = (Join-Path $env:USERPROFILE '.config\cozy_bloom\build-defines.json')
)

$resolvedDefinesFile = [System.IO.Path]::GetFullPath($DefinesFile)
if (-not (Test-Path -LiteralPath $resolvedDefinesFile -PathType Leaf)) {
  throw "Defines file was not found: $resolvedDefinesFile"
}

& flutter build $Target --release "--dart-define-from-file=$resolvedDefinesFile"
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
