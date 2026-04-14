#Requires -Version 5.1

param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDirectory,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [ValidateSet('emit', 'dest')]
    [string]$GroupBy = 'emit',

    [switch]$Copy,
    [switch]$DryRun,
    [switch]$Recurse
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info { param([string]$Message) Write-Host "[info] $Message" -ForegroundColor DarkGray }
function Write-Warn { param([string]$Message) Write-Host "[warn] $Message" -ForegroundColor Yellow }
function Write-Ok   { param([string]$Message) Write-Host "[ok]   $Message" -ForegroundColor Green }
function Write-Bad  { param([string]$Message) Write-Host "[fail] $Message" -ForegroundColor Red }

function Get-FirstNodeValue {
    param(
        [xml]$XmlDocument,
        [string[]]$XPathCandidates,
        [System.Xml.XmlNamespaceManager]$NamespaceManager
    )

    foreach ($xpath in $XPathCandidates) {
        try {
            $node = $XmlDocument.SelectSingleNode($xpath, $NamespaceManager)
        }
        catch [System.Xml.XPath.XPathException] {
            continue
        }

        if ($node -and $node.InnerText) {
            $value = $node.InnerText.Trim()
            if ($value) {
                return $value
            }
        }
    }

    return $null
}

function Get-AccessKeyFromFileName {
    param([string]$FileName)

    if ($FileName -match '(\d{44})-nfe$') {
        return $matches[1]
    }

    if ($FileName -match '(\d{44})') {
        return $matches[1]
    }

    return $null
}

function Get-YearMonthFromDateString {
    param([string]$DateValue)

    if (-not $DateValue) { return $null }

    $normalized = $DateValue.Trim()
    if ($normalized -match '^(\d{4})-(\d{2})-(\d{2})') {
        return "$($matches[1])-$($matches[2])"
    }

    if ($normalized -match '^(\d{4})(\d{2})(\d{2})') {
        return "$($matches[1])-$($matches[2])"
    }

    if ($normalized -match '^(\d{2})\/(\d{2})\/(\d{4})') {
        return "$($matches[3])-$($matches[2])"
    }

    return $null
}

function Get-YearMonthFromAccessKey {
    param([string]$AccessKey)

    if (-not $AccessKey -or $AccessKey.Length -lt 6) { return $null }

    $yy = $AccessKey.Substring(2, 2)
    $mm = $AccessKey.Substring(4, 2)
    # NF-e access keys encode the year with two digits; assume 20xx.
    return "20$yy-$mm"
}

function Get-NfeMetadata {
    param([string]$FilePath)

    try {
        [xml]$xmlDoc = Get-Content -Path $FilePath -Raw -Encoding UTF8
    }
    catch {
        throw "Could not parse XML file: $FilePath"
    }

    $namespaceUri = $xmlDoc.DocumentElement.NamespaceURI
    $ns = New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable)
    if ($namespaceUri) {
        $ns.AddNamespace('nfe', $namespaceUri)
    }

    $emitCnpj = Get-FirstNodeValue -XmlDocument $xmlDoc -NamespaceManager $ns -XPathCandidates @(
        '//nfe:emit/nfe:CNPJ',
        '//emit/CNPJ'
    )

    $destCnpj = Get-FirstNodeValue -XmlDocument $xmlDoc -NamespaceManager $ns -XPathCandidates @(
        '//nfe:dest/nfe:CNPJ',
        '//dest/CNPJ'
    )

    $destCpf = Get-FirstNodeValue -XmlDocument $xmlDoc -NamespaceManager $ns -XPathCandidates @(
        '//nfe:dest/nfe:CPF',
        '//dest/CPF'
    )

    $issueDate = Get-FirstNodeValue -XmlDocument $xmlDoc -NamespaceManager $ns -XPathCandidates @(
        '//nfe:ide/nfe:dhEmi',
        '//nfe:ide/nfe:dEmi',
        '//ide/dhEmi',
        '//ide/dEmi'
    )

    $accessKey = Get-FirstNodeValue -XmlDocument $xmlDoc -NamespaceManager $ns -XPathCandidates @(
        '//nfe:infNFe/@Id',
        '//infNFe/@Id'
    )

    if ($accessKey) {
        $accessKey = $accessKey -replace '^NFe', ''
    }

    if (-not $accessKey) {
        $accessKey = Get-AccessKeyFromFileName -FileName ([System.IO.Path]::GetFileNameWithoutExtension($FilePath))
    }

    $yearMonth = Get-YearMonthFromDateString -DateValue $issueDate
    if (-not $yearMonth) {
        $yearMonth = Get-YearMonthFromAccessKey -AccessKey $accessKey
    }

    return [pscustomobject]@{
        EmitCnpj = $emitCnpj
        DestCnpj = $destCnpj
        DestCpf = $destCpf
        AccessKey = $accessKey
        IssueDate = $issueDate
        YearMonth = $yearMonth
    }
}

