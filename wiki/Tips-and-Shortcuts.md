# Tips and Shortcuts

A quick-reference page: every keyboard shortcut, what each gesture does in
each mode, and a handful of behaviors that aren't obvious from using the
app.

## Keyboard shortcuts

| Keys | Action |
|---|---|
| ⌘O | Open a file |
| ⌘S | Save Session (grayed out until at least one spectrum is loaded) |
| ⇧⌘O | Open Session |
| ⇧⌘C | Copy Plot (PNG to the clipboard) |
| ⌘0 | Reset View |
| ⇧⌘L | Toggle peak labels |
| ⇧⌘T | Show or hide the results table |
| ⌃⌘S | Show or hide the sidebar |
| Delete | Delete the selected row(s) in the results table |
| Return | Confirm the open sheet (Smooth, Subtract) |
| Escape | Cancel the open sheet (Smooth, Subtract) |

A few things have no keyboard shortcut and need a click: Find Peaks, the
mode picker, the Y Display picker, and Check for Updates.

## Gestures by mode

The plot has three modes, set from the toolbar's segmented control:
Explore, Pick Peaks, and Integrate. What a click does depends on which
one is active. A dash means the gesture has no effect in that mode.

| Gesture | Explore | Pick Peaks | Integrate |
|---|---|---|---|
| Click | Nothing | Snaps to the nearest peak apex and adds a mark | First click sets the start of the region (a dashed guide appears); second click closes it and adds the region |
| Double-click | Resets the view | - | - |
| Drag | Rubber-band box zoom | - | - |
| Option-drag | Pan | - | - |
| Scroll | Zoom about the cursor | Zoom about the cursor | Zoom about the cursor |
| Pinch (trackpad) | Zoom | Zoom | Zoom |
| Hover | Crosshair readout | Crosshair readout | Crosshair readout |

A couple of notes on the gestures that work in every mode: scrolling only
zooms while the cursor is over the plot area itself; scroll over the axis
labels or the margins around the plot does nothing. Pinching on a
trackpad zooms about the point where the gesture starts. Hovering shows a
crosshair that snaps to the nearest visible data point, with its
coordinates printed alongside.

## Things you might not know

- Emptying a peak's label in the results table reverts it to the default
  name (the x value), it doesn't leave the row blank.
- Clicking the same spot twice in Pick Peaks mode, for the same spectrum,
  x position, and display mode, is silently ignored. You won't get a
  stack of duplicate marks.
- If two peak labels would overlap on the plot, the later one is skipped
  rather than drawn on top of or stacked above the first.
- The inspector's filter box matches parameter values, not just their
  names. Searching "CAS" finds a parameter named `CAS registry no.` and
  one named something else whose value happens to contain "CAS."
- Every parameter value in the inspector is plain, selectable text: click
  and drag to copy a number or string straight out of the panel.
- Escape does not cancel a click you've already placed in Integrate mode.
  If you start a region and change your mind, switch to a different mode
  (Explore or Pick Peaks) to clear the pending click, or just place the
  second click to finish the region and delete it afterward from the
  results table.

## About the "shift-click" rumor

Integrate mode does not use Shift-click, or any modifier key at all. It's
two plain clicks: the first marks the start of the region, the second
closes it.
