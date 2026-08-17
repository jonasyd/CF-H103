import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'neo_types.dart';

class ApiConfig {
  // La variable interna es estática
  static String? _baseUrl;
  static List<DepositOption>? _deposits;

  // El método de inicialización es estático
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('backend_url');

    // Cargar depósitos
    String? depositsJson = prefs.getString('deposits_list');
    if (depositsJson != null) {
      Iterable l = json.decode(depositsJson);
      _deposits = List<DepositOption>.from(
        l.map((model) => DepositOption.fromJson(model)),
      );
    }
  }

  // El getter DEBE ser 'static' para poder usar ApiConfig.baseUrl
  static String get baseUrl =>
      _baseUrl ?? 'https://dev.neoretail.com.ar/api/mobile/v1';

  static List<DepositOption> get deposits {
    return _deposits ?? defaultDepositOptions;
  }

  static void setBaseUrl(String newUrl) => _baseUrl = newUrl;

  static void setDeposits(List<DepositOption> newDeposits) =>
      _deposits = newDeposits;
}
