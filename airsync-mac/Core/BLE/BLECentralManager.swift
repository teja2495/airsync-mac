import Foundation
import CoreBluetooth
import Combine

class BLECentralManager: NSObject, ObservableObject {
    static let shared = BLECentralManager()
    
    private var centralManager: CBCentralManager!
    private var discoveredPeripheral: CBPeripheral?
    
    private var characteristics: [CBUUID: CBCharacteristic] = [:]
    private var chunkBuffers: [CBUUID: [Int: Data]] = [:]
    private var discoveredServiceCount = 0
    private let expectedServiceCount = 4
    
    @Published var connectionStatus: BLEConnectionStatus = .disconnected
    @Published var connectedDeviceName: String? = nil
    
    var isConnected: Bool {
        connectionStatus != .disconnected && connectionStatus != .scanning
    }

    var isAuthenticated: Bool {
        connectionStatus == .authenticated
    }
    
    enum BLEConnectionStatus: Equatable {
        case disconnected
        case scanning
        case connected
        case authenticated
    }
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    private var scanTimer: Timer?
    private var connectionTimer: Timer?
    
    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        print("[BLE] Starting scan...")
        connectionStatus = .scanning
        
        centralManager.stopScan()
        scanTimer?.invalidate()
        
        centralManager.scanForPeripherals(withServices: [BLEConstants.serviceSystem], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        
        // Restart scan periodically to avoid stale states
        scanTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            print("[BLE] Restarting scan...")
            self?.centralManager.stopScan()
            self?.centralManager.scanForPeripherals(withServices: [BLEConstants.serviceSystem], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }
    
    func stopScanning() {
        scanTimer?.invalidate()
        scanTimer = nil
        centralManager.stopScan()
        if connectionStatus == .scanning {
            connectionStatus = .disconnected
        }
    }
    
    func disconnect() {
        if let peripheral = discoveredPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        connectionStatus = .disconnected
    }
    
    func write(characteristicUUID: CBUUID, data: Data) {
        guard let peripheral = discoveredPeripheral, let char = characteristics[characteristicUUID] else { return }
        peripheral.writeValue(data, for: char, type: .withoutResponse)
    }
    
    func writeChunked(characteristicUUID: CBUUID, payload: String) {
        let mtu = discoveredPeripheral?.maximumWriteValueLength(for: .withoutResponse) ?? 20
        let chunks = BLEChunkUtil.splitIntoChunks(payload: payload, mtu: mtu)
        for chunk in chunks {
            write(characteristicUUID: characteristicUUID, data: chunk)
        }
    }
}

extension BLECentralManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            if AppState.shared.isBLEEnabled {
                print("[BLE] Bluetooth powered on, starting scan")
                startScanning()
            }
        } else {
            print("[BLE] Bluetooth state changed: \(central.state.rawValue)")
            connectionStatus = .disconnected
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"
        let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        print("[BLE] Discovered \(name) with RSSI: \(RSSI), Services: \(serviceUUIDs.map { $0.uuidString }.joined(separator: ", "))")
        
        // Always connect if discovered while scanning
        discoveredPeripheral = peripheral
        connectedDeviceName = name
        centralManager.stopScan()
        scanTimer?.invalidate()
        scanTimer = nil
        
        print("[BLE] Attempting to connect to \(name)...")
        centralManager.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ])
        
        // CoreBluetooth connect() has no timeout — it can hang forever with stale pairing data.
        connectionTimer?.invalidate()
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            print("[BLE] Connection timed out, cancelling and retrying...")
            if let p = self.discoveredPeripheral {
                self.centralManager.cancelPeripheralConnection(p)
            }
            self.discoveredPeripheral = nil
            self.connectionStatus = .disconnected
            self.characteristics.removeAll()
            self.discoveredServiceCount = 0
            
            if AppState.shared.isBLEAutoConnectEnabled {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.startScanning()
                }
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionTimer?.invalidate()
        connectionTimer = nil
        let name = peripheral.name ?? "Unknown Device"
        let maxWrite = peripheral.maximumWriteValueLength(for: .withoutResponse)
        print("[BLE] Connected to \(name), Max Write Length: \(maxWrite)")
        connectionStatus = .connected
        peripheral.delegate = self
        peripheral.discoverServices([BLEConstants.serviceSystem, BLEConstants.serviceNotifications, BLEConstants.serviceMedia, BLEConstants.serviceClipboard])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionTimer?.invalidate()
        connectionTimer = nil
        print("[BLE] Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
        connectionStatus = .disconnected
        discoveredPeripheral = nil
        characteristics.removeAll()
        discoveredServiceCount = 0
        
        // Retry scanning after a delay
        if AppState.shared.isBLEAutoConnectEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.startScanning()
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectionTimer?.invalidate()
        connectionTimer = nil
        print("[BLE] Disconnected: \(error?.localizedDescription ?? "clean")")
        connectionStatus = .disconnected
        discoveredPeripheral = nil
        connectedDeviceName = nil
        characteristics.removeAll()
        chunkBuffers.removeAll()
        discoveredServiceCount = 0
        
        if AppState.shared.isBLEAutoConnectEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.startScanning()
            }
        }
    }
}

