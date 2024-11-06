$workingFolder = $env:GITHUB_WORKSPACE

$configPath = "$workingFolder\config.json"
$config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
Write-Host "Config loaded from $configPath"

$repoDir = "$workingFolder\github_repos"
$sitemapDir = "$workingFolder\sitemaps"
$robotsPath = "$sitemapDir\robots.txt"
$sitemapIndexPath = "$sitemapDir\$($config.sitemap_index)"
$currentDateFormatted = Get-Date -Format "yyyy-MM-dd"

if (-not (Test-Path -Path $repoDir)) {
    New-Item -ItemType Directory -Path $repoDir | Out-Null
}
if (-not (Test-Path -Path $sitemapDir)) {
    New-Item -ItemType Directory -Path $sitemapDir | Out-Null
}
function GenerateFile {
    param(
        [string]$path,
        [string]$content
    )

    $content | Out-File -Encoding UTF8 -FilePath $path -Force
}

$sitemapEntries = @()
foreach ($repo in $config.repos) {
    $repoName = $repo.name
    $repoUrl = $repo.url
    $sitemapName = $repo.sitemap

    if ($repo.enabled -eq $false) {
        Write-Host "Skipping $repoName as it is disabled"
        continue
    }

    $currentRepoDir = "$repoDir\$repoName"
    git clone -c core.longpaths=true $repoUrl $currentRepoDir
    Set-Location $currentRepoDir

    $includes = ($repo.filters | Where-Object { $_ -notmatch "^!" } | ForEach-Object { $_ }) -join "|"
    $excludes = ($repo.filters | Where-Object { $_ -match "^!" } | ForEach-Object { $_ -replace "^!", "" }) -join "|"
    $allFiles = git ls-files .
    $includedFiles = $allFiles | Where-Object { $_ -match $includes }
    $filteredFiles = $includedFiles | Where-Object { $_ -notmatch $excludes }

    $urlEntries = @()
    Write-Host "Generating sitemap for $repoName"
    
    foreach ($fileName in $filteredFiles) {
        Write-Host "Processing $fileName"

        $lastChangeDate = git log -1 --format="%cd" --date=short -- $fileName
        $rawRepoUrl = $repoUrl -replace 'https://github.com', 'https://raw.githubusercontent.com'
        $rawFileUrl = "$rawRepoUrl/refs/heads/main/$fileName" -replace '\\', '/'
        $urlEntries += @"
<url>
    <loc>$rawFileUrl</loc>
    <lastmod>$lastChangeDate</lastmod>
</url>
"@
    }
    
    Write-Host "Sitemap generated for $repoName at $sitemapFilePath"
    GenerateFile -path "$sitemapDir\$sitemapName" -content @"
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">
$($urlEntries -join "`n")
</urlset>
"@
    
    $sitemapUrl = "https://raw.githubusercontent.com/partychen/azure-sdk-sitemap/refs/heads/main/$sitemapFilePath"
    $sitemapEntries += @"
<sitemap>
    <loc>$sitemapUrl</loc>
    <lastmod>$currentDateFormatted</lastmod>
</sitemap>
"@
}


Write-Host "Generating sitemap index for $sitemapIndexPath"
GenerateFile -path $sitemapIndexPath -content @"
<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
$($sitemapEntries -join "`n")
</sitemapindex>
"@

Write-Host "Generating robot.txt for $robotsPath"
$robotsEntries = @("User-agent: *", "", "Sitemap: https://raw.githubusercontent.com/partychen/azure-sdk-sitemap/refs/heads/main/sitemaps/$sitemapIndexPath")
GenerateFile -path $robotsPath -content $($robotsEntries -join "`n")

Set-Location $workingFolder