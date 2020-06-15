■ 概要
Azure AD と Intune に登録されているデバイスのうちアンマッチのデバイスをリストアップします

■ オプション
CSV 出力ディレクトリ指定(-CSVPath)
    CSV の出力先ディレクトリ
    省略時はカレントに出力されます

実行ログ出力ディレクトリ(-LogPath)
    実行ログの出力先
    省略時はカレントディレクトリに出力します


■ 例
PS C:\Test> .\FindUnmatchDevice4AzureAdAndIntune.ps1
アンマッチデバイスリストを出力します

PS C:\Test> .\FindUnmatchDevice4AzureAdAndIntune.ps1 -CSVPath C:\CSV
アンマッチデバイスリストを C:\CSV に出力します

PS C:\Test> .\FindUnmatchDevice4AzureAdAndIntune.ps1 -LogPath C:\Log
実行ログを C:\Log に出力します
