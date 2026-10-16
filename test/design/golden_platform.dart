import 'dart:io';

/// Whether the goldens in this folder are compared here.
///
/// They are recorded on macOS. The Linux runner rasterises anti-aliased
/// edges, gradients and blurs differently, and the same frame comes out 0.7
/// to 3.4 percent of pixels apart, so a comparison there fails on every run
/// without anything having changed. Run them on a Mac, and record them there:
/// `fvm flutter test --update-goldens test/design`.
final bool skipGoldensOffMac = !Platform.isMacOS;
