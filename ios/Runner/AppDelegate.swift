import Flutter
import UIKit
import CoreBluetooth
import CoreLocation

@main
@objc class AppDelegate: FlutterAppDelegate {
    
    private var peripheralManager: CBPeripheralManager?
    private var advertisingData: [String: Any] = [:]
    private var isAdvertising = false
    private let CHANNEL = "ble_advertiser"
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        
        let controller = window?.rootViewController as! FlutterViewController
        let methodChannel = FlutterMethodChannel(name: CHANNEL, binaryMessenger: controller.binaryMessenger)
        
        methodChannel.setMethodCallHandler { [weak self] (call, result) in
            switch call.method {
            case "startAdvertising":
                if let userId = call.arguments as? [String: Any],
                   let userIdValue = userId["userId"] as? Int {
                    self?.startBleAdvertising(userId: userIdValue)
                }
                result(nil)
                
            case "stopAdvertising":
                self?.stopBleAdvertising()
                result(nil)
                
            case "isBluetoothOn":
                let isOn = self?.isBluetoothEnabled() ?? false
                result(isOn)
                
            case "requestEnableBluetooth":
                result(FlutterError(code: "NOT_SUPPORTED", 
                                  message: "En iOS debes activar Bluetooth manualmente desde Configuración", 
                                  details: nil))
                
            case "checkNativePermissions":
                let permissions = self?.checkPermissions() ?? [:]
                result(permissions)
                
            case "requestNativePermissions":
                self?.requestPermissions { permissionResults in
                    result(permissionResults)
                }
                
            case "openAppSettings":
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
                result(nil)
                
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    private func startBleAdvertising(userId: Int) {
        guard peripheralManager?.state == .poweredOn else {
            print("Bluetooth no está disponible")
            return
        }
        
        let calendar = Calendar.current
        let now = Date()
        let year = UInt8(calendar.component(.year, from: now) % 100)
        let month = UInt8(calendar.component(.month, from: now))
        let day = UInt8(calendar.component(.day, from: now))
        let hour = UInt8(calendar.component(.hour, from: now))
        let minute = UInt8(calendar.component(.minute, from: now))
        
        let manufacturerData = Data([
            0xAB, 0xCD,
            UInt8((userId >> 8) & 0xFF),
            UInt8(userId & 0xFF),
            year, month, day, hour, minute
        ])
        
        advertisingData = [
            CBAdvertisementDataManufacturerDataKey: manufacturerData,
            CBAdvertisementDataLocalNameKey: ""
        ]
        
        peripheralManager?.startAdvertising(advertisingData)
        isAdvertising = true
        print("Advertising iniciado con ID: \(userId)")
    }
    
    private func stopBleAdvertising() {
        if isAdvertising {
            peripheralManager?.stopAdvertising()
            isAdvertising = false
            print("Advertising detenido")
        }
    }
    
    private func isBluetoothEnabled() -> Bool {
        if peripheralManager == nil {
            peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        }
        return peripheralManager?.state == .poweredOn
    }
    
    private func checkPermissions() -> [String: Bool] {
        var permissions: [String: Bool] = [:]
        
        if #available(iOS 13.1, *) {
            permissions["BLUETOOTH_ADVERTISE"] = CBPeripheralManager.authorization == .allowedAlways
        } else {
            permissions["BLUETOOTH_ADVERTISE"] = true
        }
        
        let locationStatus = CLLocationManager.authorizationStatus()
        permissions["ACCESS_FINE_LOCATION"] = locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways
        
        return permissions
    }
    
    private func requestPermissions(completion: @escaping ([String: Bool]) -> Void) {
        let locationManager = CLLocationManager()
        
        if CLLocationManager.authorizationStatus() == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        
        if peripheralManager == nil {
            peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let results = self.checkPermissions()
            completion(results)
        }
    }
}

extension AppDelegate: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            print("Bluetooth está encendido y listo")
        case .poweredOff:
            print("Bluetooth está apagado")
            if isAdvertising {
                stopBleAdvertising()
            }
        case .unauthorized:
            print("Permisos de Bluetooth denegados")
        case .unsupported:
            print("Bluetooth LE no soportado en este dispositivo")
        default:
            print("Estado de Bluetooth: \(peripheral.state.rawValue)")
        }
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            print("Error al iniciar advertising: \(error.localizedDescription)")
            isAdvertising = false
        } else {
            print("Advertising iniciado exitosamente")
            isAdvertising = true
        }
    }
}
