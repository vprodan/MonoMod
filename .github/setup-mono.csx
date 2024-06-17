#!/usr/bin/env dotnet script
#nullable enable
#r "nuget:Chell,1.0.0"
#r "nuget:NuGet.Frameworks,6.10.0"
#r "nuget:NuGet.Configuration,6.10.0"
#r "nuget:NuGet.Protocol,6.10.0"

using Chell;
using NuGet.Frameworks;
using System.IO.Compression;
using static Chell.Exports;

static string GetScriptFolder([System.Runtime.CompilerServices.CallerFilePath] string path = "") => Path.GetDirectoryName(path) ?? ".";
var ScriptDir = GetScriptFolder();

if (Args is not [{ } matrixJson, { } githubOutputFile, { } githubEnvFile, { } runnerOs])
{
    Console.WriteLine("Must have 4 arguments: the job json, the github outputs file, the github env file, and the runner OS");
    return 1;
}

githubOutputFile = Path.GetFullPath(githubOutputFile);
githubEnvFile = Path.GetFullPath(githubEnvFile);

var jobInfo = FromJson(matrixJson, new
{
    arch = "",
    dotnet = new
    {
        isMono = false,
        systemMono = false,
        tfm = "",
        netMonoNugetSrc = (string?)null,
        netMonoPkgName = (string?)null,
        netMonoPkgVer = (string?)null,
        monoLibPath = (string?)null,
        monoDllPath = (string?)null,
    }
});

if (jobInfo is null)
{
    Console.WriteLine("Job info was null");
    return 1;
}

if (!jobInfo.dotnet.isMono)
{
    Console.WriteLine("Nothing to do, job is not a Mono job");
    return 0;
}

// TODO: use NuGet libs to automatically determine matching xunit console tfm
var tfm = jobInfo.dotnet.tfm;
var ntf = NuGetFramework.Parse(tfm);

var runnerTfm = NuGetFrameworkUtility.GetNearest(
    [ // xUnit.runner.console package /tools/ TFMs
        "net452",
        "net46",
        "net461",
        "net462",
        "net47",
        "net471",
        "net472",
        "netcoreapp1.0",
        "netcoreapp2.0",
    ],
    ntf,
    NuGetFramework.Parse);

// set the output
File.AppendAllLines(githubOutputFile, [$"runner_tfm={runnerTfm}"]);

if (jobInfo.dotnet.systemMono)
{
    if (!TryWhich("mono", out var monoPath))
    {
        Console.WriteLine("System mono job, but could not find system Mono on PATH");
        return 1;
    }

    Console.WriteLine($"Job is for system mono; using mono={monoPath}");
    File.AppendAllLines(githubOutputFile, [
        "use_mdh=false",
        $"mono_dll={monoPath}",
    ]);
    return 0;
}

var pkgSrc = jobInfo.dotnet.netMonoNugetSrc;
var pkgName = jobInfo.dotnet.netMonoPkgName;
var pkgVer = jobInfo.dotnet.netMonoPkgVer;
var libPath = jobInfo.dotnet.monoLibPath;
var dllPath = jobInfo.dotnet.monoDllPath;

if (pkgSrc is null || pkgName is null || pkgVer is null || libPath is null || dllPath is null)
{
    Console.WriteLine("Job info is missing some required properties");
    return 1;
}

var repoRoot = Path.GetFullPath(Path.Combine(ScriptDir, ".."));
var monoDir = Path.Combine(repoRoot, ".mono");
Directory.CreateDirectory(monoDir);

// Lets download MDH
var mdhDir = Path.Combine(monoDir, "mdh");
var mdhExe = Path.Combine(mdhDir, "mdh");

{
    var mdhZip = Path.Combine(monoDir, "mdh.zip");

    // compute the arch name
    var mdhArch = jobInfo.arch;
    var osName = runnerOs.ToLowerInvariant();
    mdhArch = mdhArch switch
    {
        "x64" => "x86_64",
        "arm64" => "aarch64",
        var x => x
    };
    if (osName is "linux")
    {
        osName = "linux-gnu.2.10";
    }

    // download the file
    var url = $"https://github.com/nike4613/mono-dynamic-host/releases/latest/download/{mdhArch}-{osName}.zip";
    
    using (var file = File.Create(mdhZip))
    {
        using var stream = await FetchStreamAsync(url);
        await stream.CopyToAsync(file);
    }

    // extract the archive
    if (Directory.Exists(mdhDir))
    {
        Directory.Delete(mdhDir, true);
    }
    ZipFile.ExtractToDirectory(mdhZip, mdhDir);

    // update mdhExe
    if (File.Exists(mdhExe + ".exe"))
    {
        mdhExe = mdhExe + ".exe";
    }

    if (!Env.IsWindows)
    {
        // on non-Windows, mark the exe executable
        await Run($"chmod +x {mdhExe}");
    }
}

// now we want to restore the Mono package

// TODO: do NuGet restore with NuGet APIs

var origNugetPackages = Env.Vars["NUGET_PACKAGES"];
try
{
    var pkgsPath = Path.Combine(monoDir, "pkg");
    Env.Vars["NUGET_PACKAGES"] = pkgsPath;

    var dummyProjPath = Path.Combine(monoDir, "dummy.csproj");
    // set up project files
    File.WriteAllText(Path.Combine(monoDir, "Directory.Build.props"), "<Project />");
    File.WriteAllText(Path.Combine(monoDir, "Directory.Build.targets"), "<Project />");
    File.WriteAllText(dummyProjPath, $"""
        <Project Sdk="Microsoft.Build.NoTargets">

          <PropertyGroup>
            <TargetFramework>{tfm}</TargetFramework>
            <EnableDefaultItems>false</EnableDefaultItems>
          </PropertyGroup>

          <ItemGroup>
            <PackageDownload Include="{pkgName}" Version="[{pkgVer}]" />
          </ItemGroup>

        </Project>
        """);

    var nugetConfigFile = Path.Combine(monoDir, "nuget.config");
    var embeddedMapping = pkgSrc == "nuget.org"
        ? ""
        : $"<packageSource key=\"{pkgSrc}\"><package pattern=\"{pkgName}\" /></packageSource>";
    File.WriteAllText(nugetConfigFile, $"""
        <?xml version="1.0" encoding="utf-8"?>
        <configuration>

          <packageSourceMapping>
            <packageSource key="nuget.org">
              <package pattern="*" />
            </packageSource>
            {embeddedMapping}
          </packageSourceMapping>

        </configuration>
        """);

    using (Cd(monoDir))
    {
        await Run($"dotnet restore {dummyProjPath} --packages {pkgsPath} -tl:off -bl:{Path.Combine(monoDir, "msbuild.binlog")}");
    }

    var pkgBase = Path.Combine(pkgsPath, pkgName.ToLowerInvariant(), pkgVer);
    var fullLibPath = Path.GetFullPath(Path.Combine(pkgBase, libPath));
    var fullDllPath = Path.GetFullPath(Path.Combine(pkgBase, dllPath));

    Console.WriteLine($"""
        Job is for .NET Mono
        mdh={mdhExe}
        mono_dll={fullDllPath}
        MONO_PATH={fullLibPath}
        """);

    File.AppendAllLines(githubOutputFile, [
        "use_mdh=true",
        $"mdh={mdhExe}",
        $"mono_dll={fullDllPath}",
    ]);
    File.AppendAllLines(githubEnvFile, [
        $"MONO_PATH={fullLibPath}"
    ]);
}
finally
{
    Env.Vars["NUGET_PACKAGES"] = origNugetPackages;
}

return 0;