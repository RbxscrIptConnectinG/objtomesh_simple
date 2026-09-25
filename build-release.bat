:: use this if you don't want huge exe file
@echo off
echo building objtomesh...
zune bundle src/toMesh/main.luau src/toMesh/**/*.luau applibs/**/*.luau libs/luau/** -f libs/bin/** -f assets/toMesh/** -f .luaurc  --out=build/release/objtomesh.exe --compression=zstd --release --native -O2

ResourceHacker -open build/release/objtomesh.exe -save build/release/objtomesh.exe -resource assets/toMesh/images/icons/util/icon.ico -mask ICONGROUP,MAINICON, -action addoverwrite -log CONSOLE
ResourceHacker.exe -open assets/toMesh/bin/version/version.rc -save assets/toMesh/bin/version/version.res -action compile -log CONSOLE
ResourceHacker.exe -open build/release/objtomesh.exe -save build/release/objtomesh.exe -resource assets/toMesh/bin/version/version.res -action addoverwrite -mask VersionInfo,, -log CONSOLE
echo built objtomesh!