[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$shortcutName = 'MA Floater.lnk'
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$playerScript = Join-Path $projectRoot 'bin\MAFloater.ps1'
$launcherScript = Join-Path $projectRoot 'Start-MAFloater.vbs'
$iconPath = Join-Path $projectRoot 'assets\ma-floater.ico'
$windowsScriptHost = Join-Path $env:WINDIR 'System32\wscript.exe'
$windowsPowerShell = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$programsFolder = [Environment]::GetFolderPath('Programs')
$shortcutPath = Join-Path $programsFolder $shortcutName
$appUserModelId = 'MAFloater.Desktop'

if (-not ('MAFloater.ShortcutIdentity' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace MAFloater
{
    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    internal struct PropertyKey
    {
        internal Guid FormatId;
        internal uint PropertyId;
    }

    [StructLayout(LayoutKind.Explicit, Size = 16)]
    internal struct PropVariant
    {
        [FieldOffset(0)] internal ushort VarType;
        [FieldOffset(8)] internal IntPtr PointerValue;
    }

    [ComImport]
    [Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IPropertyStore
    {
        [PreserveSig] int GetCount(out uint propertyCount);
        [PreserveSig] int GetAt(uint propertyIndex, out PropertyKey key);
        [PreserveSig] int GetValue(ref PropertyKey key, out PropVariant value);
        [PreserveSig] int SetValue(ref PropertyKey key, ref PropVariant value);
        [PreserveSig] int Commit();
    }

    public static class ShortcutIdentity
    {
        private const uint ReadWrite = 0x2;
        private static readonly Guid PropertyStoreId =
            new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
        private static readonly Guid AppUserModelFormat =
            new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");

        [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
        private static extern void SHGetPropertyStoreFromParsingName(
            string path,
            IntPtr bindingContext,
            uint flags,
            ref Guid interfaceId,
            [MarshalAs(UnmanagedType.Interface)] out IPropertyStore propertyStore);

        [DllImport("ole32.dll")]
        private static extern int PropVariantClear(ref PropVariant propVariant);

        public static void SetAppUserModelId(string shortcutPath, string appId)
        {
            IPropertyStore propertyStore;
            Guid interfaceId = PropertyStoreId;
            SHGetPropertyStoreFromParsingName(
                shortcutPath,
                IntPtr.Zero,
                ReadWrite,
                ref interfaceId,
                out propertyStore);

            try
            {
                PropertyKey key = new PropertyKey
                {
                    FormatId = AppUserModelFormat,
                    PropertyId = 5
                };
                PropVariant value = new PropVariant
                {
                    VarType = 31,
                    PointerValue = Marshal.StringToCoTaskMemUni(appId)
                };
                try
                {
                    Marshal.ThrowExceptionForHR(propertyStore.SetValue(ref key, ref value));
                    Marshal.ThrowExceptionForHR(propertyStore.Commit());
                }
                finally
                {
                    PropVariantClear(ref value);
                }
            }
            finally
            {
                Marshal.FinalReleaseComObject(propertyStore);
            }
        }
    }
}
'@
}

if (-not (Test-Path -LiteralPath $playerScript)) {
    & (Join-Path $projectRoot 'Build.ps1')
}
if (-not (Test-Path -LiteralPath $iconPath)) {
    throw "The MA Floater icon is missing: $iconPath"
}
if (-not (Test-Path -LiteralPath $launcherScript)) {
    throw "The windowless MA Floater launcher is missing: $launcherScript"
}

$arguments = '"' + $launcherScript + '"'
$legacyArguments = '-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $playerScript + '"'
$iconLocation = $iconPath + ',0'
$shell = New-Object -ComObject WScript.Shell

if (Test-Path -LiteralPath $shortcutPath) {
    $existing = $shell.CreateShortcut($shortcutPath)
    $matchesCurrent = $existing.TargetPath -eq $windowsScriptHost -and
        $existing.Arguments -eq $arguments
    $matchesLegacy = $existing.TargetPath -eq $windowsPowerShell -and
        $existing.Arguments -eq $legacyArguments
    if ((-not $matchesCurrent -and -not $matchesLegacy) -or
        $existing.WorkingDirectory -ne $projectRoot) {
        throw "A different shortcut already uses '$shortcutPath'; refusing to replace it."
    }
}

$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $windowsScriptHost
$shortcut.Arguments = $arguments
$shortcut.WorkingDirectory = $projectRoot
$shortcut.IconLocation = $iconLocation
$shortcut.Description = 'Open MA Floater for Music Assistant.'
$shortcut.Save()
[MAFloater.ShortcutIdentity]::SetAppUserModelId($shortcutPath, $appUserModelId)

$shellApplication = New-Object -ComObject Shell.Application
$shortcutFolder = $shellApplication.Namespace($programsFolder)
$shortcutItem = $shortcutFolder.ParseName($shortcutName)
$savedAppUserModelId = [string]$shortcutItem.ExtendedProperty('System.AppUserModel.ID')
if ($savedAppUserModelId -ne $appUserModelId) {
    throw "The MA Floater shortcut identity could not be verified."
}

[pscustomobject]@{
    Name = 'MA Floater'
    Path = $shortcutPath
    Target = $windowsScriptHost
    AppUserModelId = $savedAppUserModelId
}
