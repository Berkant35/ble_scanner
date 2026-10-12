import 'dart:typed_data';

import 'package:ble_scanner/ble_scanner.dart';
import 'package:ble_scanner/src/messages.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockHost extends Mock implements BleScannerHostApi {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockHost host;
  late BleScanner scanner;

  setUpAll(() {
    registerFallbackValue(
      ScanConfig(
        mode: ScanMode.lowLatency,
        serviceUuids: [],
        batchIntervalMs: 0,
      ),
    );
    registerFallbackValue(AdvertiseConfig(serviceUuid: ''));
  });

  setUp(() {
    host = _MockHost();
    scanner = BleScanner(hostApi: host);
  });

  tearDown(() => scanner.dispose());

  test('start sends low-latency config with batch interval in ms', () async {
    when(() => host.startScan(any())).thenAnswer((_) async {});

    await scanner.start(batchInterval: const Duration(milliseconds: 300));

    final config =
        verify(() => host.startScan(captureAny())).captured.single
            as ScanConfig;
    expect(config.mode, ScanMode.lowLatency);
    expect(config.batchIntervalMs, 300);
    expect(config.serviceUuids, isEmpty);
  });

  test('native callbacks are forwarded to streams', () async {
    final sample = ScanSample(
      peripheralKey: 'AA:BB',
      rssi: -71,
      serviceUuids: const [],
      monotonicNanos: 1,
      wallClockMillis: 2,
      companyId: CompanyIds.apple,
    );

    final samples = expectLater(scanner.samples, emits([sample]));
    final states = expectLater(
      scanner.adapterStates,
      emits(AdapterState.poweredOff),
    );
    final errors = expectLater(
      scanner.errors,
      emits(isA<BleScanError>().having((e) => e.code, 'code', 2)),
    );

    scanner
      ..onSamples([sample])
      ..onAdapterStateChanged(AdapterState.poweredOff)
      ..onScanError(2, 'failed');

    await Future.wait([samples, states, errors]);
  });

  const uuid = '06ad86ef-1e8c-47b4-9c65-c526d5e31581';

  test('advertising sends the service UUID, name and data', () async {
    when(() => host.startAdvertising(any())).thenAnswer((_) async {});

    await scanner.startAdvertising(
      serviceUuid: uuid,
      localName: 'SOS-1A2B',
      serviceData: Uint8List.fromList([1, 0x1a, 0x2b, 80, 3]),
    );

    final config =
        verify(() => host.startAdvertising(captureAny())).captured.single
            as AdvertiseConfig;
    expect(config.serviceUuid, uuid);
    expect(config.localName, 'SOS-1A2B');
    expect(config.serviceData, [1, 0x1a, 0x2b, 80, 3]);
  });

  test('a payload that does not fit a legacy packet is refused', () {
    expect(
      () => scanner.startAdvertising(
        serviceUuid: uuid,
        serviceData: Uint8List(12),
      ),
      throwsArgumentError,
    );
    expect(
      () => scanner.startAdvertising(serviceUuid: uuid, localName: 'x' * 21),
      throwsArgumentError,
    );
    verifyNever(() => host.startAdvertising(any()));
  });

  test('advertising callbacks are forwarded to streams', () async {
    when(() => host.stopAdvertising()).thenAnswer((_) async {});
    final started = expectLater(scanner.advertiseStarted, emits(null));
    final errors = expectLater(
      scanner.advertiseErrors,
      emits(isA<BleScanError>().having((e) => e.code, 'code', 3)),
    );

    scanner
      ..onAdvertiseStarted()
      ..onAdvertiseError(3, 'too many advertisers');
    await scanner.stopAdvertising();

    await Future.wait([started, errors]);
    verify(() => host.stopAdvertising()).called(1);
  });
}
