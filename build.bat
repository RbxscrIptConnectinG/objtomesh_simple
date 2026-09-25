:: recomended.
@echo off
echo building objtomesh...
zune bundle src/toMesh/main.luau src/toMesh/**/*.luau applibs/**/*.luau libs/luau/** -f libs/bin/** -f assets/toMesh/** -f .luaurc  --out=build/debug/objtomesh.exe --debug

ResourceHacker -open build/debug/objtomesh.exe -save build/debug/objtomesh.exe -resource assets/toMesh/images/icons/util/icon.ico -mask ICONGROUP,MAINICON, -action addoverwrite -log CONSOLE
ResourceHacker.exe -open assets/toMesh/bin/version/version.rc -save assets/toMesh/bin/version/version.res -action compile -log CONSOLE
ResourceHacker.exe -open build/debug/objtomesh.exe -save build/debug/objtomesh.exe -resource assets/toMesh/bin/version/version.res -action addoverwrite -mask VersionInfo,, -log CONSOLE
echo built objtomesh!