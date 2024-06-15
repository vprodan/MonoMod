$useMdh = $env:USE_MDH -eq "true";
$exe = if ($useMdh) { $env:MDH } else { $env:MONO_DLL };
$exeargs = if ($useMdh) { @($env:MONO_DLL) } else { @() };

echo $exe;
echo $exeargs;

# TODO: this xUnit TFM is incorrect for some targets. We'd really like to use vstest on .NET Mono, as that will keep things somewhat simpler.
&$exe @exeargs "$($env:NUGET_PACKAGES)/xunit.runner.console/$($env:XunitVersion)/tools/$($env:TFM)/xunit.console.exe" `
    "release_$($env:TFM)/MonoMod.UnitTest.dll" -junit "$($env:LOG_FILE_NAME).xml"
