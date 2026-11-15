param(
    [long]$RunId = 0,
    [ValidateRange(1, 60)][int]$TimeoutMinutes = 10
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$repo = 'mikedasoxfan-eng/cinejoy-ios'
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
Push-Location $repoRoot
try {
    if (!$RunId) {
        $runs = gh run list --repo $repo --workflow build-ios.yml --branch main --event push --limit 1 --json databaseId,headSha | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0 -or !$runs) { throw 'No push build found. Sign in with gh auth login first.' }
        $RunId = $runs[0].databaseId
    }
    Write-Host "Waiting for the IPA from build $RunId (no Simulator wait)..."
    while ((Get-Date) -lt $deadline) {
        $data = gh api "repos/$repo/actions/runs/$RunId/artifacts" | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) { throw 'Could not read build artifacts.' }
        $artifact = $data.artifacts | Where-Object { $_.name -eq 'Cinejoy-IPA' -and !$_.expired } | Select-Object -First 1
        if ($artifact) {
            $downloadDir = Join-Path $repoRoot "dist/downloads/$RunId"
            New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null
            gh run download $RunId --repo $repo --name Cinejoy-IPA --dir $downloadDir
            if ($LASTEXITCODE -ne 0) { throw 'IPA download failed.' }
            $ipa = Join-Path $downloadDir 'Cinejoy-unsigned.ipa'
            if (!(Test-Path -LiteralPath $ipa)) { throw 'The artifact did not contain an IPA.' }
            $destination = Join-Path $repoRoot 'dist/Cinejoy-latest.ipa'
            Copy-Item -LiteralPath $ipa -Destination $destination -Force
            python tools/verify_ipa.py $destination
            if ($LASTEXITCODE -ne 0) { throw 'IPA verification failed.' }
            Write-Host "Ready for Sideloadly: $destination"
            Get-FileHash -LiteralPath $destination -Algorithm SHA256
            return
        }
        $run = gh run view $RunId --repo $repo --json status,conclusion | ConvertFrom-Json
        if ($run.status -eq 'completed') { throw "Build ended ($($run.conclusion)) without an IPA." }
        Start-Sleep -Seconds 5
    }
    throw "Timed out waiting for build $RunId."
} finally {
    Pop-Location
}
