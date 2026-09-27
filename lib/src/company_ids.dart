/// Bluetooth SIG company identifiers that matter for finding phones.
abstract final class CompanyIds {
  /// Apple Inc. — iPhone Continuity / Nearby and Find My advertisements.
  static const int apple = 0x004C;

  /// Microsoft — Windows / Swift Pair beacons (usually surface devices).
  static const int microsoft = 0x0006;

  /// Samsung Electronics — SmartThings Find, Galaxy devices.
  static const int samsung = 0x0075;

  /// Google — Fast Pair / Find Hub related advertisements.
  static const int google = 0x00E0;

  /// First payload byte of an Apple Find My (offline finding) advertisement.
  static const int appleFindMyType = 0x12;

  /// First payload byte of an Apple Nearby Info advertisement.
  static const int appleNearbyInfoType = 0x10;
}
