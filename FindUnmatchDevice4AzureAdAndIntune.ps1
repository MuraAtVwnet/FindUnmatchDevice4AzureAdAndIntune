<#
.SYNOPSIS
Azure AD と Intune に登録されているデバイスのうちアンマッチのデバイスをリストアップします

.DESCRIPTION
CSV 出力ディレクトリ指定(-CSVPath)
    CSV の出力先ディレクトリ
    省略時はカレントに出力されます

実行ログ出力ディレクトリ(-LogPath)
    実行ログの出力先
    省略時はカレントディレクトリに出力します

資格情報を使用する(-UseCredential)
    Web 対話ログインではなく、資格情報を使用します

.EXAMPLE
PS C:\Test> .\FindUnmatchDevice4AzureAdAndIntune.ps1
アンマッチデバイスリストを出力します

.EXAMPLE
PS C:\Test> .\FindUnmatchDevice4AzureAdAndIntune.ps1 -CSVPath C:\CSV
アンマッチデバイスリストを C:\CSV に出力します

.EXAMPLE
PS C:\Test> .\FindUnmatchDevice4AzureAdAndIntune.ps1 -LogPath C:\Log
実行ログを C:\Log に出力します

.EXAMPLE
PS C:\Test> .\FindUnmatchDevice4AzureAdAndIntune.ps1 -UseCredential
Web 対話ログインではなく、資格情報を使用します

.PARAMETER CSVPath
CSV の出力先
省略時はカレントディレクトリに出力します

.PARAMETER LogPath
実行ログの出力先
省略時はカレントディレクトリに出力します

.PARAMETER AllList
全デバイス リストを CSV 出力します

.PARAMETER UseCredential
Web 対話ログインではなく資格情報を使用します
#>

#######################################################
# AzureAD / Intune デバイスアンマッチ検出
# Master : Azure AD
# Tran : Intune
#######################################################
Param(
	[string]$CSVPath,			# CSV 出力 Path
	[string]$LogPath,			# ログ出力ディレクトリ
	[switch]$UseCredential,		# 資格情報を使用する
	[switch]$IdOnly				# デバイス名を含めずマッチングする

	)

# 重複デバイスデータ名
$GC_DuplicateDeviceName = "UnmatchDevice"

# ログの出力先
if( $LogPath -eq [string]$null ){
	$GC_LogPath = Convert-Path .
}
else{
	$GC_LogPath = $LogPath
}

# ログファイル名
$GC_LogName = "FindUnmatchDevice"

# CSV レコード
class CsvRecode {
	[string] $DeviceName
	[string] $AzureAdDeviceID_Azure
	[string] $AzureAdObjectID
	[string] $AzureAdDeviceID_Intune
	[string] $IntuneDeviceID
	[string] $AzureADOnly
	[string] $IntuneOnly
	[string] $Match
}


# マッチング状態定数
$LC_Mode_Matchi = 0
$LC_Mode_MasterOnly = 1
$LC_Mode_TranOnly = 2
$LC_Mode_Oter = 9

##########################################################################
# ログ出力
##########################################################################
function Log(
			$LogString
			){

	$Now = Get-Date

	# Log 出力文字列に時刻を付加(YYYY/MM/DD HH:MM:SS.MMM $LogString)
	$Log = $Now.ToString("yyyy/MM/dd HH:mm:ss.fff") + " "
	$Log += $LogString

	# ログファイル名が設定されていなかったらデフォルトのログファイル名をつける
	if( $GC_LogName -eq $null ){
		$GC_LogName = "LOG"
	}

	# ログファイル名(XXXX_YYYY-MM-DD.log)
	$LogFile = $GC_LogName + "_" +$Now.ToString("yyyy-MM-dd") + ".log"

	# ログフォルダーがなかったら作成
	if( -not (Test-Path $GC_LogPath) ) {
		New-Item $GC_LogPath -Type Directory
	}

	# ログファイル名
	$LogFileName = Join-Path $GC_LogPath $LogFile

	# ログ出力
	Write-Output $Log | Out-File -FilePath $LogFileName -Encoding Default -append

	# echo
	[System.Console]::WriteLine($Log)
}

###################################################
# AzureAD データにマッチングキー追加
###################################################
filter AddMatchingKey4AzureAD{
	if( $IdOnly ){
		$MatchingKey = $_.DeviceId
	}
	else{
		$MatchingKey = $_.DisplayName + ":" + $_.DeviceId
	}
	Add-Member -InputObject $_ -MemberType NoteProperty -Name MatchingKey -Value $MatchingKey -Force
	return $_
}

