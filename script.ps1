if ($args[0].Length -eq 0){
	write-host "Please provide the URL to the m3u8 file as an input paramater"
	Exit 1
}

$instr = $args[0]
write-host "m3u8 URL is $instr"

$workarr = $instr.Split("/")
$workurl = ($workarr[0..($workarr.Length - 2)] -join "/") + "/"
$m3u8Raw = (Invoke-WebRequest $instr).RawContent
$m3arr1 = $m3u8Raw.Split([Environment]::NewLine)
$EXTBegin = 0
$contentstr = @()

write-host "Downloading segments"

foreach ($line in $m3arr1) {
	if ($EXTBegin -eq 0){
		if ($line.Contains('EXTM3U')){
			$EXTBegin = 1
		}
	}
	else {
		if (!$line.Contains("#")){
			if ($line.Trim() -ne ""){
				$val = ($workurl + $line)
				$fpath = $PSScriptRoot + "\Working\" + $line
				$contentstr += $fpath
				Start-Process -NoNewWindow -FilePath "$PSScriptRoot\curl\bin\curl.exe" -ArgumentList "-ks","$val","-o","$fpath"
				if ($line.Contains("00.ts")){
					write-host $line
				}
			}
		}
	}
}

foreach ($file in $contentstr) {
	$isLocked = 1
	while ($isLocked -eq 1) { 
		If ([System.IO.File]::Exists($file)) {
			Try {
				$FileStream = [System.IO.File]::Open($file,'Open','Write')

				$FileStream.Close()
				$FileStream.Dispose()

				$IsLocked = 0
			} Catch [System.UnauthorizedAccessException] {
				$IsLocked = 1
				Start-Sleep 5
				write-host "waiting on $file"
			} Catch {
				$IsLocked = 1
				Start-Sleep 5
				write-host "waiting on $file"
			}
		}
	}
}

$FileStream.Close()
$FileStream.Dispose()


write-host "All files downloaded!"
write-host "Concatenating to final.ts"
$flist = Get-ChildItem -Path $PSScriptRoot\Working -Include *.ts -name | Sort { [regex]::Replace($_, '\d+', { $args[0].Value.PadLeft(20) }) }
$flist | ForEach-Object { Get-Content .\Working\$_ -Raw | Add-Content "$PSScriptRoot\Working\final.ts" }

write-host "Converting to mp4"
& $PSScriptRoot\FF64\ffmpeg.exe -i $PSScriptRoot\Working\final.ts -acodec copy -vcodec copy "$PSScriptRoot\Output\Outfile.mp4"

write-host "Cleaning working directory"
Remove-Item $PSScriptRoot\Working\*.ts
