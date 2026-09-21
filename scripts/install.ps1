# code-style installer. Remote: irm <raw-url> | iex
# Env: CODE_STYLE_TARGET, CODE_STYLE_AGENTS, CODE_STYLE_LANGUAGES, CODE_STYLE_UNINSTALL
$ErrorActionPreference = 'Stop'

function Get-CodeStyleRepoRoot {
    if (-not $PSScriptRoot) {
        return $null
    }
    $candidate = Split-Path -Parent $PSScriptRoot
    if (Test-Path -LiteralPath (Join-Path $candidate 'manifest.json')) {
        return $candidate
    }
    return $null
}

function Get-CodeStyleCommit {
    param(
        [string]$SourceRoot,
        [string]$Repo,
        [string]$Ref
    )

    $gitDir = Join-Path $SourceRoot '.git'
    if (Test-Path -LiteralPath $gitDir) {
        try {
            $sha = & git -C $SourceRoot rev-parse HEAD 2>$null
            if ($LASTEXITCODE -eq 0 -and $sha) {
                return $sha.Trim()
            }
        } catch {
        }
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $uri = "https://api.github.com/repos/$Repo/commits/$Ref"
        $response = Invoke-RestMethod -Uri $uri -Headers @{ 'User-Agent' = 'code-style-installer' }
        if ($response.sha) {
            return [string]$response.sha
        }
    } catch {
    }

    return 'unknown'
}

function ConvertTo-CodeStyleList {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }

    return @(
        $Value -split ',' |
            ForEach-Object { $_.Trim().ToLowerInvariant() } |
            Where-Object { $_ }
    )
}

function Get-CodeStyleManifest {
    param([string]$SourceRoot)

    $manifestPath = Join-Path $SourceRoot 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "未找到 manifest.json: $manifestPath"
    }

    return Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-CodeStyleSelectedSkills {
    param(
        [psobject]$Manifest,
        [string]$SourceRoot,
        [string[]]$LanguageFilter
    )

    $skills = @()
    $commonPath = Join-Path $SourceRoot $Manifest.common.path
    if (-not (Test-Path -LiteralPath $commonPath)) {
        throw "公共 skill 不存在: $commonPath"
    }

    $skills += [pscustomobject]@{
        Id       = [string]$Manifest.common.id
        Path     = $commonPath
        Language = $null
    }

    $available = @{}
    if ($Manifest.languages) {
        foreach ($property in $Manifest.languages.PSObject.Properties) {
            $available[$property.Name.ToLowerInvariant()] = $property.Value
        }
    }

    $requested = @($available.Keys)
    if ($LanguageFilter.Count -gt 0) {
        $requested = $LanguageFilter
    }

    foreach ($lang in $requested) {
        if (-not $available.ContainsKey($lang)) {
            $known = @($available.Keys)
            if ($known.Count -eq 0) {
                throw "manifest.json 中没有语言包，无法安装: $lang"
            }
            throw "未知语言包 '$lang'。已登记: $($known -join ', ')"
        }

        $entry = $available[$lang]
        $skillPath = Join-Path $SourceRoot $entry.path
        if (-not (Test-Path -LiteralPath $skillPath)) {
            throw "语言 skill 不存在: $skillPath"
        }

        $skills += [pscustomobject]@{
            Id       = [string]$entry.id
            Path     = $skillPath
            Language = $lang
        }
    }

    return $skills
}

function Get-CodeStyleDestinations {
    param(
        [string]$Target,
        [string[]]$Agents
    )

    $destinations = @()
    if ($Agents -contains 'cursor' -or $Agents -contains 'codex') {
        $destinations += Join-Path $Target '.agents\skills'
    }
    if ($Agents -contains 'claude') {
        $destinations += Join-Path $Target '.claude\skills'
    }
    if ($destinations.Count -eq 0) {
        throw '没有可写入的 Agent 目录。CODE_STYLE_AGENTS 只能包含 cursor、claude、codex。'
    }

    return $destinations
}

function Copy-CodeStyleSkill {
    param(
        [string]$Source,
        [string]$DestinationRoot,
        [string]$Id
    )

    $destination = Join-Path $DestinationRoot $Id
    if (Test-Path -LiteralPath $destination) {
        Remove-Item -LiteralPath $destination -Recurse -Force
    }
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Copy-Item -Path (Join-Path $Source '*') -Destination $destination -Recurse -Force
}

