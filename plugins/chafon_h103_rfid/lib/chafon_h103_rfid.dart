import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ChafonH103RfidService {
  static const MethodChannel _channel = MethodChannel('chafon_h103_rfid');

  /// Inicializa los callbacks nativos.
  static void initCallbacks({
    Function(Map<String, dynamic>)? onTagRead,
    Function(Map<String, dynamic>)? onTagReadSingle,
    Function(Map<String, dynamic>)? onRadarResult,
    Function(Map<String, dynamic>)? onBatteryLevel,
    Function()? onBatteryTimeout,
    Function(Map<String, dynamic>)? onReadError,
    Function()? onDisconnected,
    Function(Map<String, dynamic>)? onDeviceFound,
    Function()? onFlashSaved,
    Function(String)? onScanError,

    /// Nuevo: barcode leído
    Function(Map<String, dynamic>)? onBarcodeRead,

    /// Nuevo: estado de trigger/key
    Function(Map<String, dynamic>)? onKeyState,
  }) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onTagRead':
          if (onTagRead != null) {
            onTagRead(Map<String, dynamic>.from(call.arguments));
          }
          break;

        case 'onTagReadSingle':
          if (onTagReadSingle != null) {
            onTagReadSingle(Map<String, dynamic>.from(call.arguments));
          }
          break;

        case 'onRadarSignal':
          if (onRadarResult != null) {
            onRadarResult(Map<String, dynamic>.from(call.arguments));
          }
          break;

        case 'onBatteryLevel':
          if (onBatteryLevel != null) {
            onBatteryLevel(Map<String, dynamic>.from(call.arguments));
          }
          break;

        case 'onBatteryTimeout':
          if (onBatteryTimeout != null) {
            onBatteryTimeout();
          }
          break;

        case 'onReadError':
          if (onReadError != null) {
            onReadError(Map<String, dynamic>.from(call.arguments));
          }
          break;

        case 'onDisconnected':
          if (onDisconnected != null) {
            onDisconnected();
          }
          break;

        case 'onDeviceFound':
          if (onDeviceFound != null) {
            onDeviceFound(Map<String, dynamic>.from(call.arguments));
          }
          break;

        case 'onFlashSaved':
          if (onFlashSaved != null) {
            onFlashSaved();
          }
          break;

        case 'onScanError':
          if (onScanError != null) {
            onScanError(call.arguments as String);
          }
          break;

        case 'onBarcodeRead':
          if (onBarcodeRead != null) {
            onBarcodeRead(Map<String, dynamic>.from(call.arguments));
          }
          break;

        case 'onKeyState':
          if (onKeyState != null) {
            onKeyState(Map<String, dynamic>.from(call.arguments));
          }
          break;

        default:
          debugPrint('Unhandled native callback: ${call.method}');
      }
    });
  }

  /// Helper: fuerza el rango 5..33; si llega 0, usa 6
  static int _normalizePower(int power) {
    final p = (power == 0 ? 6 : power);
    return p.clamp(5, 33).toInt();
  }

  // ========== Métodos generales ==========

  static Future<String?> getPlatformVersion() async {
    return await _channel.invokeMethod<String>('getPlatformVersion');
  }

  static Future<String?> getBatteryLevel() async {
    return await _channel.invokeMethod<String>('getBatteryLevel');
  }

  static Future<String?> startScan() async {
    return await _channel.invokeMethod<String>('startScan');
  }

  static Future<String?> stopScan() async {
    return await _channel.invokeMethod<String>('stopScan');
  }

  static Future<bool?> connect(String address) async {
    return await _channel.invokeMethod<bool>('connect', {
      'address': address,
    });
  }

  static Future<bool?> isConnected() async {
    return await _channel.invokeMethod<bool>('isConnected');
  }

  static Future<bool?> disconnect() async {
    return await _channel.invokeMethod<bool>('disconnect');
  }

  static Future<Map<String, int>> getAllDeviceConfig() async {
    final result = await _channel.invokeMethod<Map>('getAllDeviceConfig');
    return result?.map((key, value) => MapEntry(key.toString(), value as int)) ?? {};
  }

  // ========== Configuración RFID ==========

  /// Escribe solo la potencia.
  /// [saveToFlash]=true -> guarda en flash
  /// [resumeInventory]=true -> si inventory estaba corriendo, lo restaura
  static Future<String?> setOnlyOutputPower({
    required int power,
    bool saveToFlash = true,
    bool resumeInventory = false,
    int? region,
  }) async {
    final int p = _normalizePower(power);
    try {
      final res = await _channel.invokeMethod<String>('setOnlyOutputPower', {
        'power': p,
        'saveToFlash': saveToFlash,
        'resumeInventory': resumeInventory,
        if (region != null) 'region': region,
      });

      debugPrint(
        'setOnlyOutputPower: $res (p=$p save=$saveToFlash resume=$resumeInventory region=$region)',
      );
      return res;
    } catch (e) {
      debugPrint('setOnlyOutputPower error: $e');
      return null;
    }
  }

  /// Escribe la configuración completa.
  static Future<String?> sendAndSaveAllParams({
    required int power,
    int region = 2,
    int qValue = 4,
    int session = 0,
  }) async {
    final int p = _normalizePower(power);
    try {
      final result = await _channel.invokeMethod<String>(
        'sendAndSaveAllParams',
        {
          'power': p,
          'region': region,
          'qValue': qValue,
          'session': session,
        },
      );

      debugPrint(
        'sendAndSaveAllParams: $result (p=$p region=$region q=$qValue s=$session)',
      );
      return result;
    } catch (e) {
      debugPrint('sendAndSaveAllParams error: $e');
      return null;
    }
  }

  // ========== Inventory RFID ==========

  static Future<String?> startInventory() async {
    return await _channel.invokeMethod<String>('startInventory');
  }

  /// QEYD: Native tərəfdə 'startInventoryWithBank' yoxdursa, bunu istifadə etmə.
  /// Əvəzinə readSingleTagFromBank(...) yaz.
  @Deprecated('Si el método nativo no existe, usa readSingleTagFromBank')
  static Future<String?> startInventoryWithBank(String memoryBank) async {
    return await _channel.invokeMethod<String>('startInventoryWithBank', {
      'memoryBank': memoryBank,
    });
  }

  static Future<String?> stopInventory() async {
    return await _channel.invokeMethod<String>('stopInventory');
  }

  /// Lee un único tag desde EPC (0x01)
  static Future<String?> readSingleTag() async {
    return await _channel.invokeMethod<String>('readSingleTag', {
      'memoryBank': 0x01,
    });
  }

  /// Lee un único tag desde el banco indicado:
  /// EPC=0x01, TID=0x02, USER=0x03, etc.
  static Future<String?> readSingleTagFromBank(int memBank) async {
    return await _channel.invokeMethod<String>('readSingleTag', {
      'memoryBank': memBank,
    });
  }

  // ========== Radar RFID ==========

  static Future<void> startRadar(String epc) async {
    await _channel.invokeMethod('startRadarTracking', {
      'epc': epc,
    });
  }

  static Future<dynamic> startRadarMasked({
    required int maskStartAddress,
    required int maskLength,
    required String mask,
  }) async {
    return await _channel.invokeMethod('startRadarMasked', {
      'maskStartAddress': maskStartAddress,
      'maskLength': maskLength,
      'mask': mask,
    });
  }

  static Future<void> stopRadar() async {
    await _channel.invokeMethod('stopRadarTracking');
  }

  // ========== Barcode ==========

  /// Devuelve 'rfid' o 'barcode'
  static Future<String?> getReadMode() async {
    return await _channel.invokeMethod<String>('getReadMode');
  }

  /// Cambia el modo del lector:
  /// - 'rfid'
  /// - 'barcode'
  static Future<String?> setReadMode(String mode) async {
    assert(mode == 'rfid' || mode == 'barcode');
    return await _channel.invokeMethod<String>('setReadMode', {
      'mode': mode,
    });
  }

  static Future<String?> setBarcodeMode() async {
    return await setReadMode('barcode');
  }

  static Future<String?> setRfidMode() async {
    return await setReadMode('rfid');
  }

  /// Inicia lectura de barcode.
  /// El resultado leído llegará por callback `onBarcodeRead`.
  static Future<String?> startBarcodeScan() async {
    return await _channel.invokeMethod<String>('startBarcodeScan');
  }

  /// Detiene lectura de barcode.
  static Future<String?> stopBarcodeScan() async {
    return await _channel.invokeMethod<String>('stopBarcodeScan');
  }
}