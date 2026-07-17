# Getting Started

## Download

1. Download `SpectraSwift-<version>.zip` from the
   [latest release](https://github.com/proverbiallemon/SpectraSwift/releases/latest).
2. Unzip it and drag `Spectra.app` into your Applications folder.

## First launch (Gatekeeper)

Spectra Swift isn't signed with an Apple Developer certificate, so macOS
blocks it the first time you try to open it. This only happens once.

**macOS Sequoia (15.0) and later**

1. Double-click `Spectra.app`. You'll see "Spectra" Not Opened.
2. Click Done (not "Move to Trash").
3. Open System Settings, then Privacy & Security.
4. Scroll to Security and find "Spectra was blocked to protect your Mac."
5. Click Open Anyway, then confirm with Open Anyway again.

**macOS Sonoma (14.x)**

1. Right-click `Spectra.app` and choose Open.
2. Click Open in the dialog that appears.

If the app still won't open, or you'd rather do it from Terminal, see
[Troubleshooting](Troubleshooting) for the full walkthrough.

## Auto-updates

After the first launch, Spectra Swift checks for updates automatically
once a day. You can also check any time with Spectra Swift ▸ Check for
Updates (the menu item grays out while a check is already running).
Updates install and relaunch the app in place, with no Gatekeeper dance
the second time around.

## Opening your first file

Drop a `.jdx`, `.dx`, or OPUS file (like `.0`) onto the window, use
File > Open (Command-O), or double-click the file in Finder. See
[Opening Files](Opening-Files) for the full list of formats and a quirk
with OPUS's numeric extensions.

Next: [Opening Files](Opening-Files)
