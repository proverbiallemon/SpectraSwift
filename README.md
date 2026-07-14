# Spectra Swift

A native macOS viewer for JCAMP-DX spectroscopy files — the format NIST
WebBook serves for IR, mass, and UV-Vis spectra.

Drop a `.jdx` or `.dx` file onto the window (or double-click it in Finder)
and you get an interactive plot that follows the conventions chemists
expect: IR spectra draw with the wavenumber axis running high to low,
mass spectra draw as stick plots, and a toolbar toggle converts IR data
between transmittance and absorbance on the fly.

## Installing

Grab `SpectraSwift-<version>.zip` from the
[latest release](https://github.com/proverbiallemon/SpectraSwift/releases/latest),
unzip it, and drag `Spectra.app` into `/Applications`.

**First launch:** the app isn't notarized with Apple (no paid developer
account behind it), so macOS will warn you. Right-click the app, choose
**Open**, then click **Open** in the dialog.  If you're on newer versions 
of Mac OS you will have to go to system settings after you try to open it, 
and click open anyway to launch — you only have to do this
once. If you prefer the terminal:

```sh
xattr -cr /Applications/Spectra.app
```

Building from source (below) avoids the warning entirely.

## Known issues

- Dragging the sidebar divider to the right can leave the spectra list
  looking blank. Nothing is lost — toggle the sidebar closed and open
  again (View ▸ Hide/Show Sidebar, ⌃⌘S) and it comes back.
- The sidebar occasionally starts hidden after a restart; the same
  shortcut brings it in.
- Measuring is deliberately disabled while a spectrum is displayed
  unit-converted or on a mixed-unit normalized overlay — show the
  spectrum by itself to measure it in its native units.

## Features

- **Overlay and compare** — load any number of spectra; checkboxes in the
  sidebar control which ones draw together. Spectra with different y-units
  overlay on a normalized axis.
- **Navigate** — rubber-band box zoom, scroll-wheel and pinch zoom about
  the cursor, Option-drag to pan, double-click to fit.
- **Read values** — a crosshair snaps to the nearest data point on any
  visible trace and shows its exact coordinates.
- **Inspect metadata** — every parameter recorded in the file, in a
  searchable panel, along with any warnings from parsing.
- **Export** — CSV or JCAMP-DX for the data; PNG or vector PDF for the
  plot; ⇧⌘C copies the plot straight to the clipboard.

## Format support

The parser handles the JCAMP-DX 4.24/5.00 features found in real-world
files: `(X++(Y..Y))` data with the full ASDF compression set (PAC, SQZ,
DIF, DUP), peak tables, NTUPLES data tables, compound multi-spectrum
files, and both line-abscissa conventions in circulation (including the
one NIST's quantitative IR database uses). Malformed files degrade
gracefully: recoverable oddities load with a warning badge instead of
failing, and unreadable files produce a clear error naming the reason.

Parsing lives in `SpectraKit`, a UI-free Swift package, and is tested
against fixtures downloaded from NIST as well as synthetic edge cases.

## Building

Requires macOS 14+, Xcode 16 or later, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
xcodebuild -project Spectra.xcodeproj -scheme Spectra -configuration Debug build
```

Or open the generated `Spectra.xcodeproj` in Xcode and run.

To run the library tests:

```sh
swift test
```

## Layout

```
Sources/SpectraKit/   file parsing and the spectrum model (no UI)
Tests/                Swift Testing suite + NIST fixture files
App/                  the SwiftUI app
project.yml           XcodeGen project definition
```

## Planned

Peak picking and automatic peak detection, baseline-referenced peak
heights, area integration between two points with an exportable results
table, difference spectra, session saving, and x-unit conversion so
wavelength and wavenumber data overlay meaningfully.