extension BLECentralManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        print("[BLE] Discovered \(chars.count) characteristics for service \(service.uuid)")
        for char in chars {
            characteristics[char.uuid] = char
            
            if char.properties.contains(.notify) {
                print("[BLE] Subscribing to \(char.uuid)")
                peripheral.setNotifyValue(true, for: char)
            }
        }
        
        discoveredServiceCount += 1
        print("[BLE] Services discovered: \(discoveredServiceCount)/\(expectedServiceCount)")
        
        // Only attempt auth after ALL services are discovered
        if discoveredServiceCount >= expectedServiceCount {
            if characteristics[BLEConstants.charAuthToken] != nil {
                print("[BLE] All services discovered, attempting authentication...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.attemptAuthentication()
                }
            }
        }
    }
    
    private func attemptAuthentication() {
        guard connectionStatus == .connected else { return }
        let token = UserDefaults.standard.string(forKey: "bleAuthToken") ?? ""
        if !token.isEmpty, let data = token.data(using: .utf8) {
            print("[BLE] Attempting authentication...")
            write(characteristicUUID: BLEConstants.charAuthToken, data: data)
        } else {
            print("[BLE] Auth token is empty, skipping auth")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
        switch characteristic.uuid {
        case BLEConstants.charAuthResult:
            if data.first == BLEConstants.authSuccess {
                print("[BLE] Auth Success!")
                connectionStatus = .authenticated
                
                // Immediately notify Android of Mac status
                WebSocketServer.shared.sendMacStatusOverBLE()
                
                // Also trigger a full fetch (which includes media info)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    MacInfoSyncManager.shared.fetch()
                }
            } else {
                print("[BLE] Auth Failed!")
                connectionStatus = .connected // Revert to connected but not auth
            }
        case BLEConstants.charBatteryLevel:
            let level = Int(data.first ?? 0)
            print("[BLE] Received Android Battery: \(level)%")
            DispatchQueue.main.async {
                if AppState.shared.status == nil {
                    AppState.shared.status = DeviceStatus(battery: DeviceStatus.Battery(level: level, isCharging: false), isPaired: true, music: nil)
                } else {
                    AppState.shared.status?.battery.level = level
                }
            }
        case BLEConstants.charNotificationData, BLEConstants.charMediaState, BLEConstants.charClipboardDataNotify, BLEConstants.charDeviceName, BLEConstants.charNotificationDismissNotify, BLEConstants.charMacControl:
            handleChunkedUpdate(uuid: characteristic.uuid, data: data)
        default:
            break
        }
    }
    
    private func handleChunkedUpdate(uuid: CBUUID, data: Data) {
        guard let (current, total) = BLEChunkUtil.parseHeader(from: data) else { return }
        let payload = BLEChunkUtil.getPayload(from: data)
        
        var buffer = chunkBuffers[uuid] ?? [:]
        buffer[current] = payload
        chunkBuffers[uuid] = buffer
        
        if buffer.count == total {
            let completePayload = BLEChunkUtil.reassemble(chunks: buffer)
            print("[BLE] Received complete chunked payload for \(uuid)")
            chunkBuffers.removeValue(forKey: uuid)
            
            // Route to BLETransportBridge
            BLETransportBridge.shared.handleIncoming(uuid: uuid, payload: completePayload)
        }
    }
}
