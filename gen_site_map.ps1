$workingFolder = $env:GITHUB_WORKSPACE

$configPath = "$workingFolder\config.json"
$config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
Write-Host "Config loaded from $configPath"

$repoDir = "$workingFolder\github_repos"
$sitemapDir = "$workingFolder\sitemaps"
$robotsPath = "$sitemapDir\robots.txt"
New-Item -ItemType Directory -Path $repoDir -Force | Out-Null

function GenerateFile {
    param(
        [string]$path,
        [string]$content
    )

    $content | Out-File -Encoding UTF8 $path
}

$sitemapIndexEntries = @()
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

    $sitemapEntries = @()
    Write-Host "Generating sitemap for $repoName"
    
    foreach ($fileName in $filteredFiles) {
        Write-Host "Processing $fileName"

        $lastChangeDate = git log -1 --format="%cd" --date=short -- $fileName
        $rawRepoUrl = $repoUrl -replace 'https://github.com', 'https://raw.githubusercontent.com'
        $rawFileUrl = "$rawRepoUrl/refs/heads/main/$fileName" -replace '\\', '/'

        $sitemapEntry = @"
<url>
    <loc>$rawFileUrl</loc>
    <lastmod>$lastChangeDate</lastmod>
</url>
"@

        $sitemapEntries += $sitemapEntry
    }
    
    GenerateFile -path "$sitemapDir\$sitemapName" -content @"
<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
$($sitemapEntries -join "`n")
</sitemapindex>
"@
    Write-Host "Sitemap generated for $repoName at $sitemapFilePath"

    $sitemapUrl = "https://raw.githubusercontent.com/partychen/azure-sdk-sitemap/refs/heads/main/$sitemapFilePath"
    $currentDateFormatted = Get-Date -Format "yyyy-MM-dd"
    sitemapIndexEntries += @"
<sitemap>
    <loc>$sitemapUrl</loc>
    <lastmod>$currentDateFormatted</lastmod>
</sitemap>
"@
}

$sitemapIndexPath = "$sitemapDir\$($config.sitemap_index)"
GenerateFile -path sitemapIndexPath -content @"
<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
$($sitemapIndexEntries -join "`n")
</sitemapindex>
"@

$robotsEntries = @("User-agent: *", "", "Sitemap: https://raw.githubusercontent.com/partychen/azure-sdk-sitemap/refs/heads/main/sitemaps/$sitemapIndexPath")
GenerateFile -path $robotsPath -content $($robotsEntries -join "`n")

Set-Location $workingFolder