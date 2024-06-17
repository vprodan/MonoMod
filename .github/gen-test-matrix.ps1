param (
    [string[]] $MatrixOutName,
    [string] $GithubOutput
)

$ErrorActionPreference = "Stop";

$nugetOrgPkgSrc = "nuget.org";

$operatingSystems = @(
    [pscustomobject]@{
        name = "Windows";
        runner = "windows-latest";
        ridname = "win";
        arch = @("x86","x64"); # while .NET Framework supports Arm64, GitHub doesn't provide Arm windows runners
        runnerArch = 1;
        hasFramework = $true;
        unityMonoArch = @("win32", "win64", "win_arm64");
        unityMonoDll = "mono-2.0-bdwgc.dll";
        dllSuffix = ".dll";
    },
    [pscustomobject]@{
        name = "Linux";
        runner = "ubuntu-latest";
        ridname = "linux";
        arch = @("x64");
        runnerArch = 0;
        hasMono = $true;
        unityMonoArch = @("linux64");
        unityMonoDll = "limonobdwgc-2.0.so"; # TODO
        dllPrefix = "lib";
        dllSuffix = ".so";
    },
    [pscustomobject]@{
        name = "MacOS 13";
        runner = "macos-13";
        ridname = "osx";
        arch = @("x64");
        runnerArch = 0;
        hasMono = $true;
        unityMonoArch = @("macos_x64");
        unityMonoDll = "limonobdwgc-2.0.dylib";
        dllPrefix = "lib";
        dllSuffix = ".dylib";
    },
    [pscustomobject]@{
        #enable = $false;
        name = "MacOS 14 (M1)";
        runner = "macos-14";
        ridname = "osx";
        arch = @("x64"<#, "arm64"#>); # x64 comes from Rosetta, and we disable arm64 mode for now because we don't support it yet
        runnerArch = 1;
        hasMono = $true;
        unityMonoArch = @("macos_x64", "macos_arm64");
        unityMonoDll = "limonobdwgc-2.0.dylib";
        dllPrefix = "lib";
        dllSuffix = ".dylib";
    }
);

$dotnetVersions = @(
    [pscustomobject]@{
        name = ".NET Framework 4.x";
        id = 'fx';
        tfm = "net462";
        rids = @("win-x86","win-x64","win-arm64");
        isFramework = $true;
    },
    [pscustomobject]@{
        name = ".NET Core 2.1";
        sdk = "2.1";
        tfm = "netcoreapp2.1";
        rids = @("win-x86","win-x64","linux-x64","osx-x64");
        needsRestore = $true;
    },
    [pscustomobject]@{
        name = ".NET Core 3.0";
        sdk = "3.0";
        tfm = "netcoreapp3.0";
        rids = @("win-x86","win-x64","linux-x64","osx-x64");
    },
    [pscustomobject]@{
        name = ".NET Core 3.1";
        sdk = "3.1";
        tfm = "netcoreapp3.1";
        rids = @("win-x86","win-x64","linux-x64","osx-x64");
    },
    [pscustomobject]@{
        name = ".NET 5.0";
        sdk = "5.0";
        tfm = "net5.0";
        rids = @("win-x86","win-x64","linux-x64","osx-x64");
    },
    [pscustomobject]@{
        name = ".NET 6.0";
        sdk = "6.0";
        tfm = "net6.0";
        rids = @("win-x86","win-x64","win-arm64","linux-x64","linux-arm","linux-arm64","osx-x64","osx-arm64");
        pgo = $true;
        netMonoPkgVer = "6.0.31"
        netMonoNugetSrc = $nugetOrgPkgSrc;
    },
    [pscustomobject]@{
        name = ".NET 7.0";
        sdk = "7.0";
        tfm = "net7.0";
        rids = @("win-x86","win-x64","win-arm64","linux-x64","linux-arm","linux-arm64","osx-x64","osx-arm64");
        pgo = $true;
        netMonoPkgVer = "7.0.20"
        netMonoNugetSrc = $nugetOrgPkgSrc;
    },
    [pscustomobject]@{
        name = ".NET 8.0";
        sdk = "8.0";
        tfm = "net8.0";
        rids = @("win-x86","win-x64","win-arm64","linux-x64","linux-arm","linux-arm64","osx-x64","osx-arm64");
        pgo = $true;
        netMonoPkgVer = "8.0.6"
        netMonoNugetSrc = $nugetOrgPkgSrc;
    }
);

$netMonoPackageName = "Microsoft.NETCore.App.Runtime.Mono.{RID}";
$netMonoLibPath = "runtimes/{RID}/lib/{TFM}/";
$netMonoDllPath = "runtimes/{RID}/native/{DllPre}coreclr{DllSuf}";

function Fill-Template($template, $obj)
{
    $result = $template;
    foreach ($kvp in $obj.GetEnumerator())
    {
        $result = $result -replace "{$($kvp.Key)}",$kvp.Value;
    }
    return $result;
}

$monoTfm = "net462";

$unityMonoVersions = @(
    <#
    [pscustomobject]@{
        name = "Unity Mono 6000.0.2";
        unityVersion = "6000.0.2";
        monoName = "MonoBleedingEdge";
    }
    #>
);

$jobs = @();
function Remove-NullProperties {

  param(
    [parameter(Mandatory,ValueFromPipeline)]
    [psobject] $InputObject
  )

  process {
    # Create the initially empty output object
    $obj = [pscustomobject]::new()
    # Loop over all input-object properties.
    foreach($prop in $InputObject.psobject.properties) {
      # If a property is non-$null, add it to the output object.
      if ($null -ne $InputObject.$($prop.Name)) {
        Add-Member -InputObject $obj -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
      }
    }
    # Give the output object a type name that reflects the type of the input
    # object prefixed with 'NonNull.' - note that this is purely informational, unless
    # you define a custom output format for this type name.
    $obj.pstypenames.Insert(0, 'NonNull.' + $InputObject.GetType().FullName)
    # Output the output object.
    $obj
  }

}

foreach ($os in $operatingSystems)
{
    if ($os.enable -eq $false) { continue; }
    $outos = $os | Select-Object -Property name,runner | Remove-NullProperties
    
    if ($os.hasMono -and $os.runnerArch -lt $os.arch.Length)
    {
        # this OS has a system mono, emit a job for that
        $jobs += @(
            [pscustomobject]@{
                title = "System Mono on $($os.name)";
                os = $outos;
                dotnet = [pscustomobject]@{
                    name = "Mono";
                    id = "sysmono";
                    needsRestore = $true; # Monos always need restore
                    isMono = $true;
                    systemMono = $true;
                    tfm = $monoTfm;
                };
                arch = $os.arch[$os.runnerArch];
            }
        );
    }

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
            
            $outdotnet = $dotnet | Select-Object -Property name,sdk,tfm,pgo,needsRestore,netMonoPkgVer,netMonoNugetSrc
            
            $title = "$($dotnet.name) $arch on $($os.name)"
            if ($dotnet.pgo)
            {
                # this runtime supports pgo; generate 2 jobs; one with it enabled, one without
                $jobs += @(
                    [pscustomobject]@{
                        title = $title + " (PGO Off)";
                        os = $outos;
                        dotnet = $outdotnet | Remove-NullProperties;
                        arch = $arch;
                        usePgo = $false;
                    },
                    [pscustomobject]@{
                        title = $title + " (PGO On)";
                        os = $outos;
                        dotnet = $outdotnet | Remove-NullProperties;
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
                        dotnet = $outdotnet | Remove-NullProperties;
                        arch = $arch;
                    }
                );
            }

            if ($dotnet.netMonoNugetSrc)
            {
                # this runtime version has an associated Mono build
                $fill = @{
                    RID = $rid;
                    TFM = $dotnet.tfm;
                    DllPre = $os.dllPrefix;
                    DllSuf = $os.dllSuffix;
                };

                # fill the templates, so that we can add the job
                $pkgName = Fill-Template $netMonoPackageName $fill
                $libPath = Fill-Template $netMonoLibPath $fill
                $dllPath = Fill-Template $netMonoDllPath $fill

                # We always need to do a restore on Mono
                $jobdotnet = $outdotnet | Select-Object -ExcludeProperty sdk,pgo -Property *,`
                    @{n='isMono';e={$true}},`
                    @{n='netMonoPkgName';e={$pkgName}},`
                    @{n='monoLibPath';e={$libPath}},`
                    @{n='monoDllPath';e={$dllPath}}
                $jobdotnet.needsRestore = $true;

                $jobs += @(
                    [pscustomobject]@{
                        title = ".NET Mono $($dotnet.netMonoPkgVer) $arch on $($os.name)";
                        os = $outos;
                        dotnet = $jobdotnet | Remove-NullProperties;
                        arch = $arch;
                    }
                );
            }
        }

        # TODO: non-system mono
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