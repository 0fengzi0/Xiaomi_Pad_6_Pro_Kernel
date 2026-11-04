param([switch]$Online)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'dependencies.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$hasProblems = $false

foreach ($repository in $manifest.repositories) {
    $localPath = Join-Path $projectRoot $repository.path
    $localStatus = 'MISSING'
    if (Test-Path -LiteralPath (Join-Path $localPath '.git')) {
        $revision = & git -C $localPath rev-parse HEAD
        if ($LASTEXITCODE -ne 0) {
            $localStatus = 'GIT_ERROR'
        } elseif ($revision -eq $repository.revision) {
            $localStatus = 'PIN_MATCH'
        } else {
            $localStatus = 'PIN_MISMATCH'
        }
    }
    if ($localStatus -ne 'PIN_MATCH') {
        $hasProblems = $true
    }

    $remoteStatus = 'NOT_CHECKED'
    if ($Online) {
        $remoteRef = 'refs/heads/' + $repository.branch
        $remoteOutput = & git ls-remote --exit-code $repository.url $remoteRef
        if ($LASTEXITCODE -ne 0 -or -not $remoteOutput) {
            $remoteStatus = 'REMOTE_ERROR'
            $hasProblems = $true
        } elseif (($remoteOutput -split '\s+')[0] -eq $repository.revision) {
            $remoteStatus = 'PIN_MATCH'
        } else {
            $remoteStatus = 'UPSTREAM_CHANGED'
            $hasProblems = $true
        }
    }
    Write-Output ('{0}: local={1}, remote={2}' -f $repository.name, $localStatus, $remoteStatus)
}

if ($manifest.PSObject.Properties.Name -contains 'referenceSources') {
    foreach ($source in $manifest.referenceSources) {
        foreach ($file in $source.files) {
            $filePath = Join-Path (Join-Path $projectRoot $source.path) $file.name
            $fileStatus = 'MISSING'
            if (Test-Path -LiteralPath $filePath -PathType Leaf) {
                $digest = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash
                if ($digest -eq $file.sha256) {
                    $fileStatus = 'HASH_MATCH'
                } else {
                    $fileStatus = 'HASH_MISMATCH'
                }
            }
            if ($fileStatus -ne 'HASH_MATCH') {
                $hasProblems = $true
            }
            Write-Output ('{0}/{1}: {2} (reference only)' -f $source.name, $file.name, $fileStatus)
        }
    }
}

Write-Output 'This checks repository HEAD revisions and reference file hashes only; it does not certify all working-tree contents, build completeness or device compatibility.'
Write-Output ('Unresolved build/compatibility items: {0}. See dependencies.json and README.md.' -f $manifest.unresolved.Count)
if ($hasProblems) {
    exit 1
}
exit 0
