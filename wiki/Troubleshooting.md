# Troubleshooting

## The app won't open ("Spectra" Not Opened, or similar)

Spectra Swift isn't signed with an Apple Developer certificate (that
costs $99 a year, and this is a free, open-source app), so macOS blocks
it the first time you try to run it. This is normal for open-source
Mac apps distributed outside the App Store, and it only happens once.

**macOS Sequoia (15.0) and later**

1. Double-click Spectra.app. You'll see "Spectra" Not Opened.
2. Click Done (not "Move to Trash").
3. Open System Settings, then Privacy & Security.
4. Scroll to Security and find "Spectra was blocked to protect your Mac."
5. Click Open Anyway, then confirm with Open Anyway again.

**macOS Sonoma (14.x)**

1. Right-click Spectra.app and choose Open.
2. Click Open in the dialog that appears.

**Terminal alternative (any version)**

```sh
xattr -cr /Applications/Spectra.app
```

After the first successful launch, Gatekeeper doesn't ask again, and
auto-updates install and relaunch the app in place with no dance at all.

## Double-clicking an OPUS file (.0, .1, ...) doesn't open Spectra Swift

OPUS files use bare numeric extensions, and another app on your Mac may
already claim them. If double-clicking a file opens something else, or
nothing, right-click it, choose Open With, and pick Spectra Swift. Finder
remembers your choice after that.

This only affects Finder double-click. File > Open (Command-O) and
dragging the file onto the Spectra Swift window both work regardless of
which app owns the extension.

## The sidebar looks blank after dragging its divider

Nothing is lost. Toggle the sidebar off and back on with Control-Command-S
(⌃⌘S), or View > Hide Sidebar followed by View > Show Sidebar, and the
list reappears. ([issue #1](https://github.com/proverbiallemon/SpectraSwift/issues/1))

## The sidebar is hidden when the app starts

Occasionally the sidebar doesn't show itself after a relaunch. The same
shortcut, Control-Command-S (⌃⌘S), brings it back.
([issue #2](https://github.com/proverbiallemon/SpectraSwift/issues/2))

## A file I opened from Finder didn't load

If you double-click a file while Spectra Swift is closed, it can launch
without the file loading. Once the app is up, open the file again (drag
it in, or use File > Open) and it loads normally.
([issue #3](https://github.com/proverbiallemon/SpectraSwift/issues/3))

## Alerts when reopening a session

When you open a `.spectrasession` file, Spectra Swift checks each spectrum
it references. If anything's changed, one alert lists what happened, file
by file:

- A bare file path means that file couldn't be found at all. The rest of
  the session still loads.
- A path noted as changed since the session was saved means the file is
  still there, but its content is different from when you saved. The
  spectrum loads with the current data, but any peaks or integration
  regions you'd measured against the old version are dropped rather than
  shown in the wrong place on the new curve.

## "Check for Updates" fails or does nothing

Spectra Swift checks for updates automatically once a day, and you can
check any time with Spectra Swift ▸ Check for Updates (the menu item
grays out while a check is already running). If a check can't complete,
for a dropped connection or an unreachable update server, an alert
explains why. Try again once you're back online, or download the latest
release by hand from the
[releases page](https://github.com/proverbiallemon/SpectraSwift/releases/latest).
If you're already on the newest version, the same menu item just tells
you so.
