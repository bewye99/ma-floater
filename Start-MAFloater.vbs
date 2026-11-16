Option Explicit

Dim shell, fileSystem, projectRoot, playerScript, windowsPowerShell, command

Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")

projectRoot = fileSystem.GetParentFolderName(WScript.ScriptFullName)
playerScript = fileSystem.BuildPath(projectRoot, "bin\MAFloater.ps1")
windowsPowerShell = shell.ExpandEnvironmentStrings("%SystemRoot%") & _
    "\System32\WindowsPowerShell\v1.0\powershell.exe"

command = Quote(windowsPowerShell) & _
    " -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File " & _
    Quote(playerScript)

shell.Run command, 0, False

Function Quote(value)
    Quote = Chr(34) & value & Chr(34)
End Function
