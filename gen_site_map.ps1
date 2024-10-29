$workingFolder = $env:GITHUB_WORKSPACE

$configPath = "$workingFolder\config.json"
$config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
Write-Host "Config loaded from $configPath"

$repoDir = "$workingFolder\github_repos"
$sitemapDir = "$workingFolder\sitemaps"
New-Item -ItemType Directory -Path $repoDir -Force | Out-Null

foreach ($repo in $config.repos) {
    $repoName = $repo.name
    $repoUrl = $repo.url
    $sitemapName = $repo.sitemap

    $repoDir = "$repoDir\$repoName"
    git clone $repoUrl $repoDir
    Set-Location $repoDir

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
    
    $sitemapEntriesJoined = $sitemapEntries -join "`n"
    $sitemapContent = @"
<?xml version="1.0" encoding="utf-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
$sitemapEntriesJoined
</urlset>
"@
    $sitemapFilePath = "$sitemapDir\$sitemapName"
    $sitemapContent | Out-File -Encoding UTF8 $sitemapFilePath

    Write-Host "Sitemap generated for $repoName at $sitemapFilePath"
    Set-Location $workingFolder
}
