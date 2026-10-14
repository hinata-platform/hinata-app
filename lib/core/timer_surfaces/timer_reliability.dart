/// Whether this build carries the reliability mode's foreground service
/// (Android, HIN-104).
///
/// `--dart-define=HINATA_FGS=off` builds a package without it: Gradle reads
/// the same define and takes the service and its permissions out of the
/// manifest, and the app then offers no switch for it. Kept for the case that
/// Google Play turns the service's declaration down.
const bool kTimerReliabilityService =
    String.fromEnvironment('HINATA_FGS') != 'off';