if (-not (Test-Path $SourceDirectory)) {
    throw "Source directory not found: $SourceDirectory"
}

if (-not (Test-Path $OutputDirectory) -and -not $DryRun) {
    New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
}

$getChildItemParams = @{
    Path = $SourceDirectory
    File = $true
    Filter = '*.xml'
}
if ($Recurse) {
    $getChildItemParams.Recurse = $true
}

$files = Get-ChildItem @getChildItemParams | Sort-Object Name
if (-not $files) {
    Write-Warn 'No XML files found in source directory.'
    exit 0
}

$totalFiles = $files.Count
$processed = 0
$skipped = 0

foreach ($file in $files) {
    try {
        $meta = Get-NfeMetadata -FilePath $file.FullName
    }
    catch {
        Write-Bad "$($file.Name): $($_.Exception.Message)"
        $skipped++
        continue
    }

    $cnpj = if ($GroupBy -eq 'emit') { $meta.EmitCnpj } else { $meta.DestCnpj }
    if (-not $cnpj -and $GroupBy -eq 'dest') {
        $cnpj = $meta.DestCpf
    }

    if (-not $cnpj) {
        Write-Warn "$($file.Name): missing $GroupBy CNPJ/CPF. Skipping."
        $skipped++
        continue
    }

    if (-not $meta.YearMonth) {
        Write-Warn "$($file.Name): could not determine issue month. Skipping."
        $skipped++
        continue
    }

    $targetDir = Join-Path (Join-Path $OutputDirectory $cnpj) $meta.YearMonth
    $targetPath = Join-Path $targetDir $file.Name

    if ($DryRun) {
        Write-Info "$($file.Name) -> $targetDir"
        $processed++
        continue
    }

    try {
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }

        if (Test-Path $targetPath) {
            Write-Warn "$($file.Name): target already exists, overwriting -> $targetPath"
        }

        if ($Copy) {
            Copy-Item -Path $file.FullName -Destination $targetPath -Force
            Write-Ok "$($file.Name): copied to $targetDir"
        }
        else {
            Move-Item -Path $file.FullName -Destination $targetPath -Force
            Write-Ok "$($file.Name): moved to $targetDir"
        }

        $processed++
    }
    catch {
        Write-Bad "$($file.Name): $($_.Exception.Message)"
        $skipped++
    }
}

$modeLabel = if ($DryRun) { 'dry-run' } elseif ($Copy) { 'copy' } else { 'move' }

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "Total     : $totalFiles" -ForegroundColor DarkGray
Write-Host "Processed : $processed" -ForegroundColor Green
Write-Host "Skipped   : $skipped" -ForegroundColor $(if ($skipped -gt 0) { 'Yellow' } else { 'Green' })
Write-Host "Mode      : $modeLabel" -ForegroundColor DarkGray
Write-Host "Grouped by: $GroupBy" -ForegroundColor DarkGray
Write-Host "============================================================" -ForegroundColor Cyan
