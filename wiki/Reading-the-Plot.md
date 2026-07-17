# Reading the Plot

## Modes

The plot toolbar has a segmented control with three modes: Explore, Pick
Peaks, and Integrate.

![Toolbar with the mode picker, Find Peaks, and Y Display controls](images/modes-toolbar.png)

Explore is for navigating: panning, zooming, resetting the view. A click
does nothing in Explore. Pick Peaks and Integrate turn a plain click into
a measurement instead, covered on the [Measuring](Measuring) page.

## Gestures

- **Double-click** resets the view to fit all visible spectra (Explore
  only).
- **Drag** does a rubber-band box zoom (Explore only).
- **Option-drag** pans (Explore only).
- **Scroll** zooms in or out about the pointer, in any mode, but only
  while the pointer is over the plot area itself. Scrolling over the
  axis labels or the margin around the plot does nothing.
- **Pinch** on a trackpad zooms about the point where the gesture starts,
  in any mode.
- **Hover** shows a crosshair that snaps to the nearest visible data
  point within about 24 points, with its exact coordinates printed
  alongside.

For the full gesture-by-mode table and every keyboard shortcut, see
[Tips and Shortcuts](Tips-and-Shortcuts).

## Axis conventions

Infrared spectra draw with the wavenumber x-axis running high to low,
the convention chemists expect. This only applies when every visible
trace uses wavenumber: overlay a mass spectrum (m/z) or an unconverted
wavelength spectrum alongside one, and the axis draws low to high
instead, since the reversed convention only makes sense when it applies
to everything on screen.

Mass spectra draw as vertical sticks rather than a continuous line, since
that's how the data is recorded.

## Y Display

The Y Display toggle (As Recorded, Transmittance, Absorbance) converts
infrared data recorded as transmittance or absorbance to the other, using
the standard -log10 relationship. It only does anything for spectra whose
y-axis is natively transmittance or absorbance. Choose Transmittance or
Absorbance for a mass spectrum, or any other non-infrared data, and
nothing changes: the y-axis label and the plotted values stay exactly as
recorded, since converting them wouldn't mean anything.

## Wavelength spectra sharing a plot with wavenumber

If a spectrum recorded in micrometers is shown alongside a wavenumber
spectrum, Spectra Swift converts it to wavenumber for display so the two
share one axis. Its entry in the legend gets a "(from µm)" tag so you
know it's not in its original units on screen. Shown by itself, it draws
in micrometers, unconverted.

## Mixed-unit overlays

Overlaying spectra with different y-units (transmittance next to relative
intensity, for example) normalizes each trace to a 0-1 scale so they fit
on one axis together. When this happens, the y-axis label reads
"Normalized" instead of a real unit, the x-axis reversal rule no longer
applies (since a mixed overlay rarely has every trace on wavenumber), and
any peak marks or labels on the affected spectra stop drawing until you
view them on their own again. What this means for taking new
measurements is covered on the [Measuring](Measuring) page.

## Auto Y

The Auto Y toggle refits the y-axis to whatever data falls within the
current x range. It only has an effect once you've zoomed or panned to a
manual view; on the default auto-fit view there's nothing for it to
refit against.

## Reset View

The Reset View button, or Command-0, clears any manual zoom or pan and
returns to the default view that fits every visible spectrum.

Next: [Measuring](Measuring)
