# Format Support

Spectra Swift reads two kinds of files: JCAMP-DX, the text format most
spectroscopy software (including the NIST WebBook) exports, and Bruker
OPUS, the binary format written directly by Bruker spectrometers.

## JCAMP-DX (.jdx, .dx, .jcm)

The parser handles the JCAMP-DX 4.24 and 5.00 features found in
real-world files, not just the textbook examples:

- `(X++(Y..Y))` compressed data blocks, with the full ASDF compression
  set in circulation: PAC, SQZ, DIF, and DUP.
- Peak tables, NTUPLES data tables, and compound files holding more than
  one spectrum.
- Both line-abscissa conventions used in practice: the first value on a
  line naming the next new point, and the DIF-style convention where it
  names the last point of the previous line (NIST's own quantitative IR
  database uses the DIF-style convention, with rounded values, even
  though its data is otherwise plain AFFN).

Malformed files degrade gracefully rather than failing outright.
Recoverable oddities, a header field that doesn't parse cleanly, an
unexpected but survivable data quirk, load anyway with a warning
attached to the spectrum (visible as the badge next to its name in the
sidebar, and listed in full in the inspector). Only a genuinely
unreadable file, one with no data Spectra Swift can extract at all,
produces an error, and that error names the specific reason rather than
a generic failure message. If one kind of warning would otherwise repeat
dozens of times over a single large data block, the app shows the first
few occurrences and a summary count instead of flooding the warning
list.

## Bruker OPUS (.0, .1, .2, ...)

OPUS files are identified by their contents, not their extension (the
same bare-numeric-extension scheme Bruker uses can collide with other
apps; see [Troubleshooting](Troubleshooting) if double-clicking one opens
the wrong app), so a renamed or oddly-numbered file still opens
correctly.

**What imports**: the processed result spectrum (absorbance or
transmittance, whichever the file stores), its x-axis grid, and every
instrument, sample, and acquisition parameter, all available in the
inspector.

**What's skipped**: interferograms and raw single-channel data. These
aren't a finished spectrum, so Spectra Swift doesn't try to guess one
from them. A file that holds only that kind of data says so plainly
instead of loading something meaningless.

**Multi-spectrum files**: an OPUS file can hold more than one result
(a sample run and a background run together, for example). Each becomes
its own entry in the sidebar; if two share a title, the later ones get
" (2)", " (3)," and so on appended so they stay distinguishable.

**Y-unit detection**: the file's Acquisition parameters carry a field
(PLF, short for "Result Spectrum") that names what kind of result was
stored, absorbance or transmittance. Spectra Swift reads that field to
label the y-axis correctly and to decide whether the Y Display toggle
should do anything. If PLF names something Spectra Swift doesn't
recognize (reflectance or Kubelka-Munk output, for instance), the
spectrum still loads under that label, with a warning that axis
conversions may not mean anything for it. If PLF is missing entirely,
Spectra Swift assumes the result is absorbance and says so with a
warning, so an assumption never looks the same as a fact read from the
file.

A handful of narrower warnings can also appear on unusual OPUS files, a
missing x-axis unit, or a data block whose length doesn't match its
stated point count. Each one names the specific mismatch rather than
failing silently or guessing.

## Malformed-file philosophy

Across both formats, the rule is the same: never crash on a bad file,
and never show data that doesn't match what's actually in the file.
Anything recoverable becomes a warning attached to the spectrum. Anything
truly unreadable throws an error that names the problem. You should
never see a spectrum that quietly plots the wrong numbers.
