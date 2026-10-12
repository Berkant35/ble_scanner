import CoreBluetooth
import Flutter
import Foundation

/// Raw BLE scanner for iOS. Foreground scanning with duplicates allowed so every received
/// advertisement produces an RSSI sample. Samples are buffered and delivered in batches. Also
/// advertises one service UUID and a local name (victim mode).
public class BleScannerPlugin: NSObject, FlutterPlugin, BleScannerHostApi, CBCentralManagerDelegate,
  CBPeripheralManagerDelegate
{
  private let flutterApi: BleScannerFlutterApi
  private var central: CBCentralManager?
  private var pendingConfig: ScanConfig?
  private var buffer: [ScanSample] = []
  private var flushTimer: Timer?
  private var peripheral: CBPeripheralManager?
  private var pendingAdvert: AdvertiseConfig?

  init(messenger: FlutterBinaryMessenger) {
    flutterApi = BleScannerFlutterApi(binaryMessenger: messenger)
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = BleScannerPlugin(messenger: registrar.messenger())
    BleScannerHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
  }

  /// Created lazily: instantiating CBCentralManager triggers the Bluetooth permission prompt.
  private func manager() -> CBCentralManager {
    if let central { return central }
    let created = CBCentralManager(
      delegate: self, queue: nil,
      options: [CBCentralManagerOptionShowPowerAlertKey: false])
    central = created
    return created
  }

  /// Created lazily, like the central manager (same Bluetooth permission).
  private func peripheralManager() -> CBPeripheralManager {
    if let peripheral { return peripheral }
    let created = CBPeripheralManager(
      delegate: self, queue: nil,
      options: [CBPeripheralManagerOptionShowPowerAlertKey: false])
    peripheral = created
    return created
  }

  // MARK: BleScannerHostApi

  func adapterState() throws -> AdapterState {
    Self.map(manager().state)
  }

  func capabilities() throws -> ScannerCapabilities {
    // CoreBluetooth exposes neither PHY selection nor extended advertising to apps.
    ScannerCapabilities(
      platform: "ios", codedPhySupported: false, extendedAdvertisingSupported: false,
      advertisingSupported: true)
  }

  func startScan(config: ScanConfig) throws {
    stopScan()
    let central = manager()
    guard central.state == .poweredOn else {
      pendingConfig = config  // started from centralManagerDidUpdateState
      return
    }
    begin(config, on: central)
  }

  func stopScan() {
    pendingConfig = nil
    central?.stopScan()
    flushTimer?.invalidate()
    flushTimer = nil
    flush()
  }

  /// iOS apps can send only service UUIDs and a local name; service data is ignored. A new call
  /// replaces the payload.
  func startAdvertising(config: AdvertiseConfig) throws {
    let manager = peripheralManager()
    manager.stopAdvertising()
    guard manager.state == .poweredOn else {
      pendingAdvert = config  // started from peripheralManagerDidUpdateState
      return
    }
    advertise(config, on: manager)
  }

  func stopAdvertising() {
    pendingAdvert = nil
    peripheral?.stopAdvertising()
  }

  private func advertise(_ config: AdvertiseConfig, on manager: CBPeripheralManager) {
    var data: [String: Any] = [CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: config.serviceUuid)]]
    if let name = config.localName { data[CBAdvertisementDataLocalNameKey] = name }
    manager.startAdvertising(data)
  }

  private func begin(_ config: ScanConfig, on central: CBCentralManager) {
    let services = config.serviceUuids.isEmpty ? nil : config.serviceUuids.map { CBUUID(string: $0) }
    central.scanForPeripherals(
      withServices: services,
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    let interval = max(Double(config.batchIntervalMs), 50) / 1000
    flushTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
      self?.flush()
    }
  }

  // MARK: CBCentralManagerDelegate

  public func centralManagerDidUpdateState(_ central: CBCentralManager) {
    let state = Self.map(central.state)
    Task { @MainActor in try? await flutterApi.onAdapterStateChanged(state: state) }
    if central.state == .poweredOn, let config = pendingConfig {
      pendingConfig = nil
      begin(config, on: central)
    }
  }

  public func centralManager(
    _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any], rssi RSSI: NSNumber
  ) {
    let rssi = RSSI.intValue
    guard rssi != 127 else { return }  // 127 = RSSI unavailable

    var companyId: Int64?
    var payload: FlutterStandardTypedData?
    if let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data, data.count >= 2 {
      companyId = Int64(data[data.startIndex]) | (Int64(data[data.startIndex + 1]) << 8)
      payload = FlutterStandardTypedData(bytes: data.dropFirst(2))
    }
    var uuids = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
    uuids += (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID]) ?? []

    buffer.append(
      ScanSample(
        peripheralKey: peripheral.identifier.uuidString,
        rssi: Int64(rssi),
        txPower: (advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?.int64Value,
        companyId: companyId,
        manufacturerData: payload,
        serviceUuids: uuids.map { $0.uuidString },
        localName: advertisementData[CBAdvertisementDataLocalNameKey] as? String,
        connectable: (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue,
        serviceData: (advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data])?
          .reduce(into: [String: FlutterStandardTypedData]()) {
            $0[$1.key.uuidString] = FlutterStandardTypedData(bytes: $1.value)
          },
        monotonicNanos: Int64(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)),
        wallClockMillis: Int64(Date().timeIntervalSince1970 * 1000)))
  }

  // MARK: CBPeripheralManagerDelegate

  public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    let state = Self.map(peripheral.state)
    Task { @MainActor in try? await flutterApi.onAdapterStateChanged(state: state) }
    if peripheral.state == .poweredOn, let config = pendingAdvert {
      pendingAdvert = nil
      advertise(config, on: peripheral)
    }
  }

  public func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
    if let error {
      let code = Int64((error as NSError).code)
      let message = error.localizedDescription
      Task { @MainActor in try? await flutterApi.onAdvertiseError(code: code, message: message) }
    } else {
      Task { @MainActor in try? await flutterApi.onAdvertiseStarted() }
    }
  }

  // MARK: Helpers

  private func flush() {
    guard !buffer.isEmpty else { return }
    let batch = buffer
    buffer.removeAll(keepingCapacity: true)
    Task { @MainActor in try? await flutterApi.onSamples(samples: batch) }
  }

  private static func map(_ state: CBManagerState) -> AdapterState {
    switch state {
    case .poweredOn: return .poweredOn
    case .poweredOff: return .poweredOff
    case .unauthorized: return .unauthorized
    case .unsupported: return .unsupported
    case .resetting, .unknown: return .unknown
    @unknown default: return .unknown
    }
  }
}
