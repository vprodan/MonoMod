param (
    [string[]] $MatrixOutName,
    [string] $GithubOutput
)

$ErrorActionPreference = "Stop";

$operatingSystems = @(
    [pscustomobject]@{
        name = "Windows";
        runner = "windows-latest";
        ridname = "win";
        arch = @("x86","x64"); # while .NET Framework supports Arm64, GitHub doesn't provide Arm windows runners
        hasFramework = $true;
    },
    [pscustomobject]@{
        name = "Linux";
        runner = "ubuntu-latest";
        ridname = "linux";
        arch = @("x64");
        hasMono = $true;
    },
    [pscustomobject]@{
        name = "MacOS 13";
        runner = "macos-13";
        ridname = "osx";
        arch = @("x64");
        hasMono = $true;
    },
    [pscustomobject]@{
        enable = $false;
        name = "MacOS 14 (M1)";
        runner = "macos-14";
        ridname = "osx";
        arch = @("x64", "arm64"); # x64 comes from Rosetta
        hasMono = $true;
    }
);

$dotnetVersions = @(
    [pscustomobject]@{
        name = ".NET Framework 4.x";
        id = 'fx';
        tfm = "net46";
        rids = @("win-x86","win-x64","win-arm64");
        isFramework = $true;
    },
    [pscustomobject]@{
        name = ".NET Core 2.1";
        sdk = "2.1.x";
        tfm = "netcoreapp2.1";
        rids = @("win-x86","win-x64","linux-x64","osx-x64");
        needsRestore = $true;
    },
    [pscustomobject]@{
        name = ".NET Core 3.0";
        sdk = "3.0.x";
        tfm = "netcoreapp3.0";
        rids = @("win-x86","win-x64","linux-x64","osx-x64");
    },
    [pscustomobject]@{
        name = ".NET Core 3.1";
        sdk = "3.1.x";
        tfm = "netcoreapp3.1";
        rids = @("win-x86","win-x64","linux-x64","osx-x64");
    },
    [pscustomobject]@{
        name = ".NET 5.0";
        sdk = "5.0.x";
        tfm = "net5.0";
        rids = @("win-x86","win-x64","linux-x64","osx-x64");
    },
    [pscustomobject]@{
        name = ".NET 6.0";
        sdk = "6.0.x";
        tfm = "net6.0";
        rids = @("win-x86","win-x64","win-arm64","linux-x64","linux-arm","linux-arm64","osx-x64","osx-arm64");
        pgo = $true;
    },
    [pscustomobject]@{
        name = ".NET 7.0";
        sdk = "7.0.x";
        tfm = "net7.0";
        rids = @("win-x86","win-x64","win-arm64","linux-x64","linux-arm","linux-arm64","osx-x64","osx-arm64");
        pgo = $true;
    },
    [pscustomobject]@{
        name = ".NET 8.0";
        sdk = "8.0.x";
        tfm = "net8.0";
        rids = @("win-x86","win-x64","win-arm64","linux-x64","linux-arm","linux-arm64","osx-x64","osx-arm64");
        pgo = $true;
    }
);

$jobs = @();

foreach ($os in $operatingSystems)
{
    if ($os.enable -eq $false) { continue; }
    $outos = $os | Select-Object -ExcludeProperty arch,ridname,hasFramework,hasMono

    foreach ($arch in $os.arch)
    {
        $rid = $os.ridname + "-" + $arch;

        foreach ($dotnet in $dotnetVersions)
        {
            if ($dotnet.enable -eq $false) { continue; }

            if ($dotnet.isFramework -and -not $os.hasFramework)
            {
                # we're looking at .NET Framework, but this OS doesn't support it
                continue;
            }

            if (-not $dotnet.rids -contains $rid)
            {
                # the current OS/arch/runtime triple is not supported by .NET, skip
                continue;
            }
            
            $outdotnet = $dotnet | Select-Object -ExcludeProperty rids
            
            $title = "$($dotnet.name) $arch on $($os.name)"
            if ($dotnet.pgo)
            {
                # this runtime supports pgo; generate 2 jobs; one with it enabled, one without
                $jobs += @(
                    [pscustomobject]@{
                        title = $title + " (PGO Off)";
                        os = $outos;
                        dotnet = $outdotnet;
                        arch = $arch;
                        usePgo = $false;
                    },
                    [pscustomobject]@{
                        title = $title + " (PGO On)";
                        os = $outos;
                        dotnet = $outdotnet;
                        arch = $arch;
                        usePgo = $true;
                    }
                );
            }
            else
            {
                # this is a normal job; only add one
                $jobs += @(
                    [pscustomobject]@{
                        title = $title;
                        os = $outos;
                        dotnet = $outdotnet;
                        arch = $arch;
                    }
                );
            }
        }
    }
}

# TODO: support multiple batches
if ($jobs.Length -gt 256)
{
    Write-Error "Generated more than 256 jobs; actions will fail!";
}

$matrixObj = [pscustomobject]@{include = $jobs;};
$matrixStr = ConvertTo-Json -Compress -Depth 5 $matrixObj;
echo "$($MatrixOutName[0])=$matrixStr" >> $GithubOutput;