function Uninstall-CodeStyle {
    param(
        [string]$Target,
        [string[]]$DefaultAgents
    )

    $statePath = Join-Path $Target '.code-style.json'
    $skillIds = @('code-style-common')
    $agents = $DefaultAgents

    if (Test-Path -LiteralPath $statePath) {
        $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($state.skills) {
            $skillIds = @($state.skills)
        }
        if ($state.agents) {
            $agents = @($state.agents | ForEach-Object { [string]$_ })
        }
    } else {
        Write-Host '未找到 .code-style.json，将只删除 code-style-common。'
    }

    foreach ($root in (Get-CodeStyleDestinations -Target $Target -Agents $agents)) {
        foreach ($id in $skillIds) {
            $skillDir = Join-Path $root $id
            if (Test-Path -LiteralPath $skillDir) {
                Remove-Item -LiteralPath $skillDir -Recurse -Force
                Write-Host "已删除 $skillDir"
            }
        }
    }

    if (Test-Path -LiteralPath $statePath) {
        Remove-Item -LiteralPath $statePath -Force
        Write-Host "已删除 $statePath"
    }

    Write-Host '卸载完成。'
}

function Install-CodeStyle {
    $target = $env:CODE_STYLE_TARGET
    if ([string]::IsNullOrWhiteSpace($target)) {
        $target = (Get-Location).Path
    }
    $target = [System.IO.Path]::GetFullPath($target)

    $allowedAgents = @('cursor', 'claude', 'codex')
    $agents = ConvertTo-CodeStyleList $env:CODE_STYLE_AGENTS
    if ($agents.Count -eq 0) {
        $agents = $allowedAgents
    }
    foreach ($agent in $agents) {
        if ($allowedAgents -notcontains $agent) {
            throw "不支持的 Agent: $agent。可选: $($allowedAgents -join ', ')"
        }
    }

    if ($env:CODE_STYLE_UNINSTALL -eq '1') {
        Uninstall-CodeStyle -Target $target -DefaultAgents $agents
        return
    }

    $tempItems = @()
    $sourceRoot = Get-CodeStyleRepoRoot
    $mode = 'local'

    try {
        if (-not $sourceRoot) {
            $mode = 'remote'
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $repo = 'ilinchunjie/code-style'
            $ref = 'main'
            $zipUri = "https://github.com/$repo/archive/refs/heads/$ref.zip"
            $zipPath = Join-Path $env:TEMP ("code-style-" + [guid]::NewGuid().ToString() + '.zip')
            $extractPath = Join-Path $env:TEMP ("code-style-" + [guid]::NewGuid().ToString())
            $tempItems += $zipPath
            $tempItems += $extractPath

            Write-Host "正在下载 $zipUri"
            $headers = @{ 'User-Agent' = 'code-style-installer' }
            $token = $env:GH_TOKEN
            if ([string]::IsNullOrWhiteSpace($token)) {
                $token = $env:GITHUB_TOKEN
            }
            if (-not [string]::IsNullOrWhiteSpace($token)) {
                $headers['Authorization'] = "Bearer $token"
            }
            try {
                Invoke-WebRequest -Uri $zipUri -OutFile $zipPath -UseBasicParsing -Headers $headers
            } catch {
                throw "下载失败。若仓库为私有，请设置 GH_TOKEN；公开仓库请确认 main 分支存在。`n$($_.Exception.Message)"
            }
            New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
            Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

            $manifestFile = Get-ChildItem -LiteralPath $extractPath -Filter 'manifest.json' -Recurse | Select-Object -First 1
            if (-not $manifestFile) {
                throw '下载的仓库中没有 manifest.json'
            }
            $sourceRoot = $manifestFile.DirectoryName
        }

        $manifest = Get-CodeStyleManifest -SourceRoot $sourceRoot
        $languageFilter = ConvertTo-CodeStyleList $env:CODE_STYLE_LANGUAGES
        $skills = Get-CodeStyleSelectedSkills -Manifest $manifest -SourceRoot $sourceRoot -LanguageFilter $languageFilter
        $destinations = Get-CodeStyleDestinations -Target $target -Agents $agents
        $commit = Get-CodeStyleCommit -SourceRoot $sourceRoot -Repo $manifest.repo -Ref $manifest.ref

        foreach ($destination in $destinations) {
            New-Item -ItemType Directory -Path $destination -Force | Out-Null
            foreach ($skill in $skills) {
                Copy-CodeStyleSkill -Source $skill.Path -DestinationRoot $destination -Id $skill.Id
                Write-Host "已安装 $($skill.Id) -> $destination"
            }
        }

        $state = [ordered]@{
            repo        = [string]$manifest.repo
            ref         = [string]$manifest.ref
            commit      = $commit
            installedAt = [DateTime]::UtcNow.ToString('o')
            mode        = $mode
            agents      = @($agents)
            skills      = @($skills | ForEach-Object { $_.Id })
            languages   = @($skills | Where-Object { $_.Language } | ForEach-Object { $_.Language })
        }
        $statePath = Join-Path $target '.code-style.json'
        $json = ($state | ConvertTo-Json -Depth 5)
        [System.IO.File]::WriteAllText($statePath, $json + [Environment]::NewLine)

        Write-Host "安装完成（$mode）。状态写入 $statePath"
    } finally {
        foreach ($item in $tempItems) {
            if (Test-Path -LiteralPath $item) {
                Remove-Item -LiteralPath $item -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Install-CodeStyle
