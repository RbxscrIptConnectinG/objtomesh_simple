@echo off
echo building objtomesh...
zune bundle src/toMesh/main.luau src/toMesh/**/*.luau --out=build/debug/objtomesh.exe --debug



ResourceHacker -open build/debug/objtomesh.exe -save build/debug/objtomesh.exe -resource assets/toMesh/icon.ico -mask ICONGROUP,MAINICON, -action addoverwrite -log CONSOLE
ResourceHacker.exe -open assets/toMesh/version.rc -save assets/toMesh/version.res -action compile -log CONSOLE
ResourceHacker.exe -open build/debug/objtomesh.exe -save build/debug/objtomesh.exe -resource assets/toMesh/version.res -action addoverwrite -mask VersionInfo,, -log CONSOLE
echo built objtomesh!