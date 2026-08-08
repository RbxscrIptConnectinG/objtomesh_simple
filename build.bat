zune bundle src/main.luau src/**/*.luau --out=build/debug/objtomesh.exe --debug



ResourceHacker -open build/debug/objtomesh.exe -save build/debug/objtomesh.exe -resource assets/icon.ico -mask ICONGROUP,MAINICON, -action addoverwrite -log CONSOLE
ResourceHacker.exe -open assets/version.rc -save assets/version.res -action compile -log CONSOLE
ResourceHacker.exe -open build/debug/objtomesh.exe -save build/debug/objtomesh.exe -resource assets/version.res -action addoverwrite -mask VersionInfo,, -log CONSOLE