###################################################
# Intune データにマッチングキー追加
###################################################
filter AddMatchingKey4Intune{
	if( $IdOnly ){
		$MatchingKey = $_.azureADDeviceId
	}
	else{
		$MatchingKey = $_.deviceName + ":" + $_.azureADDeviceId
	}
	Add-Member -InputObject $_ -MemberType NoteProperty -Name MatchingKey -Value $MatchingKey -Force
	return $_
}

###################################################
# AzureAD データセット
###################################################
function SetAzureAdDeviceData($AzureADData){

	$DeviceData = New-Object CsvRecode

	# デバイス名(DeviceName)
	$DeviceData.DeviceName = $AzureADData.DisplayName

	# デバイス ID(AzureAdDeviceID_Azure)
	$DeviceData.AzureAdDeviceID_Azure = $AzureADData.DeviceId

	# デバイス ID(AzureAdDeviceID_Intune)

	# オブジェクト ID(AzureAdObjectID)
	$DeviceData.AzureAdObjectID = $AzureADData.ObjectId

	# 管理デバイス ID(IntuneDeviceID)

	# Azure AD Only
	$DeviceData.AzureADOnly = '*'


	return $DeviceData
}

###################################################
# Intune データセット
###################################################
function SetIntuneDeviceData($IntuneData){

	$DeviceData = New-Object CsvRecode

	# デバイス名(DeviceName)
	$DeviceData.DeviceName = $IntuneData.deviceName

	# デバイス ID(AzureAdDeviceID_Azure)

	# デバイス ID(AzureAdDeviceID_Intune)
	$DeviceData.AzureAdDeviceID_Intune = $IntuneData.azureADDeviceId

	# オブジェクト ID(AzureAdObjectID)

	# 管理デバイス ID(IntuneDeviceID)
	$DeviceData.IntuneDeviceID = $IntuneData.managedDeviceId

	# Intune Only
	$DeviceData.IntuneOnly = '*'

	return $DeviceData
}

###################################################
# AzureAD & Intuneデータセット
###################################################
function SetAzureAdAndIntuneDeviceData($AzureADData, $IntuneData){

	$DeviceData = New-Object CsvRecode

	# デバイス名(DeviceName)
	$DeviceData.DeviceName = $AzureADData.DisplayName

	# デバイス ID(AzureAdDeviceID_Azure)
	$DeviceData.AzureAdDeviceID_Azure = $AzureADData.DeviceId

	# デバイス ID(AzureAdDeviceID_Intune)
	$DeviceData.AzureAdDeviceID_Intune = $IntuneData.azureADDeviceId

	# オブジェクト ID(AzureAdObjectID)
	$DeviceData.AzureAdObjectID = $AzureADData.ObjectId

	# 管理デバイス ID(IntuneDeviceID)
	$DeviceData.IntuneDeviceID = $IntuneData.managedDeviceId

	# Match
	$DeviceData.Match = '*'

	return $DeviceData
}



#######################################################
# マスター Key セット
#######################################################
function SetMasterKey($MasterObjects){
	return $MasterObjects.MatchingKey
}

#######################################################
# トランキー Key セット
#######################################################
function SetTranKey($TranObjects){
	return $TranObjects.MatchingKey
}

#######################################################
# マッチング 状態判定
#######################################################
function GetMatchingStatus( $MasterKey, $Master_EOD, $TranKey, $Tran_EOD ){
	$ReturnMode = $LC_Mode_Oter

	# マスター終了
	if( $Master_EOD -eq $true ){
		$ReturnMode = $LC_Mode_TranOnly
	}

	# トラン終了
	elseif( $Tran_EOD -eq $true ){
		$ReturnMode = $LC_Mode_MasterOnly
	}

	# キーが等しい
	elseif( $MasterKey -eq $TranKey ){
		$ReturnMode = $LC_Mode_Matchi
	}

	# マスターが小さい
	elseif( $MasterKey -lt $TranKey ){
		$ReturnMode = $LC_Mode_MasterOnly
	}

	# トランが小さい
	elseif( $TranKey -lt $MasterKey ){
		$ReturnMode = $LC_Mode_TranOnly
	}

	return $ReturnMode
}

