param (
    [string] $MatrixJson,
    [string] $GithubOutput,
    [string] $GithubEnv,
    [string] $RunnerOS
)

$ErrorActionPreference = "Stop";

$jobInfo = ConvertFrom-Json $MatrixJson;

if (-not $jobInfo.dotnet.isMono)
{
    Write-Host "Nothing needs to be done, job is not a Mono job";
    return 0;
}

if ($jobInfo.dotnet.systemMono)
{
    $mono = (Get-Command mono).Source;
    Write-Host "Job is for system mono; using mono=$mono";
    echo "use_mdh=false" | Out-File $GithubOutput -Append;
    echo "mono_dll=$mono" | Out-File $GithubOutput -Append;
    return 0;
}

$pkgSrc = $jobInfo.dotnet.netMonoNugetSrc;
$pkgName = $jobInfo.dotnet.netMonoPkgName;
$pkgVer = $jobInfo.dotnet.netMonoPkgVer;
$libPath = $jobInfo.dotnet.monoLibPath;
$dllPath = $jobInfo.dotnet.monoDllPath;
$tfm = $jobInfo.dotnet.tfm;

if (-not $pkgSrc -or -not $pkgName -or -not $pkgVer -or -not $libPath -or -not $dllPath)
{
    # TODO: unity builds
    Write-Host "Job info is missing some required properties";
    return 1;
}

$repoRoot = Join-Path $PSScriptRoot ".." | Resolve-Path;

$monoDir = Join-Path $repoRoot ".mono";
if (-not (Test-Path -Type Container $monoDir))
{
    mkdir $monoDir;
}

$pkgsPath = Join-Path $monoDir "pkg";
$mdhPath = Join-Path $monoDir "mdh";
$mdhZip = Join-Path $monoDir "mdh.zip";
$mdh = Join-Path $mdhPath "mdh";

# first, lets grab mdh
$mdhArchName = $jobInfo.arch;
$mdhOsName = $RunnerOS.ToLowerInvariant();

if ($mdhArchName -eq "x64")
{
    $mdhArchName = "x86_64";
}
elseif ($mdhArchName -eq "arm64")
{
    $mdhArchName = "aarch64";
}

if ($mdhOsName -eq "linux")
{
    $mdhOsName = "linux-glibc.2.10";
}

$mdhUrl = "https://github.com/nike4613/mono-dynamic-host/releases/latest/download/$mdhArchName-$mdhOsName.zip";
echo $mdhUrl;
Invoke-WebRequest -Uri $mdhUrl -OutFile $mdhZip;

# extract mdh
7z e -y $mdhZip "-o$mdhPath";
if (Test-Path -Type Leaf "$mdh.exe")
{
    $mdh = "$mdh.exe";
}

if (-not $IsWindows)
{
    chmod ugoa+x $mdh;
}

# Need to customize NUGET_PACKAGES because we need to do a restore to pull the Mono package
$oldNUGET_PACKAGES = $env:NUGET_PACKAGES;
try {
    $env:NUGET_PACKAGES = $pkgsPath;

    # Dump the dummy project files
    $dummyProjPath = Join-Path $monoDir "dummy.csproj";
    Set-Content -Path (Join-Path $monoDir "Directory.Build.props") "<Project />";
    Set-Content -Path (Join-Path $monoDir "Directory.Build.targets") "<Project />";
    Set-Content -Path $dummyProjPath @"
<Project Sdk="Microsoft.Build.NoTargets">

  <PropertyGroup>
    <TargetFramework>$tfm</TargetFramework>
    <EnableDefaultItems>false</EnableDefaultItems>
  </PropertyGroup>

  <ItemGroup>
    <PackageDownload Include="$pkgName" Version="[$pkgVer]" />
  </ItemGroup>

</Project>
"@;

    # Generate a NuGet config that assigns the correct package source
    $nugetConfigFile = Join-Path $monoDir "nuget.config";
    $srcMap = if ($pkgSrc -ne "nuget.org") { "<packageSource key=`"$pkgSrc`"><package pattern=`"$pkgName`" /></packageSource>" } else { "" };
    Set-Content -Path $nugetConfigFile @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>

  <packageSourceMapping>
    <packageSource key="nuget.org">
      <package pattern="*" />
    </packageSource>
    $srcMap
  </packageSourceMapping>
  
</configuration>
"@;

    # Now do a restore from there
    pushd $monoDir;
    dotnet restore $dummyProjPath --packages $pkgsPath -tl:off -bl:(Join-Path $monoDir "msbuild.binlog");
    popd;

    # Now that we've done the restore, we can export the relevant information
    $pkgBasePath = Join-Path $pkgsPath $pkgName.ToLowerInvariant() $pkgVer | Resolve-Path;
    $fullLibPath = Join-Path $pkgBasePath $libPath | Resolve-Path;
    $fullDllPath = Join-Path $pkgBasePath $dllPath | Resolve-Path;

    Write-Host "Job is for .NET Mono";
    Write-Host "mdh=$mdh";
    Write-Host "mono_dll=$fullDllPath";
    Write-Host "MONO_PATH=$fullLibPath";

    echo "use_mdh=true" | Out-File $GithubOutput -Append;
    echo "mdh=$mdh" | Out-File $GithubOutput -Append;
    echo "mono_dll=$fullDllPath" | Out-File $GithubOutput -Append;
    echo "MONO_PATH=$fullLibPath" | Out-File $GithubEnv -Append;
}
finally
{
    $env:NUGET_PACKAGES = $oldNUGET_PACKAGES;
}