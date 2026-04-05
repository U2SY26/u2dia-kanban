Set WshShell = CreateObject("WScript.Shell")
WshShell.CurrentDirectory = "E:\agents_team"
WshShell.Run "pythonw server.py --no-browser", 0, False
