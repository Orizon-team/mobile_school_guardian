import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const nativeCodePlatform = MethodChannel("ble_advertiser");
  final TextEditingController _userId = TextEditingController();
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  String statusMessage = "Inicializando...";
  bool permissionsGranted = false;
  bool isBluetoothOn = false;
  bool isGpsOn = false;
  bool isAdvertising = false;
  bool isScanning = false;
  bool isServicesModalShowing = false;
  Timer? _statusCheckTimer;
  Timer? _scanTimeoutTimer;
  int userId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  @override
  void dispose() {
    _userId.dispose();
    _statusCheckTimer?.cancel();
    _scanSubscription?.cancel();
    _scanTimeoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    // Solicitar permisos al inicio
    final granted = await requestPermissions();
    if (!granted) {
      setState(() {
        statusMessage = "Permisos requeridos para continuar";
      });
    }

    // Iniciar monitoreo de servicios cada 2 segundos
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkServicesStatus();
    });
    _checkServicesStatus();
  }

  Future<void> _checkServicesStatus() async {
    if (!mounted) return;

    try {
      final bluetoothOn = await nativeCodePlatform.invokeMethod(
        'isBluetoothOn',
      );
      final locationStatus = await Permission.location.serviceStatus;

      setState(() {
        isBluetoothOn = bluetoothOn is bool && bluetoothOn;
        isGpsOn = !locationStatus.isDisabled;

        if (!permissionsGranted) {
          statusMessage = "Solicita permisos para continuar";
        } else if (!isBluetoothOn && !isGpsOn) {
          statusMessage = "Activa Bluetooth y GPS manualmente";
        } else if (!isBluetoothOn) {
          statusMessage = "Activa Bluetooth manualmente";
        } else if (!isGpsOn) {
          statusMessage = "Activa GPS manualmente";
        } else {
          statusMessage = "Todo listo - Puedes marcar asistencia";
        }
      });

      // Mostrar modal de servicios requeridos si es necesario
      if (!isBluetoothOn || !isGpsOn) {
        if (isAdvertising || isScanning || isServicesModalShowing) return;

        List<String> missingServices = [];
        if (!isBluetoothOn) missingServices.add("Bluetooth");
        if (!isGpsOn) missingServices.add("GPS");

        if (missingServices.isNotEmpty) {
          isServicesModalShowing = true;
          showDialog(
            context: context,
            barrierDismissible: true,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              title: Text('Servicios Requeridos'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bluetooth, color: Colors.blue, size: 100),
                      Icon(
                        Icons.location_on,
                        color: Colors.redAccent,
                        size: 100,
                      ),
                    ],
                  ),
                  Text(
                    'Para marcar asistencia necesitas activar: ${missingServices.join(" y ")}\n\n',
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    isServicesModalShowing = false;
                  },
                  child: Text('Entendido'),
                ),
              ],
            ),
          ).then((_) => isServicesModalShowing = false);
        }
      } else if (isServicesModalShowing) {
        Navigator.of(context).pop();
        isServicesModalShowing = false;
      }
    } catch (e) {
      setState(() {
        statusMessage = "Error verificando servicios: $e";
      });
    }
  }

  Future<bool> requestPermissions() async {
    try {
      final permissions = await [
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.location,
        Permission.locationWhenInUse,
      ].request();

      final granted = permissions.values.every(
        (permission) => permission.isGranted,
      );

      setState(() {
        permissionsGranted = granted;
        statusMessage = granted ? "Permisos concedidos" : "Permisos denegados";
      });

      return granted;
    } catch (e) {
      setState(() {
        statusMessage = "Error al solicitar permisos: $e";
      });
      return false;
    }
  }

  Future<void> startAdvertisingAndScanCycle() async {
    if (!permissionsGranted) {
      _showModal(
        "Permisos Requeridos",
        "Necesitas otorgar permisos primero",
        icon: Icons.error_outline,
        iconColor: Colors.red,
      );
      return;
    }

    if (!isBluetoothOn || !isGpsOn) {
      _showModal(
        "Servicios Requeridos",
        "Activa Bluetooth y GPS manualmente para continuar",
        icon: Icons.warning,
        iconColor: Colors.orange,
      );
      return;
    }

    if (_userId.text.isEmpty) {
      setState(() => statusMessage = "Introduce un ID de usuario");
      return;
    }

    try {
      userId = int.parse(_userId.text);

      // Mostrar modal de carga para advertising
      _showModal(
        "Exponiendo Datos BLE",
        "Presentando credencial...",
        isLoading: true,
      );

      await nativeCodePlatform.invokeMethod('startAdvertising', {
        'userId': userId,
      });
      setState(() {
        isAdvertising = true;
        statusMessage = "Exponiendo datos BLE... (5s)";
      });

      // Después de 5 segundos, cambiar a modo escaneo
      Future.delayed(const Duration(seconds: 5), () async {
        await stopProcess(); // Usar stopProcess para detener advertising
        _startScanningForResponse();
      });
    } catch (e) {
      Navigator.of(context).pop(); // Cerrar modal de carga si hay error
      setState(() {
        isAdvertising = false;
        statusMessage = "Error al activar Advertising: $e";
      });
      _showModal(
        "Error",
        "No se pudo iniciar el proceso",
        icon: Icons.error,
        iconColor: Colors.red,
      );
    }
  }

  void _showModal(
    String title,
    String message, {
    IconData? icon,
    Color? iconColor,
    bool isLoading = false,
  }) {
    showDialog(
      context: context,
      barrierDismissible: !isLoading,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              CircularProgressIndicator(color: Colors.blue)
            else if (icon != null)
              Icon(icon, color: iconColor ?? Colors.blue, size: 60),
            SizedBox(height: 20),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
        actions: isLoading
            ? null
            : [
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Aceptar'),
                  ),
                ),
              ],
      ),
    );
  }

  void _startScanningForResponse() {
    setState(() {
      isScanning = true;
      statusMessage = "Escuchando respuesta del ESP32...";
    });

    // Cerrar modal anterior y mostrar modal de escaneo
    Navigator.of(context).pop();
    _showModal(
      "Escaneando",
      "Esperando respuesta del ESP32...",
      isLoading: true,
    );

    // Configurar timeout de 30 segundos
    _scanTimeoutTimer?.cancel();
    _scanTimeoutTimer = Timer(const Duration(seconds: 60), () {
      FlutterBluePlus.stopScan();
      _scanSubscription?.cancel();
      Navigator.of(context).pop();
      setState(() {
        isScanning = false;
        statusMessage = "Sin respuesta del ESP32";
      });
      _showModal(
        "Tiempo Agotado",
        "No se recibió respuesta del ESP32 en 30 segundos. Inténtalo de nuevo.",
        icon: Icons.timer_off_outlined,
        iconColor: Colors.orange,
      );
    });

    // Configurar listener para resultados del escaneo
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult result in results) {
        final manufacturerData = result.advertisementData.manufacturerData;
        final payload = manufacturerData[0xFFFF];

        if (payload != null && payload.length == 3) {
          final espUserId = (payload[0] << 8) | payload[1];

          if (espUserId == userId) {
            // Limpiar y detener escaneo
            _scanTimeoutTimer?.cancel();
            FlutterBluePlus.stopScan();
            _scanSubscription?.cancel();
            Navigator.of(context).pop();
            setState(() => isScanning = false);

            // Procesar respuesta
            final status = payload[2];
            if (status == 1) {
              setState(
                () => statusMessage = "¡Asistencia marcada exitosamente!",
              );
              _showModal(
                "¡Asistencia Marcada!",
                "Tu asistencia fue registrada correctamente en el salón 204 - Matemáticas 9B",
                icon: Icons.check_circle_outline,
                iconColor: Colors.green,
              );
            } else {
              setState(() => statusMessage = "Asistencia fue rechazada");
              _showModal(
                "Asistencia Rechazada",
                "No tienes clase en este salón/laboratorio, verifica dónde es tu próxima clase.",
                icon: Icons.highlight_off,
                iconColor: Colors.red,
              );
            }
            break;
          }
        }
      }
    });

    // Iniciar el escaneo BLE
    FlutterBluePlus.startScan();
  }

  Future<void> stopProcess() async {
    // Detener advertising si está activo
    if (isAdvertising) {
      try {
        await nativeCodePlatform.invokeMethod('stopAdvertising');
        setState(() {
          isAdvertising = false;
          statusMessage = "Cambiando a modo escaneo...";
        });
      } catch (e) {
        setState(() => statusMessage = "Error al detener advertising");
      }
    }

    // Detener escaneo si está activo
    if (isScanning) {
      FlutterBluePlus.stopScan();
      _scanSubscription?.cancel();
      _scanTimeoutTimer?.cancel();
      setState(() {
        isScanning = false;
        statusMessage = "Proceso detenido";
      });
      Navigator.of(context).pop(); // Cerrar cualquier modal abierto
    }
  }

  Widget _buildStatusIndicator(String label, bool isActive) {
    return Column(
      children: [
        Icon(
          isActive ? Icons.check_circle : Icons.cancel,
          color: isActive ? Colors.green : Colors.red,
          size: 20,
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.green : Colors.red,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 47, 46, 50),
      appBar: AppBar(
        title: Text(
          "School Guardian",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color.fromARGB(255, 66, 41, 88),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Text(
                  "BLUETOOTH ADVERTISER APP",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 20),
                TextField(
                  keyboardType: TextInputType.number,
                  controller: _userId,
                  style: TextStyle(color: Colors.amber),
                  decoration: InputDecoration(
                    hintStyle: TextStyle(color: Colors.grey),
                    hintText: "123",
                    labelText: "ID de usuario",
                    labelStyle: TextStyle(color: Colors.amber),
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 20),
                ElevatedButton(
                  onPressed: requestPermissions,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: permissionsGranted
                        ? Colors.green
                        : Colors.orange,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        permissionsGranted
                            ? Icons.check_circle
                            : Icons.security,
                      ),
                      SizedBox(width: 8),
                      Text(
                        permissionsGranted
                            ? "Permisos OK"
                            : "Solicitar Permisos",
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 15),
                ElevatedButton(
                  onPressed: !permissionsGranted || !isBluetoothOn || !isGpsOn
                      ? null
                      : (isAdvertising || isScanning
                            ? null
                            : startAdvertisingAndScanCycle),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bluetooth),
                      Text("Marcar Asistencia"),
                    ],
                  ),
                ),
                SizedBox(height: 15),
                ElevatedButton(
                  onPressed: (isAdvertising || isScanning) ? stopProcess : null,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [Icon(Icons.stop), Text("Detener Proceso")],
                  ),
                ),
                SizedBox(height: 20),
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info, color: Colors.lightBlue),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              statusMessage,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.lightBlue,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildStatusIndicator("Permisos", permissionsGranted),
                          _buildStatusIndicator("Bluetooth", isBluetoothOn),
                          _buildStatusIndicator("GPS", isGpsOn),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        color: const Color.fromARGB(255, 66, 41, 88),
      ),
    );
  }
}
