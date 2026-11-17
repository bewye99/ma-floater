# MA Floater

MA Floater is an unofficial, lightweight floating controller for [Music Assistant](https://www.music-assistant.io/) on Windows 11. It follows the currently playing Music Assistant queue, stays above other windows when requested, and collapses to a compact now-playing view when it is not being used.

MA Floater is an independent community project. It is not affiliated with or endorsed by Music Assistant or the Open Home Foundation.

The current 0.1.1 PowerShell implementation is described below. The repository also contains an in-progress native .NET/WPF replacement and single-EXE Windows installer, but no native executable or installer is included in the public release.

## Features

- Album artwork, song, artist, and active-player name
- Previous, play/pause, next, shuffle, and repeat controls
- Live volume slider when the active player supports volume control
- Automatic switching to an available queue that starts playing
- Optional preferred fallback queue when nothing is actively playing
- Compact artwork/title/artist view after 15 seconds away from the pointer
- Full controls restored on hover
- Always-on-top, minimize, resize, and remembered window position
- System-tray restore and exit controls
- Branded multi-resolution tray and full-size taskbar icon
- Optional per-user Start menu entry
- Optional per-user autostart after Windows sign-in
- Current 0.1.1 PowerShell implementation uses no third-party packages or compiled executable

## Requirements and compatibility

- Windows 11
- A reachable Music Assistant server with built-in user authentication enabled
- A dedicated Music Assistant account with the **Guest** role

The current PowerShell implementation requires Windows PowerShell 5.1 and the .NET components included with Windows. Users do not need the .NET SDK, Inno Setup, or any native build tools.

Version 0.1.1 has been clean-room tested with Music Assistant 2.10.12 in a fresh Windows Sandbox, including validated Guest-account setup and Start-menu launching without the VBScript engine. MA Floater uses Music Assistant API commands that may change in later releases; check the issue tracker when a Music Assistant update causes a regression.

## Security and privacy

MA Floater refuses to run with an account whose Music Assistant role is broader than Guest. Use a dedicated account rather than a personal administrator account.

Music Assistant player filters determine what the Guest account may control:

- Leave the player filter empty if MA Floater should follow and control any active player, including players added later.
- Select specific players to limit control. Music Assistant may still return other queue names; MA Floater can display an active excluded queue, but control commands for it will be rejected.

The Guest password is encrypted with Windows Data Protection and can be decrypted only by the same Windows user. Credentials and settings are stored outside the project under `%LOCALAPPDATA%\MAFloater`; they are never written to the repository.

MA Floater connects to the configured Music Assistant server. Artwork may also be loaded from an absolute image URL supplied by Music Assistant.

Use an `https://` Music Assistant URL when the server is reachable over an untrusted network. An `http://` connection does not encrypt the Guest username, password, access token, playback data, or control commands in transit; use HTTP only on a network you trust. External artwork is downloaded through a separate client that does not receive the Music Assistant authorization token.

## Install and run the public PowerShell release

1. Download the release source archive from GitHub and extract it to a permanent folder. Moving or deleting that folder later breaks its optional Start menu and autostart entries.
2. Create a dedicated account in **Music Assistant → Settings → User Management** and assign it the **Guest** role. Set its player filter to the players MA Floater should control, or leave the filter empty to allow all players.
3. In File Explorer, open the extracted MA Floater folder, click the address bar, type `powershell`, and press Enter.
4. Permit scripts only in this PowerShell window:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
```

5. Configure the connection:


```powershell
.\Set-MusicAssistantConnection.ps1
```

Use the direct Music Assistant server URL, normally ending in port `8095`, rather than a Home Assistant dashboard URL. The script validates the server, login, and Guest role before saving anything. Its password field is masked; no characters appear while typing. If Ctrl+V does not work in Windows PowerShell 5.1, use right-click or Shift+Insert to paste.

6. Start MA Floater:

```powershell
.\Start-MAFloater.ps1
```

The launcher uses Microsoft's signed Windows PowerShell executable with a process-only execution-policy selection. It does not change the computer's persistent PowerShell policy.

The setup values can also be supplied as parameters:

```powershell
.\Set-MusicAssistantConnection.ps1 -ServerUrl 'http://music-assistant.local:8095' -Username 'ma-floater' -PreferredQueue 'Living Room'
```

Do not put a password in a command or script argument. The password is always requested through the masked prompt.

## Optional Windows integration

After MA Floater works from `Start-MAFloater.ps1`, the following optional commands add it to the current user's Start menu or start it after Windows sign-in:

```powershell
.\Install-StartMenuShortcut.ps1
.\Install-Autostart.ps1
```

The Start menu shortcut uses Windows PowerShell directly and does not depend on the deprecated Windows VBScript engine. The autostart task is limited to the current user and runs only after sign-in. Neither command requests administrator access.

## Contributor and developer workflow

### Current PowerShell implementation

The reviewable source is `src\MAFloater.ps1`. The runnable `bin\MAFloater.ps1` is committed for convenience and is regenerated by:

```powershell
.\Build.ps1
```

Run the dependency-free verification suite after changing the PowerShell source, packaging scripts, or public documentation:

```powershell
.\Test.ps1
```

The tests validate PowerShell syntax, source/build equality, publication branding, absence of known personal defaults and runtime credentials, setup validation, icon structure and frame sizes, artwork authorization isolation, the 40-pixel taskbar assignment, hidden Start menu launching without VBScript, safe autostart and shortcut removal, shared Windows app identity, and queue-selection behavior. They do not validate the native application.

### Native application foundation

The native Windows replacement is being developed alongside the PowerShell implementation, which remains the working reference. The native solution targets .NET 10 LTS and publishes a self-contained Windows x64 executable, so eventual users will not need to install .NET separately.

Developers with the .NET 10 SDK can build, check, and publish the native foundation with:

```powershell
.\Build-Native.ps1
```

`Build-Native.ps1` restores and builds the native solution, runs its foundation checks, and creates a self-contained Windows x64 publication. Generated files are written under `artifacts\win-x64` and are not tracked.

The native implementation currently provides the branded Windows shell, first-run setup, compatible current-user DPAPI credential storage, Guest-only authentication with token refresh, now-playing artwork, playback/shuffle/repeat controls, supported-player volume, compact-window behavior, and optional per-user autostart.

> [!WARNING]
> The native application and installer are currently unsigned development artifacts, not public releases. Windows 11 Smart App Control can block them. Do not disable Smart App Control as a workaround.

### Build the native Windows installer

The installer is intended for a standard per-user installation and does not request administrator access. It installs the native executable under `%LOCALAPPDATA%\Programs\MA Floater`, creates the Start menu entry, offers optional startup and desktop shortcuts, registers an uninstaller, and can launch MA Floater when setup finishes. Music Assistant credentials are never bundled; the native first-run window collects them after installation.

Install [Inno Setup 7](https://jrsoftware.org/isdl.php), then run:

```powershell
.\Build-Installer.ps1
```

The build first runs all native checks and creates the self-contained application, then writes the single downloadable installer to `artifacts\installer`. Use `-SkipNativeBuild` only when an unchanged, already-verified `artifacts\win-x64\MAFloater.exe` is present.

The installer preserves `%LOCALAPPDATA%\MAFloater` during upgrades and removal so a normal reinstall does not discard the encrypted credential or settings. The removal section below explains how to erase that data intentionally.

### Code signing and public releases

MA Floater does not currently publish a native Windows installer. A public native release requires trusted signatures on the application, installer, and generated uninstaller, followed by validation on Windows 11 with Smart App Control enabled. Checksums alone do not satisfy that requirement.

The project intends to apply for SignPath Foundation's open-source signing program after the repository is public and the release workflow is ready. SignPath has not accepted the project yet. See the [code signing policy](CODE_SIGNING_POLICY.md) for status, privacy, roles, and the release gate.

The `Windows build` GitHub Actions workflow builds and tests the native application and installer. Its downloadable workflow artifact is deliberately named `unsigned`, retained briefly, and must not be attached to a public GitHub Release.

Use the window's minimize button to send MA Floater to the taskbar. Double-click its tray icon, or choose **Open player**, to restore it. Choose **Exit** from the tray menu or close the window to stop it and revoke its current Music Assistant session.

Developers can run a successfully published native build directly:

```powershell
.\artifacts\win-x64\MAFloater.exe
```

Running the native executable does not replace the PowerShell launcher or its autostart task. The native tray menu provides **Start with Windows** for the native executable; do not enable both implementations at sign-in.

## Add the current PowerShell implementation to the Start menu

The Start menu shortcut is optional and is not installed automatically. To add **MA Floater** to the current Windows user's app list without requesting administrator access:

```powershell
.\Install-StartMenuShortcut.ps1
```

To remove only the shortcut created by this project folder:

```powershell
.\Remove-StartMenuShortcut.ps1
```

The shortcut uses the branded icon and launches the PowerShell implementation in a hidden window. It assigns the shortcut the same Windows app identity as the running player so the taskbar uses the branded application icon instead of a PowerShell fallback. Adding it to the Start menu does not enable autostart.

## Start the current PowerShell implementation automatically

Autostart is optional and is not installed automatically. To register the limited, per-user scheduled task **MA Floater** after Windows sign-in:

```powershell
.\Install-Autostart.ps1
```

To remove only that task:

```powershell
.\Remove-Autostart.ps1
```

The task does not run before login, store a Windows password, or request elevation. Duplicate launches in the same Windows session are prevented by a local mutex.

These scripts register only the PowerShell launcher. The native application manages its separate per-user startup entry from the tray menu, and the native installer offers the same option during setup.

## Removal

1. If the Start menu shortcut was installed, run `Remove-StartMenuShortcut.ps1`.
2. If the PowerShell autostart task was installed, run `Remove-Autostart.ps1`. For the native application, clear **Start with Windows** from its tray menu or uninstall it.
3. Exit every running MA Floater instance.
4. Delete the project folder and any separately copied native publication.
5. Delete `%LOCALAPPDATA%\MAFloater` to remove the shared encrypted credential and settings.
6. Delete or disable the dedicated Music Assistant Guest account if it is no longer needed.

## Project layout

- `src\MAFloater.ps1` — reviewable WPF application source
- `bin\MAFloater.ps1` — generated runnable copy
- `assets\ma-floater.ico` / `assets\ma-floater.png` — Windows icon and transparent source artwork
- `Set-MusicAssistantConnection.ps1` — per-user connection setup
- `Start-MAFloater.ps1` — hidden launcher
- `Start-MAFloater.vbs` — legacy launcher retained for safe removal of shortcuts created by version 0.1.0
- `Install-StartMenuShortcut.ps1` / `Remove-StartMenuShortcut.ps1` — optional per-user Start menu integration
- `Install-Autostart.ps1` / `Remove-Autostart.ps1` — optional scheduled-task management
- `Build-Installer.ps1` / `installer\MAFloater.iss` — native per-user single-EXE installer build
- `Build-Icon.ps1` — generates the multi-resolution Windows icon from the PNG artwork
- `Build.ps1` — syntax validation and staging
- `Test.ps1` — dependency-free repository checks
- `MAFloater.Native.slnx` — native .NET solution
- `src\MAFloater.App` — native WPF shell and Windows UI
- `src\MAFloater.Core` — native Music Assistant, settings, and credential logic
- `tests\MAFloater.FoundationChecks` — dependency-free native foundation checks
- `Build-Native.ps1` — native restore, build, checks, and self-contained publication
- `artifacts\win-x64` — generated native publication; not tracked

## License

MA Floater is released under the MIT License. See `LICENSE`.
