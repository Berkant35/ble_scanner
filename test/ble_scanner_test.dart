import 'package:ble_scanner/ble_scanner.dart';
import 'package:ble_scanner/src/messages.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockHost extends Mock implements BleScannerHostApi {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockHost host;
  late BleScanner scanner;

  setUpAll(
    () => registerFallbackValue(
      ScanConfig(
        mode: ScanMode.lowLatency,
        serviceUuids: [],
        batchIntervalMs: 0,
      ),
    ),
  );

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
}
