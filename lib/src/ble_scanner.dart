import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ble_scanner/src/messages.g.dart';

/// Error reported by the native scanner or advertiser (for example Android failure codes).
final class BleScanError implements Exception {
  /// Creates an error with the platform [code] and a human readable [message].
  const BleScanError(this.code, this.message);

  /// Platform error code (Android `ScanCallback` codes, `-1` for permission problems).
  final int code;

  /// Description from the platform.
  final String message;

  @override
  String toString() => 'BleScanError($code, $message)';
}

/// Entry point of the plugin. Create one instance per app and [dispose] it when done.
class BleScanner implements BleScannerFlutterApi {
  /// Creates a scanner. [hostApi] can be replaced in tests.
  BleScanner({BleScannerHostApi? hostApi})
    : _host = hostApi ?? BleScannerHostApi() {
    BleScannerFlutterApi.setUp(this);
  }

  final BleScannerHostApi _host;
  final _samples = StreamController<List<ScanSample>>.broadcast();
  final _adapter = StreamController<AdapterState>.broadcast();
  final _errors = StreamController<BleScanError>.broadcast();
  final _advertiseStarted = StreamController<void>.broadcast();
  final _advertiseErrors = StreamController<BleScanError>.broadcast();

  /// Most service data a legacy scan response holds next to a 128-bit UUID (31 − 2 − 16 − 2).
  static const maxServiceDataBytes = 11;

  /// Longest local name accepted (iOS puts it in the scan response with room to spare).
  static const maxLocalNameBytes = 20;

  /// Batches of received advertisements, in arrival order.
  Stream<List<ScanSample>> get samples => _samples.stream;

  /// Adapter state changes (Bluetooth turned on/off, permission changes on iOS).
  Stream<AdapterState> get adapterStates => _adapter.stream;

  /// Scan failures reported asynchronously by the platform.
  Stream<BleScanError> get errors => _errors.stream;

  /// Current adapter state. On iOS the first call may show the Bluetooth permission prompt.
  Future<AdapterState> adapterState() => _host.adapterState();

  /// What this device supports.
  Future<ScannerCapabilities> capabilities() => _host.capabilities();

  /// Starts (or restarts) scanning. Defaults suit RSSI measurements.
  Future<void> start({
    ScanMode mode = ScanMode.lowLatency,
    List<String> serviceUuids = const [],
    Duration batchInterval = const Duration(milliseconds: 250),
  }) => _host.startScan(
    ScanConfig(
      mode: mode,
      serviceUuids: serviceUuids,
      batchIntervalMs: batchInterval.inMilliseconds,
    ),
  );

  /// Stops scanning and flushes buffered samples.
  Future<void> stop() => _host.stopScan();

  /// Advertising confirmed by the platform (after every [startAdvertising]).
  Stream<void> get advertiseStarted => _advertiseStarted.stream;

  /// Advertising failures reported asynchronously (Android `AdvertiseCallback` codes, iOS errors).
  Stream<BleScanError> get advertiseErrors => _advertiseErrors.stream;

  /// Starts advertising [serviceUuid] — or replaces the payload when already advertising. Android
  /// sends [serviceData] (not [localName]); iOS sends [localName] (not [serviceData]). Throws
  /// [ArgumentError] when the payload does not fit a legacy packet.
  Future<void> startAdvertising({
    required String serviceUuid,
    String? localName,
    Uint8List? serviceData,
  }) {
    if ((serviceData?.length ?? 0) > maxServiceDataBytes) {
      throw ArgumentError.value(
        serviceData!.length,
        'serviceData',
        'at most $maxServiceDataBytes bytes',
      );
    }
    if (localName != null &&
        utf8.encode(localName).length > maxLocalNameBytes) {
      throw ArgumentError.value(
        localName,
        'localName',
        'at most $maxLocalNameBytes bytes',
      );
    }
    return _host.startAdvertising(
      AdvertiseConfig(
        serviceUuid: serviceUuid,
        localName: localName,
        serviceData: serviceData,
      ),
    );
  }

  /// Stops advertising.
  Future<void> stopAdvertising() => _host.stopAdvertising();

  /// Releases the Dart side. The instance cannot be used afterwards.
  Future<void> dispose() async {
    BleScannerFlutterApi.setUp(null);
    await Future.wait([
      _samples.close(),
      _adapter.close(),
      _errors.close(),
      _advertiseStarted.close(),
      _advertiseErrors.close(),
    ]);
  }

  @override
  void onSamples(List<ScanSample> samples) => _samples.add(samples);

  @override
  void onAdapterStateChanged(AdapterState state) => _adapter.add(state);

  @override
  void onScanError(int code, String message) =>
      _errors.add(BleScanError(code, message));

  @override
  void onAdvertiseStarted() => _advertiseStarted.add(null);

  @override
  void onAdvertiseError(int code, String message) =>
      _advertiseErrors.add(BleScanError(code, message));
}
