local fs = zune.fs
return {
	IsVSC = #fs.embeddedFiles() <= 0,
}
