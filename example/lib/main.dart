import 'dart:async';

import 'package:ble_scanner/ble_scanner.dart';
import 'package:flutter/material.dart';

void main() => runApp(const ExampleApp());

/// Minimal example: lists every advertiser with its latest RSSI.
class ExampleApp extends StatefulWidget {
  /// Creates the example app.
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  final _scanner = BleScanner();
  final _latest = <String, ScanSample>{};
  StreamSubscription<List<ScanSample>>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = _scanner.samples.listen((batch) {
      setState(() {
        for (final s in batch) {
          _latest[s.peripheralKey] = s;
        }
      });
    });
    unawaited(_scanner.start());
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_scanner.stop().then((_) => _scanner.dispose()));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _latest.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('ble_scanner — ${rows.length} devices')),
        body: ListView.builder(
          itemCount: rows.length,
          itemBuilder: (_, i) => ListTile(
            title: Text(rows[i].localName ?? rows[i].peripheralKey),
            subtitle: Text('company: ${rows[i].companyId ?? '-'}'),
            trailing: Text('${rows[i].rssi} dBm'),
          ),
        ),
      ),
    );
  }
}
