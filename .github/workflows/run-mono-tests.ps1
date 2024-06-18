$useMdh = $env:USE_MDH -eq "true";
[string]$exe = if ($useMdh) { $env:MDH } else { $env:MONO_DLL };
[string[]]$exeargs = if ($useMdh) { @($env:MONO_DLL) } else { @() };

# TODO: this xUnit TFM is incorrect for some targets. We'd really like to use vstest on .NET Mono, as that will keep things somewhat simpler.
&$exe @exeargs "$($env:NUGET_PACKAGES)/xunit.runner.console/$($env:XunitVersion)/tools/$($env:RUNNER_TFM)/xunit.console.exe" `
    "release_$($env:TFM)/MonoMod.UnitTest.dll" -junit "$($env:LOG_FILE_NAME).xml"
