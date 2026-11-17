# Philosopher's Codex — Downloads

Public downloads for **Philosopher's Codex**, a World of Warcraft: Forever (Interface 16001) leveling and gearing tracker crafted for the **Alchemists** guild.

The source code lives in a private repository. This repository is only for install files, release zips, and `latest.json` so guildmates can update without needing collaborator access.

## Install (first time)

1. Open the [latest release](https://github.com/uriahgibsonai/PhilosophersCodex-Releases/releases/latest) and download `PhilosophersCodex.zip`.
2. Extract it so you have:

   `World of Warcraft\_forever_\Interface\AddOns\PhilosophersCodex\`

   The folder name has no apostrophe. The zip also contains `Update-PhilosophersCodex.bat` — you can leave that in `AddOns` or anywhere convenient.
3. Restart WoW Forever or type `/reload`.
4. Type `/codex` (or `/pc`).

Your character progress is stored in `PhilosophersCodexDB` and is not overwritten by an update.

## Update

In game, if a guildmate is already on a newer copy, Philosopher's Codex shows **Update available: vX** and an Update button. That button cannot download the file (WoW addons are not allowed to go online). It gives you this page's address to copy.

Easier: double-click `Update-PhilosophersCodex.bat` (or run the `.ps1` in PowerShell). The updater:

- Reads [`latest.json`](https://raw.githubusercontent.com/uriahgibsonai/PhilosophersCodex-Releases/main/latest.json)
- Compares it to the `## Version` in your installed `PhilosophersCodex.toc`
- Downloads the release zip
- Renames your current folder to `PhilosophersCodex.bak-YYYYMMDD-HHMMSS`
- Extracts the new copy into `Interface\AddOns`
- Never touches any other addon, WTF file, or game folder

It looks for common install paths, including `C:\Program Files (x86)\World of Warcraft\_forever_`. If your game is somewhere else, pass it in:

```powershell
.\Update-PhilosophersCodex.ps1 -WowRoot "D:\World of Warcraft\_forever_"
```

To copy your in-game issue log out so it can be shared:

```powershell
.\Update-PhilosophersCodex.ps1 -CopyReports
```

That copies only `WTF\Account\*\SavedVariables\PhilosophersCodex*.lua` into a `reports` folder next to the script and prints a short summary.

## In-game commands

- `/codex update` — show the download link
- `/codex issues` — errors and missing-data log, with Copy and Clear
- `/codex debug on|off` — also print caught errors in chat
