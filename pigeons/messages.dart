// Pigeon contract between Dart and the native BLE scanners.
// Regenerate with: fvm dart run pigeon --input pigeons/messages.dart
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartPackageName: 'ble_scanner',
    kotlinOut:
        'android/src/main/kotlin/org/beneathsos/ble_scanner/Messages.g.kt',
    kotlinOptions: KotlinOptions(package: 'org.beneathsos.ble_scanner'),
    swiftOut: 'ios/ble_scanner/Sources/ble_scanner/Messages.g.swift',
  ),
)
/// How aggressively the radio scans. `lowLatency` is required for measurements.
enum ScanMode { lowPower, balanced, lowLatency }

/// Bluetooth adapter state as reported by the platform.
enum AdapterState { unknown, unsupported, unauthorized, poweredOff, poweredOn }

/// Scan request.
class ScanConfig {
  ScanConfig({
    required this.mode,
    required this.serviceUuids,
    required this.batchIntervalMs,
  });

  ScanMode mode;

  /// Optional filter. Empty = report every advertisement.
  List<String> serviceUuids;

  /// Samples are buffered natively and delivered in batches at this interval.
  int batchIntervalMs;
}

/// One received advertisement. RSSI is always tied to a received packet.
class ScanSample {
  ScanSample({
    required this.peripheralKey,
    required this.rssi,
    required this.serviceUuids,
    required this.monotonicNanos,
    required this.wallClockMillis,
    this.txPower,
    this.companyId,
    this.manufacturerData,
    this.localName,
    this.connectable,
  });

  /// Android: Bluetooth address (may be random/rotating). iOS: CBPeripheral.identifier.
  String peripheralKey;
  int rssi;
  int? txPower;

  /// Bluetooth SIG company identifier from manufacturer data (0x004C = Apple).
  int? companyId;

  /// Manufacturer data payload without the 2-byte company identifier.
  Uint8List? manufacturerData;
  List<String> serviceUuids;
  String? localName;
  bool? connectable;

  /// Service data by service UUID (Android: lower case, iOS: upper case).
  Map<String, Uint8List>? serviceData;

  /// Monotonic receive time (Android elapsedRealtimeNanos, iOS CLOCK_UPTIME_RAW).
  int monotonicNanos;
  int wallClockMillis;
}

/// What this device/OS can do — reported, never assumed.
class ScannerCapabilities {
  ScannerCapabilities({
    required this.platform,
    required this.codedPhySupported,
    required this.extendedAdvertisingSupported,
    required this.advertisingSupported,
  });

  String platform;
  bool codedPhySupported;
  bool extendedAdvertisingSupported;

  /// Whether this phone can advertise (Android: false while Bluetooth is off).
  bool advertisingSupported;
}

/// What this phone advertises (a legacy packet: 31 bytes of advert + 31 of scan response).
class AdvertiseConfig {
  AdvertiseConfig({
    required this.serviceUuid,
    this.localName,
    this.serviceData,
  });

  /// 128-bit service UUID, in the advert.
  String serviceUuid;

  /// iOS only (Android can only advertise the phone's own name).
  String? localName;

  /// Android only (iOS apps cannot advertise service data), under [serviceUuid].
  Uint8List? serviceData;
}

@HostApi()
abstract class BleScannerHostApi {
  AdapterState adapterState();
  ScannerCapabilities capabilities();
  void startScan(ScanConfig config);
  void stopScan();
  void startAdvertising(AdvertiseConfig config);
  void stopAdvertising();
}

@FlutterApi()
abstract class BleScannerFlutterApi {
  void onSamples(List<ScanSample> samples);
  void onAdapterStateChanged(AdapterState state);
  void onScanError(int code, String message);
  void onAdvertiseStarted();
  void onAdvertiseError(int code, String message);
}
