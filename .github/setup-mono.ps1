param (
    [string] $MatrixJson,
    [string] $GithubOutput,
    [string] $GithubEnv
)

$ErrorActionPreference = "Stop";

$jobInfo = ConvertFrom-Json $MatrixJson;

if (-not $jobInfo.dotnet.isMono)
{
    Write-Host "Nothing needs to be done, job is not a Mono job";
    return 0;
}

$pkgSrc = $jobInfo.dotnet.netMonoNugetSrc;
$pkgName = $jobInfo.dotnet.netMonoPkgName;
$pkgVer = $jobInfo.dotnet.netMonoPkgVer;
$libPath = $jobInfo.dotnet.monoLibPath;
$dllPath = $jobInfo.dotnet.monoDllPath;

if (-not $pkgSrc -or -not $pkgName -or -not $pkgVer -or -not $libPath -or -not $dllPath)
{
    # TODO: unity builds
    Write-Host "Job info is missing some required properties";
    return 1;
}

$repoRoot = Join-Path $PSScriptRoot ".." | Resolve-Path;

$monoDir = Join-Path $repoRoot ".mono";
if (-not Test-Path -Type Container $monoDir)
{
    mkdir $monoDir;
}

$pkgsPath = Join-Path $monoDir "pkg";
$mdhPath = Join-Path $monoDir "mdh";
$mdhZip = Join-Path $monoDir "mdh.tgz";
$mdh = Join-Path $mdhPath "mdh";

# first, lets grab mdh
$mdhArchName = $jobInfo.arch.ToUpperInvariant();
$mdhOsName = $jobInfo.os.name;
if ($mdhOsName -eq "MacOS") { $mdhOsName = "macOS"; } # fixup because Actions gives MDH this out of the gate
$mdhUrl = "https://github.com/nike4613/mono-dynamic-host/releases/download/latest/release-$mdhOsName-$mdhArchName.tgz";
Invoke-WebRequest -Uri $mdhUrl -OutFile $mdhZip

# extract mdh
Expand-Archive -Force -Path $mdhZip $mdhPath
if (Test-Path -Type Leaf "$mdh.exe")
{
    $mdh = "$mdh.exe";
}

# Need to customize NUGET_PACKAGES because we need to do a restore to pull the Mono package
$oldNUGET_PACKAGES = $env:NUGET_PACKAGES;
try {
    $env:NUGET_PACKAGES = $pkgsPath;

    # Dump the dummy project files
    $dummyProjPath = Join-Path $monoDir "dummy.proj";
    Set-Content -Path (Join-Path monoDir "Directory.Build.props") "<Project />";
    Set-Content -Path (Join-Path monoDir "Directory.Build.targets") "<Project />";
    Set-Content -Path $dummyProjPath @"
<Project Sdk="Microsoft.Build.NoTargets">

  <PropertyGroup>
    <EnableDefaultItems>false</EnableDefaultItems>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="$pkgName" Version="$pkgVersion" />
  </ItemGroup>

</Project>
"@;

    # Generate a NuGet config that assigns the correct package source
    $nugetConfigFile = Join-Path monoDir "nuget.config";
    Set-Content -Path $nugetConfigFile @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>

  <packageSourceMapping>
    <packageSource key="$pkgSrc">
      <package pattern="$pkgName" />
    </packageSource>
  </packageSourceMapping>
  
</configuration>
"@;

    # Now do a restore from there
    dotnet restore $dummyProjPath --packages $pkgsPath --configfile $nugetConfigFile

    # Now that we've done the restore, we can export the relevant information
    $pkgBasePath = Join-Path $pkgsPath $pkgName $pkgVer | Resolve-Path;
    $fullLibPath = Join-Path $pkgBasePath $libPath | Resolve-Path;
    $fullDllPath = Join-Path $pkgBasePath $dllPath | Resolve-Path;

    echo "mdh=$mdh" >> $GithubOutput;
    echo "mono_dll=$fullDllPath" >> $GithubOutput;
    echo "MONO_PATH=$fullLibPath" >> $GithubEnv;
}
finally
{
    $env:NUGET_PACKAGES = $oldNUGET_PACKAGES;
}