#######################################################
# マッチング処理
#######################################################
function Matching([array]$MasterObjects, [array]$TranObjects){

	### Master前処理
	# Master 終わったフラグ
	$Master_EOD = $false
	# Sort
	[array]$MasterData = $MasterObjects | Sort-Object  -Property MatchingKey
	# Max 件数
	$Master_Max = $MasterData.Count
	# Key 初期セットset
	$Master_Index = 0
	if( $MasterData.Count -ne 0 ){
		$MasterKey = SetMasterKey $MasterData[$Master_Index]
	}
	else{
		$Master_EOD = $true
	}

	### Tran 前処理
	# Tran 終わったフラグ
	$Tran_EOD = $false
	# Sort
	[array]$TranData = $TranObjects | Sort-Object  -Property MatchingKey
	# Max 件数
	$Tran_Max = $TranData.Count
	# Key 初期セットset
	$Tran_Index = 0
	if( $TranData.Count -ne 0 ){
		$TranKey = SetTranKey $TranData[$Tran_Index]
	}
	else{
		$Tran_EOD = $true
	}

	# Master Only Data
	$MasterOnlyData = @()

	# Tran Only Data
	$TranOnlyData = @()

	# MatchData
	$MatchData = @()

	# 件数カウンター
	$MatchCount = 0
	$MasterOnlyCount = 0
	$TranOnlyCount = 0


	# マッチング
	while( -not (($Master_EOD -eq $true) -and ($Tran_EOD -eq $true)) ){

		# マッチング 状態取得
		$MatchingStatus = GetMatchingStatus $MasterKey $Master_EOD $TranKey $Tran_EOD

		# Master Only
		if( $MatchingStatus -eq $LC_Mode_MasterOnly ){

			# Master データ収集
			$AddData = $MasterData[$Master_Index]
			$MasterOnlyData += SetAzureAdDeviceData $AddData

			# Master Key Set
			$NowKey = $MasterKey

			# キーが割れるまで読み飛ばす
			do{
				# 件数カウント
				$MasterOnlyCount++

				$Master_Index++
				if( $Master_Index -ge $Master_Max ){
					$Master_EOD = $true
					$NewKey = $null
				}
				else{
					$MasterKey = SetMasterKey $MasterData[$Master_Index]
					$NewKey = $MasterKey
				}
			}while( $NowKey -eq $NewKey )

		}
		# Tran Only
		elseif( $MatchingStatus -eq $LC_Mode_TranOnly ){

			# Tran データ収集
			$AddData = $TranData[$Tran_Index]
			$TranOnlyData += SetIntuneDeviceData $AddData

			# Tran Key Set
			$NowKey = $TranKey

			# キーが割れるまで読み飛ばす
			do{
				# 件数カウント
				$TranOnlyCount++

				$Tran_Index++
				if( $Tran_Index -ge $Tran_Max ){
					$Tran_EOD = $true
					$NewKey = $null
				}
				else{
					$TranKey = SetTranKey $TranData[$Tran_Index]
					$NewKey = $TranKey
				}
			}while( $NowKey -eq $NewKey )
		}

		# マッチ
		else{

			# Match データ収集
			# (Master をセット。必要に応じて Tran セットに書き換える)
			$AddMasterData = $MasterData[$Master_Index]
			$AddTranData = $TranData[$Tran_Index]
			$MatchData += SetAzureAdAndIntuneDeviceData $AddMasterData $AddTranData

			# Master Key Set
			$NowKey = $MasterKey

			# キーが割れるまで読み飛ばす
			do{
				# 件数カウント
				$MatchCount++

				$Master_Index++
				if( $Master_Index -ge $Master_Max ){
					$Master_EOD = $true
					$NewKey = $null
				}
				else{
					$MasterKey = SetMasterKey $MasterData[$Master_Index]
					$NewKey = $MasterKey
				}
			}while( $NowKey -eq $NewKey )


			# Tran Key Set
			$NowKey = $TranKey
			do{ # キーが割れるまで読み飛ばす
				$Tran_Index++
				if( $Tran_Index -ge $Tran_Max ){
					$Tran_EOD = $true
					$NewKey = $null
				}
				else{
					$TranKey = SetTranKey $TranData[$Tran_Index]
					$NewKey = $TranKey
				}
			}while( $NowKey -eq $NewKey )
		}
	}


	# 戻り値セット
	$ReturnData = New-Object PSObject | Select-Object `
			MasterOnlyData, # マスターオンリー
			MatchData,		# マッチ
			TranOnlyData	# トランオンリー

	$ReturnData.MasterOnlyData = $MasterOnlyData
	$ReturnData.MatchData	   = $MatchData
	$ReturnData.TranOnlyData   = $TranOnlyData

	return $ReturnData
}

###################################################
# アンマッチデータ出力
###################################################
function OutputUnmatchData([array]$SortDevicesData, $Now){

	$OutputFile = Join-Path $CSVPath ($GC_DuplicateDeviceName + "_" +$Now.ToString("yyyy-MM-dd_HH-mm") + ".csv")

	Log "[INFO] Output unmatch Device list : $OutputFile"

	if( -not(Test-Path $CSVPath)){
		mdkdir $CSVPath
	}

	$SortDevicesData | Export-Csv -Path $OutputFile -Encoding Default
}


#######################################################
# main
#######################################################
Log "[INFO] ============== START =============="

# 動作環境確認
if( $PSVersionTable.PSVersion.Major -ne 5 ){
	Log "[FAIL] このスクリプトは Windows PowerShell 5 のみサポートしています"
	Log "[INFO] ============== END =============="
	exit
}

# AzureAD モジュール ロード
try{
	Import-Module -Name AzureAD -ErrorAction Stop
}
catch{
	# 管理権限で起動されているか確認
	if (-not(([Security.Principal.WindowsPrincipal] `
		[Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
		[Security.Principal.WindowsBuiltInRole] "Administrator"`
		))) {

		Log "[INFO] 必要モジュールがインストールされていません"
		Log "[INFO] 管理権限で起動してスクリプトを実行するか、管理権限で以下コマンドを実行してください"
		Log "[INFO] Install-Module -Name AzureAD"
		Log "[INFO] ============== END =============="
		exit
	}

	# 管理権限で実行されているのでモジュールをインストールする
	Log "[INFO] 必要モジュールをインストールします"
	Install-Module -Name AzureAD
}


# Intune モジュール ロード
try{
	Import-Module -Name Microsoft.Graph.Intune -ErrorAction Stop
}
catch{
	# 管理権限で起動されているか確認
	if (-not(([Security.Principal.WindowsPrincipal] `
		[Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
		[Security.Principal.WindowsBuiltInRole] "Administrator"`
		))) {

		Log "[INFO] 必要モジュールがインストールされていません"
		Log "[INFO] 管理権限で起動してスクリプトを実行するか、管理権限で以下コマンドを実行してください"
		Log "[INFO] Install-Module Microsoft.Graph.Intune"
		Log "[INFO] ============== END =============="
		exit
	}

	# 管理権限で実行されているのでモジュールをインストールする
	Log "[INFO] 必要モジュールをインストールします"
	Install-Module Microsoft.Graph.Intune
}

# 資格情報を使用
if( $UseCredential ){
	$Credential = Get-Credential -Message "Azure の ID / Password を入力してください"
}


# Azure AD Login
try{
	if( $UseCredential ){
		Connect-AzureAD -Credential $Credential -ErrorAction Stop
	}
	else{
		Connect-AzureAD -ErrorAction Stop
	}
}
catch{
	Log "[FAIL] Azure login fail !"
	Log "[INFO] ============== END =============="
	exit
}

# Azure AD 全デバイスを取得
[array]$AzureAdDevicesData = Get-AzureADDevice -All $true | AddMatchingKey4AzureAD

# 対象デバイス数表示
$Count = $AzureAdDevicesData.Count
Log "[INFO] Azure AD Devices count : $Count"

# Intune Login
try{
	if( $UseCredential ){
		Connect-MSGraph -Credential $Credential -ErrorAction Stop
	}
	else{
		Connect-MSGraph -ErrorAction Stop
	}
}
catch{
	Log "[FAIL] Intune login fail !"
	Log "[INFO] ============== END =============="
	exit
}

# Intune 全デバイスを取得
[array]$IntuneDevicesData = Get-IntuneManagedDevice | AddMatchingKey4Intune

# 対象デバイス数表示
$Count = $IntuneDevicesData.Count
Log "[INFO] Intune Devices count : $Count"

# CSV 出力先
if( $CSVPath -eq [string]$null){
	$CSVPath = Convert-Path .
}

# マッチング
$RetData = Matching $AzureAdDevicesData $IntuneDevicesData

# マッチング結果データ取り出し
[array]$CsvData = $RetData.MasterOnlyData
$CsvData += $RetData.TranOnlyData
$CsvData += $RetData.MatchData

# 出力データ sort
[array]$SortCsvData = $CsvData | Sort-Object -Property DeviceName, AzureAdDeviceID, IntuneDeviceID

# 出力ファイル用処理時間
$Now = Get-Date

# 重複データ出力
OutputUnmatchData $SortCsvData $Now

Log "[INFO] ============== END =============="
