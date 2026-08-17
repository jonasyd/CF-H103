import 'dart:async';
import 'dart:convert';

import 'package:chafon_h103_rfid/chafon_h103_rfid.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'neo_utils.dart';
import 'neo_types.dart';
import 'api_config.dart';

/// ------------------------------------------------------------
/// CONFIG
/// ------------------------------------------------------------

//const String kMobileApiBaseUrl = 'https://dev.neoretail.com.ar/api/mobile/v1';

/// ------------------------------------------------------------
/// STOCK API
/// ------------------------------------------------------------

class MobileStockApiService {
  final String baseUrl;
  final http.Client _client;

  MobileStockApiService({String? baseUrl, http.Client? client})
    : // Los dos puntos inician la lista de inicialización
      baseUrl = baseUrl ?? ApiConfig.baseUrl,
      _client = client ?? http.Client();

  Future<List<ModelSuggestion>> suggestModels({
    required String depositUuid,
    required String query,
    required bool onlyWithStock,
    int limit = 8,
  }) async {
    final uri = Uri.parse('$baseUrl/models/suggest').replace(
      queryParameters: {
        'depositUuid': depositUuid,
        'q': query,
        'onlyWithStock': onlyWithStock.toString(),
        'limit': limit.toString(),
      },
    );

    final json = await _getJson(uri);
    final data = asList(asMap(json)['data']);

    return data.map((e) => ModelSuggestion.fromJson(asMap(e))).toList();
  }

  Future<List<ModelSummary>> searchModels({
    required String depositUuid,
    required String query,
    bool onlyWithStock = false,
    int page = 1,
    int limit = 20,
  }) async {
    final uri = Uri.parse('$baseUrl/models').replace(
      queryParameters: {
        'depositUuid': depositUuid,
        'q': query,
        'onlyWithStock': onlyWithStock.toString(),
        'page': page.toString(),
        'limit': limit.toString(),
      },
    );

    final json = await _getJson(uri);
    final data = asList(asMap(json)['data']);

    return data.map((e) => ModelSummary.fromJson(asMap(e))).toList();
  }

  Future<ModelDetail> getModelDetail({
    required String modelUuid,
    required String depositUuid,
    bool onlyWithStock = false,
  }) async {
    final uri = Uri.parse('$baseUrl/models/$modelUuid').replace(
      queryParameters: {
        'depositUuid': depositUuid,
        'onlyWithStock': onlyWithStock.toString(),
      },
    );

    final json = await _getJson(uri);
    return ModelDetail.fromJson(asMap(asMap(json)['data']));
  }

  Future<ModelDetail> getByBarcode({
    required String barcode,
    required String depositUuid,
  }) async {
    final encodedBarcode = Uri.encodeComponent(barcode);

    final uri = Uri.parse(
      '$baseUrl/articles/by-barcode/$encodedBarcode',
    ).replace(queryParameters: {'depositUuid': depositUuid});

    final json = await _getJson(uri);
    return ModelDetail.fromJson(asMap(asMap(json)['data']));
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    try {
      final response = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));

      final bodyText = utf8.decode(response.bodyBytes);

      dynamic bodyJson;
      if (bodyText.trim().isNotEmpty) {
        try {
          bodyJson = jsonDecode(bodyText);
        } catch (_) {
          bodyJson = null;
        }
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (bodyJson is Map<String, dynamic>) {
          return bodyJson;
        }
        throw ApiException('Respuesta JSON inválida.');
      }

      throw ApiException(
        _extractErrorMessage(bodyJson, bodyText, response.statusCode),
        statusCode: response.statusCode,
      );
    } on http.ClientException catch (e) {
      throw ApiException('ClientException: $e');
    } on FormatException catch (e) {
      throw ApiException('FormatException: $e');
    } on TimeoutException catch (e) {
      throw ApiException('Timeout: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Error inesperado: $e');
    }
  }

  String _extractErrorMessage(
    dynamic bodyJson,
    String rawBody,
    int statusCode,
  ) {
    if (bodyJson is Map<String, dynamic>) {
      final detail = asString(bodyJson['detail']);
      final title = asString(bodyJson['title']);

      if (detail.isNotEmpty) return detail;
      if (title.isNotEmpty) return title;
    }

    if (rawBody.trim().isNotEmpty) {
      return rawBody;
    }

    return 'Error HTTP $statusCode';
  }
}

/// ------------------------------------------------------------
/// MODELOS DE SUGERENCIAS
/// ------------------------------------------------------------

class ModelSuggestion {
  final String modelUuid;
  final String modelCode;
  final String modelDescription;
  final ModelSuggestionImage image;

  const ModelSuggestion({
    required this.modelUuid,
    required this.modelCode,
    required this.modelDescription,
    required this.image,
  });

  factory ModelSuggestion.fromJson(Map<String, dynamic> json) {
    return ModelSuggestion(
      modelUuid: asString(json['modelUuid']),
      modelCode: asString(json['modelCode']),
      modelDescription: asString(json['modelDescription']),
      image: ModelSuggestionImage.fromJson(asMap(json['image'])),
    );
  }
}

class ModelSuggestionImage {
  final bool hasImage;
  final String? thumbUrl;

  const ModelSuggestionImage({
    required this.hasImage,
    required this.thumbUrl,
  });

  factory ModelSuggestionImage.fromJson(Map<String, dynamic> json) {
    final urls = asMap(json['urls']);
    return ModelSuggestionImage(
      hasImage: _asBool(json['hasImage']),
      thumbUrl: asString(urls['thumb']).trim().isEmpty
          ? null
          : asString(urls['thumb']).trim(),
    );
  }
}

/// ------------------------------------------------------------
/// WIDGET REUTILIZABLE DE IMAGEN
/// ------------------------------------------------------------

class _ProductImage extends StatelessWidget {
  final String? imageUrl;
  final double width;
  final double height;
  final double borderRadius;

  const _ProductImage({
    required this.imageUrl,
    required this.width,
    required this.height,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = _resolveImageUrl(imageUrl);

    if (resolvedUrl == null) {
      return _buildPlaceholder();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.network(
        resolvedUrl,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildPlaceholder(),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            return child;
          }

          final expected = loadingProgress.expectedTotalBytes;
          final value = expected != null
              ? loadingProgress.cumulativeBytesLoaded / expected
              : null;

          return Container(
            width: width,
            height: height,
            color: Colors.grey.shade100,
            alignment: Alignment.center,
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, value: value),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Icon(
        Icons.image_not_supported_outlined,
        size: width >= 100 ? 40 : 28,
        color: Colors.grey.shade600,
      ),
    );
  }
}

/// ------------------------------------------------------------
/// PANTALLA DE BÚSQUEDA
/// ------------------------------------------------------------

class StockScreenReal extends StatefulWidget {
  const StockScreenReal({super.key});

  @override
  State<StockScreenReal> createState() => _StockScreenRealState();
}

class _StockScreenRealState extends State<StockScreenReal>
    with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final MobileStockApiService _api = MobileStockApiService();

  // Declaramos la variable del UUID seleccionado (sin valor inicial fijo)
  late String _selectedDepositUuid;

  // Usamos los depósitos configurados:
  final List<DepositOption> _deposits = ApiConfig.deposits;

  Timer? _suggestDebounce;
  Timer? _scanBusyResetTimer;

  int _suggestRequestId = 0;

  bool _onlyWithStock = false;

  bool _isSuggesting = false;
  bool _isSearchingModels = false;

  String _message = '';

  List<ModelSuggestion> _suggestions = [];
  List<ModelSummary> _searchResults = [];

  bool _showSuggestions = false;
  bool _showSearchResults = false;

  /// ------------------------------------------------------------
  /// ESTADO DEL ESCÁNER DE CÓDIGO DE BARRAS
  /// ------------------------------------------------------------

  /// Cuando el escáner está activo/procesando una lectura.
  bool _isScanBusy = false;

  /// Cuando el gatillo físico está presionado (onKeyState == start).
  bool _isTriggerActive = false;

  /// Evita navegar dos veces si entran lecturas muy seguidas.
  bool _isHandlingScannedBarcode = false;

  /// Evita que el listener del TextField dispare sugerencias
  /// cuando el texto se asigna de forma programática desde el scan.
  bool _suppressSearchTextListener = false;

  /// Debounce simple para descartar lecturas duplicadas rápidas.
  String _lastScannedBarcode = '';
  DateTime? _lastScannedAt;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    // En Dart, no se puede ejecutar lógica de control (como un if o un bucle) directamente en el cuerpo de la clase.
    // El código debe vivir dentro de un método, como el initState.
    _selectedDepositUuid = _deposits.isNotEmpty ? _deposits.first.uuid : '';

    _searchController.addListener(_onSearchTextChanged);
    _searchFocusNode.addListener(_onSearchFocusChanged);

    // Registramos callbacks del lector para barcode.
    _registerBarcodeCallbacks();

    // Al entrar a la pantalla, dejamos el lector en modo barcode.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreBarcodeScannerContext();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _suggestDebounce?.cancel();
    _scanBusyResetTimer?.cancel();

    _searchController.removeListener(_onSearchTextChanged);
    _searchFocusNode.removeListener(_onSearchFocusChanged);

    _searchController.dispose();
    _searchFocusNode.dispose();

    // Detenemos el escaneo si hubiera quedado activo.
    _safeStopBarcodeScan();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Si la app vuelve al frente, restauramos callbacks y modo barcode.
    if (state == AppLifecycleState.resumed) {
      _restoreBarcodeScannerContext();
    }
  }

  /// ------------------------------------------------------------
  /// SCANNER BARCODE
  /// ------------------------------------------------------------

  void _onSearchFocusChanged() {
    if (_searchFocusNode.hasFocus) {
      _restoreBarcodeScannerContext();
    }
  }

  void _registerBarcodeCallbacks() {
    ChafonH103RfidService.initCallbacks(
      onBarcodeRead: (barcode) {
        final value = barcode['value']?.toString().trim() ?? '';
        if (value.isEmpty) return;

        _handleBarcodeRead(value);
      },
      onKeyState: (state) {
        final keyState = state['state']?.toString() ?? '';

        if (!mounted) return;

        setState(() {
          _isTriggerActive = keyState == 'start';

          // Si el gatillo deja de estar activo, soltamos el estado visual.
          if (!_isTriggerActive) {
            _isScanBusy = false;
          }
        });
      },
      onReadError: (map) {
        if (!mounted) return;

        final error =
            map['error']?.toString() ?? 'Error al leer el código de barras.';

        setState(() {
          _isScanBusy = false;
          _message = error;
        });
      },
      onDisconnected: () {
        if (!mounted) return;

        setState(() {
          _isScanBusy = false;
          _isTriggerActive = false;
          _message = 'El lector se desconectó.';
        });
      },
    );
  }

  Future<void> _restoreBarcodeScannerContext() async {
    // Ojo: initCallbacks suele ser global en este tipo de SDKs.
    // Lo volvemos a registrar al regresar a esta pantalla.
    _registerBarcodeCallbacks();
    await _ensureBarcodeMode();
  }

  Future<void> _ensureBarcodeMode() async {
    try {
      await ChafonH103RfidService.setBarcodeMode();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _message = 'No se pudo activar el modo barcode: $e';
      });
    }
  }

  Future<void> _startBarcodeScan() async {
    if (_isScanBusy || _isHandlingScannedBarcode) return;

    FocusScope.of(context).unfocus();

    _scanBusyResetTimer?.cancel();

    setState(() {
      _isScanBusy = true;
      _message = '';
    });

    try {
      _registerBarcodeCallbacks();
      await _ensureBarcodeMode();

      await ChafonH103RfidService.startBarcodeScan();

      // Fallback visual por si no entra callback de fin.
      _scanBusyResetTimer = Timer(const Duration(seconds: 8), () {
        if (!mounted) return;
        setState(() {
          _isScanBusy = false;
        });
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isScanBusy = false;
        _message = 'No se pudo iniciar el escaneo: $e';
      });
    }
  }

  Future<void> _stopBarcodeScanByUser() async {
    await _safeStopBarcodeScan();

    if (!mounted) return;

    setState(() {
      _isScanBusy = false;
      _isTriggerActive = false;
    });
  }

  Future<void> _safeStopBarcodeScan() async {
    try {
      await ChafonH103RfidService.stopBarcodeScan();
    } catch (_) {
      // Silencioso a propósito.
    }
  }

  bool _shouldIgnoreDuplicateBarcode(String value) {
    final now = DateTime.now();

    if (_lastScannedBarcode == value &&
        _lastScannedAt != null &&
        now.difference(_lastScannedAt!) < const Duration(milliseconds: 900)) {
      return true;
    }

    _lastScannedBarcode = value;
    _lastScannedAt = now;
    return false;
  }

  void _setSearchTextFromScanner(String value) {
    _suppressSearchTextListener = true;

    _searchController
      ..text = value
      ..selection = TextSelection.collapsed(offset: value.length);

    _suppressSearchTextListener = false;
  }

  Future<void> _handleBarcodeRead(String value) async {
    if (!mounted) return;
    if (value.isEmpty) return;
    if (_shouldIgnoreDuplicateBarcode(value)) return;

    _scanBusyResetTimer?.cancel();

    _setSearchTextFromScanner(value);

    setState(() {
      _isScanBusy = false;
      _message = '';
      _showSuggestions = false;
      _suggestions = [];
      _showSearchResults = false;
      _searchResults = [];
    });

    if (_isHandlingScannedBarcode) return;
    _isHandlingScannedBarcode = true;

    try {
      await _safeStopBarcodeScan();

      if (!mounted) return;

      // Acción automática ante lectura de barcode:
      // abrimos el detalle por barcode.
      await _openBarcodeDetail(barcodeOverride: value);
    } finally {
      _isHandlingScannedBarcode = false;
    }
  }

  /// ------------------------------------------------------------
  /// BÚSQUEDA MANUAL / SUGERENCIAS
  /// ------------------------------------------------------------

  void _onSearchTextChanged() {
    if (_suppressSearchTextListener) return;

    final query = _searchController.text.trim();

    _suggestDebounce?.cancel();

    if (!mounted) return;

    setState(() {
      _message = '';

      if (_showSearchResults) {
        _showSearchResults = false;
        _searchResults = [];
      }
    });

    if (query.isEmpty) {
      setState(() {
        _isSuggesting = false;
        _showSuggestions = false;
        _suggestions = [];
      });
      return;
    }

    if (query.length < 3) {
      setState(() {
        _isSuggesting = false;
        _showSuggestions = false;
        _suggestions = [];
      });
      return;
    }

    setState(() {
      _showSuggestions = true;
    });

    _suggestDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _fetchSuggestions(query),
    );
  }

  Future<void> _fetchSuggestions(String query) async {
    final requestId = ++_suggestRequestId;

    setState(() {
      _isSuggesting = true;
    });

    try {
      final items = await _api.suggestModels(
        depositUuid: _selectedDepositUuid,
        query: query,
        onlyWithStock: _onlyWithStock,
        limit: 8,
      );

      if (!mounted) return;
      if (requestId != _suggestRequestId) return;
      if (_searchController.text.trim() != query) return;

      setState(() {
        _suggestions = items;
        _showSuggestions = true;
      });
    } catch (_) {
      if (!mounted) return;
      if (requestId != _suggestRequestId) return;

      setState(() {
        _suggestions = [];
        _showSuggestions = true;
      });
    } finally {
      if (!mounted) return;
      if (requestId != _suggestRequestId) return;

      setState(() {
        _isSuggesting = false;
      });
    }
  }

  Future<void> _searchModels() async {
    final query = _searchController.text.trim();

    FocusScope.of(context).unfocus();

    if (query.isEmpty) {
      setState(() {
        _message = 'Ingresá un texto para buscar modelos.';
        _showSuggestions = false;
        _suggestions = [];
        _showSearchResults = false;
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _isSearchingModels = true;
      _message = '';
      _showSuggestions = false;
      _suggestions = [];
      _showSearchResults = true;
      _searchResults = [];
    });

    try {
      final results = await _api.searchModels(
        depositUuid: _selectedDepositUuid,
        query: query,
        onlyWithStock: _onlyWithStock,
      );

      if (!mounted) return;

      setState(() {
        _searchResults = results;
        if (results.isEmpty) {
          _message = 'No se encontraron modelos.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSearchingModels = false;
        });
      }
    }
  }

  Future<void> _openModelDetail({
    required String modelUuid,
    String? initialTitle,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ModelDetailScreen.byModel(
          api: _api,
          modelUuid: modelUuid,
          depositUuid: _selectedDepositUuid,
          initialTitle: initialTitle,
        ),
      ),
    );

    if (!mounted) return;
    await _restoreBarcodeScannerContext();
  }

  Future<void> _openBarcodeDetail({String? barcodeOverride}) async {
    final barcode = (barcodeOverride ?? _searchController.text).trim();

    FocusScope.of(context).unfocus();

    if (barcode.isEmpty) {
      setState(() {
        _message = 'Ingresá un barcode para buscar.';
      });
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ModelDetailScreen.byBarcode(
          api: _api,
          barcode: barcode,
          depositUuid: _selectedDepositUuid,
          initialTitle: barcode,
        ),
      ),
    );

    if (!mounted) return;
    await _restoreBarcodeScannerContext();
  }

  Future<void> _onDepositChanged(String? newDepositUuid) async {
    if (newDepositUuid == null || newDepositUuid == _selectedDepositUuid) {
      return;
    }

    setState(() {
      _selectedDepositUuid = newDepositUuid;
      _message = '';
    });

    final query = _searchController.text.trim();

    if (query.isEmpty) {
      setState(() {
        _showSuggestions = false;
        _suggestions = [];
        _showSearchResults = false;
        _searchResults = [];
      });
      return;
    }

    if (_showSearchResults) {
      await _searchModels();
      return;
    }

    if (query.length >= 3) {
      await _fetchSuggestions(query);
      return;
    }

    setState(() {
      _showSuggestions = false;
      _suggestions = [];
    });
  }

  Widget _buildScannerStatus() {
    final Color borderColor;
    final Color backgroundColor;
    final IconData icon;
    final String text;

    if (_isTriggerActive) {
      borderColor = Colors.green.shade300;
      backgroundColor = Colors.green.shade50;
      icon = Icons.radio_button_checked;
      text = 'Gatillo activo. Esperando lectura...';
    } else if (_isScanBusy) {
      borderColor = Colors.blue.shade300;
      backgroundColor = Colors.blue.shade50;
      icon = Icons.qr_code_scanner;
      text = 'Escaneando código de barras...';
    } else {
      borderColor = Colors.grey.shade300;
      backgroundColor = Colors.grey.shade50;
      icon = Icons.qr_code_2;
      text = 'Lector listo en modo barcode.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim();

    return Scaffold(
      appBar: AppBar(title: const Text('Consulta de stock')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              /// BUSCADOR
              TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _searchModels(),
                decoration: InputDecoration(
                  hintText: 'Buscar modelo o barcode',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isSuggesting)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else if (query.isNotEmpty)
                        IconButton(
                          tooltip: 'Limpiar',
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                          },
                        ),

                      IconButton(
                        tooltip: _isScanBusy
                            ? 'Detener escaneo'
                            : 'Escanear código de barras',
                        onPressed: _isHandlingScannedBarcode
                            ? null
                            : (_isScanBusy
                                  ? _stopBarcodeScanByUser
                                  : _startBarcodeScan),
                        icon: Icon(
                          _isScanBusy
                              ? Icons.stop_circle_outlined
                              : Icons.qr_code_scanner,
                          color: _isTriggerActive ? Colors.green : null,
                        ),
                      ),
                    ],
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              /// ESTADO DEL ESCÁNER
              _buildScannerStatus(),

              const SizedBox(height: 16),

              /// DEPÓSITO
              DropdownButtonFormField<String>(
                initialValue: _selectedDepositUuid,
                items: _deposits
                    .map(
                      (d) => DropdownMenuItem<String>(
                        value: d.uuid,
                        child: Text(d.label),
                      ),
                    )
                    .toList(),
                onChanged: _isSearchingModels ? null : _onDepositChanged,
                decoration: InputDecoration(
                  labelText: 'Depósito',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              /// SOLO CON STOCK
              SwitchListTile.adaptive(
                value: _onlyWithStock,
                contentPadding: EdgeInsets.zero,
                title: const Text('Solo con stock'),
                onChanged: (value) async {
                  setState(() {
                    _onlyWithStock = value;
                    _message = '';
                  });

                  final text = _searchController.text.trim();

                  if (_showSearchResults && text.isNotEmpty) {
                    await _searchModels();
                    return;
                  }

                  if (text.length >= 3) {
                    await _fetchSuggestions(text);
                  }
                },
              ),

              const SizedBox(height: 8),

              /// BOTONES DE BÚSQUEDA
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isSearchingModels ? null : _searchModels,
                      icon: const Icon(Icons.search),
                      label: Text(
                        _isSearchingModels ? 'Buscando...' : 'Buscar modelo',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openBarcodeDetail,
                      icon: const Icon(Icons.qr_code),
                      label: const Text('Buscar barcode'),
                    ),
                  ),
                ],
              ),

              if (_message.isNotEmpty) ...[
                const SizedBox(height: 16),
                _InfoMessage(message: _message),
              ],

              /// SUGERENCIAS
              if (_showSuggestions && !_showSearchResults && query.length >= 3)
                ...[
                  const SizedBox(height: 24),
                  const Text(
                    'Sugerencias',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  if (_suggestions.isEmpty && !_isSuggesting)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: const Text('No hay sugerencias para mostrar.'),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _suggestions.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          color: Colors.grey.shade200,
                        ),
                        itemBuilder: (context, index) {
                          final item = _suggestions[index];

                          return ListTile(
                            onTap: () => _openModelDetail(
                              modelUuid: item.modelUuid,
                              initialTitle: item.modelDescription,
                            ),
                            leading: _ProductImage(
                              imageUrl: item.image.thumbUrl,
                              width: 52,
                              height: 52,
                              borderRadius: 10,
                            ),
                            title: Text(
                              item.modelDescription.isNotEmpty
                                  ? item.modelDescription
                                  : 'Sin descripción',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              item.modelCode.isNotEmpty
                                  ? item.modelCode
                                  : 'Sin código',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.chevron_right),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _searchModels,
                      icon: const Icon(Icons.format_list_bulleted),
                      label: Text('Ver todos los resultados para "$query"'),
                    ),
                  ),
                ],

              /// RESULTADOS COMPLETOS
              if (_showSearchResults) ...[
                const SizedBox(height: 24),
                const Text(
                  'Resultados',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (_isSearchingModels)
                  const Center(child: CircularProgressIndicator())
                else if (_searchResults.isNotEmpty)
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _searchResults.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = _searchResults[index];

                      final colorLabels = item.colors
                          .map(
                            (e) =>
                                e.description.isNotEmpty ? e.description : e.code,
                          )
                          .where((e) => e.isNotEmpty)
                          .join(', ');

                      return InkWell(
                        onTap: () => _openModelDetail(
                          modelUuid: item.modelUuid,
                          initialTitle: item.modelDescription,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _ProductImage(
                                  imageUrl:
                                      item.image.cardUrl ?? item.image.thumbUrl,
                                  width: 88,
                                  height: 88,
                                  borderRadius: 12,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.modelDescription.isNotEmpty
                                            ? item.modelDescription
                                            : 'Sin descripción',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text('Código: ${item.modelCode}'),
                                      if (item.season.isNotEmpty)
                                        Text('Temporada: ${item.season}'),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Precio: ${_formatPriceSummary(item.priceSummary)}',
                                      ),
                                      Text(
                                        'Stock total: ${item.stockSummary.totalStock} | Tránsito: ${item.stockSummary.totalTransit}',
                                      ),
                                      if (colorLabels.isNotEmpty)
                                        Text('Colores: $colorLabels'),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.circle,
                                            size: 12,
                                            color: _getStatusColor(
                                              item.stockSummary.status,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            _getStatusLabel(
                                              item.stockSummary.status,
                                            ),
                                            style: TextStyle(
                                              color: _getStatusColor(
                                                item.stockSummary.status,
                                              ),
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// ------------------------------------------------------------
/// PANTALLA DE DETALLE
/// ------------------------------------------------------------

class ModelDetailScreen extends StatefulWidget {
  final MobileStockApiService api;
  final String depositUuid;
  final String? modelUuid;
  final String? barcode;
  final String? initialTitle;

  const ModelDetailScreen._({
    super.key,
    required this.api,
    required this.depositUuid,
    required this.modelUuid,
    required this.barcode,
    this.initialTitle,
  });

  factory ModelDetailScreen.byModel({
    Key? key,
    required MobileStockApiService api,
    required String modelUuid,
    required String depositUuid,
    String? initialTitle,
  }) {
    return ModelDetailScreen._(
      key: key,
      api: api,
      depositUuid: depositUuid,
      modelUuid: modelUuid,
      barcode: null,
      initialTitle: initialTitle,
    );
  }

  factory ModelDetailScreen.byBarcode({
    Key? key,
    required MobileStockApiService api,
    required String barcode,
    required String depositUuid,
    String? initialTitle,
  }) {
    return ModelDetailScreen._(
      key: key,
      api: api,
      depositUuid: depositUuid,
      modelUuid: null,
      barcode: barcode,
      initialTitle: initialTitle,
    );
  }

  @override
  State<ModelDetailScreen> createState() => _ModelDetailScreenState();
}

class _ModelDetailScreenState extends State<ModelDetailScreen> {
  bool _isLoading = true;
  String _message = '';

  ModelDetail? _detail;

  String? _selectedColorCode;
  String? _selectedSizeCode;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _message = '';
      _detail = null;
      _selectedColorCode = null;
      _selectedSizeCode = null;
    });

    try {
      final detail = widget.modelUuid != null
          ? await widget.api.getModelDetail(
              modelUuid: widget.modelUuid!,
              depositUuid: widget.depositUuid,
              onlyWithStock: false,
            )
          : await widget.api.getByBarcode(
              barcode: widget.barcode!,
              depositUuid: widget.depositUuid,
            );

      if (!mounted) return;

      setState(() {
        _detail = detail;
        _applyInitialSelection(detail);
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _message = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _applyInitialSelection(ModelDetail detail) {
    final selectionContext = detail.selectionContext;

    if (selectionContext != null) {
      final colorExists = detail.colors.any(
        (c) => c.code == selectionContext.selectedColorCode,
      );

      if (colorExists) {
        _selectedColorCode = selectionContext.selectedColorCode;
        final color = _getSelectedColor();

        if (color != null &&
            color.sizes.any(
              (s) => s.size.code == selectionContext.selectedSizeCode,
            )) {
          _selectedSizeCode = selectionContext.selectedSizeCode;
          return;
        }
      }
    }

    if (detail.colors.isEmpty) {
      _selectedColorCode = null;
      _selectedSizeCode = null;
      return;
    }

    _selectedColorCode = detail.colors.first.code;
    final firstColor = detail.colors.first;

    if (firstColor.sizes.isEmpty) {
      _selectedSizeCode = null;
      return;
    }

    final firstSelectable = firstColor.sizes.cast<ArticleVariant?>().firstWhere(
      (s) => s != null && s.selectable,
      orElse: () => null,
    );

    _selectedSizeCode =
        firstSelectable?.size.code ?? firstColor.sizes.first.size.code;
  }

  ModelColor? _getSelectedColor() {
    if (_detail == null || _selectedColorCode == null) return null;

    for (final color in _detail!.colors) {
      if (color.code == _selectedColorCode) return color;
    }
    return null;
  }

  ArticleVariant? _getSelectedVariant() {
    final color = _getSelectedColor();
    if (color == null || _selectedSizeCode == null) return null;

    for (final size in color.sizes) {
      if (size.size.code == _selectedSizeCode) return size;
    }
    return null;
  }

  void _selectColor(String colorCode) {
    final color = _detail?.colors.firstWhere(
      (c) => c.code == colorCode,
      orElse: () => ModelColor(
        code: '',
        description: '',
        rfidCode: 0,
        sizes: const [],
      ),
    );

    if (color == null || color.code.isEmpty) return;

    String? newSizeCode;

    if (color.sizes.any((s) => s.size.code == _selectedSizeCode)) {
      newSizeCode = _selectedSizeCode;
    } else {
      final firstSelectable = color.sizes.cast<ArticleVariant?>().firstWhere(
        (s) => s != null && s.selectable,
        orElse: () => null,
      );

      newSizeCode =
          firstSelectable?.size.code ??
          (color.sizes.isNotEmpty ? color.sizes.first.size.code : null);
    }

    setState(() {
      _selectedColorCode = colorCode;
      _selectedSizeCode = newSizeCode;
    });
  }

  void _selectSize(String sizeCode) {
    setState(() {
      _selectedSizeCode = sizeCode;
    });
  }

  Future<void> _openRfidSearchRequest(_RfidSearchRequest request) async {
    final connected = await ChafonH103RfidService.isConnected() == true;

    if (!mounted) return;

    if (!connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay un lector RFID conectado.'),
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _RfidEpcSearchScreen(request: request),
      ),
    );
  }

  _RfidSearchRequest _buildSearchByModel(ModelDetail detail) {
    final articleHex = _encodeModelArticleHex(detail.modelCode);
    final mask = '${_RfidEpcLayout.companyHex}$articleHex';

    return _RfidSearchRequest(
      title: 'Buscar EPC por Modelo',
      description: 'Todos los EPC del modelo',
      strategy: _RfidSearchStrategy.radarMasked,
      mask: mask,
      maskStartAddress: 0,
      maskLength: mask.length ~/ 2,
      targetLabel: mask,
      matcher: (epc) => _normalizeEpcHex(epc).startsWith(mask),
    );
  }

  _RfidSearchRequest _buildSearchByColor(
    ModelDetail detail,
    ModelColor color,
  ) {
    final articleHex = _encodeModelArticleHex(detail.modelCode);
    final colorHex = _encodeRfidCodeHex(
      color.rfidCode,
      _RfidEpcLayout.colorHexLength,
      fieldName: 'color',
    );

    final rawMask = '${_RfidEpcLayout.companyHex}$articleHex$colorHex';

    // Asegura que la máscara siempre sea de longitud par (ej: 16 caracteres = 8 bytes)
    final mask = rawMask.length.isOdd ? '${rawMask}0' : rawMask;
    return _RfidSearchRequest(
      title: 'Buscar EPC por Color',
      description: 'Todos los EPC del modelo del color elegido',
      strategy: _RfidSearchStrategy.radarMasked,
      mask: mask,
      maskStartAddress: 0,
      maskLength: mask.length ~/ 2,
      targetLabel: mask,
      matcher: (epc) => _normalizeEpcHex(epc).startsWith(mask),
    );
  }

  _RfidSearchRequest _buildSearchBySize(
    ModelDetail detail,
    ArticleVariant variant,
  ) {
    final articleHex = _encodeModelArticleHex(detail.modelCode);
    final sizeHex = _encodeRfidCodeHex(
      variant.size.rfidCode,
      _RfidEpcLayout.sizeHexLength,
      fieldName: 'talle',
    );

    final modelPrefix = '${_RfidEpcLayout.companyHex}$articleHex';
    final sizeStart = _RfidEpcLayout.companyHexLength +
        _RfidEpcLayout.articleHexLength +
        _RfidEpcLayout.colorHexLength;

    return _RfidSearchRequest(
      title: 'Buscar EPC por Talle',
      description: 'Todos los EPC del modelo del talle elegido',
      strategy: _RfidSearchStrategy.inventoryFiltered,
      mask: null,
      maskStartAddress: 0,
      maskLength: 0,
      targetLabel: 'modelo=$modelPrefix talle=$sizeHex',
      matcher: (epc) {
        final normalized = _normalizeEpcHex(epc);

        if (normalized.length <
            sizeStart + _RfidEpcLayout.sizeHexLength) {
          return false;
        }

        return normalized.startsWith(modelPrefix) &&
            normalized.substring(
                  sizeStart,
                  sizeStart + _RfidEpcLayout.sizeHexLength,
                ) ==
                sizeHex;
      },
    );
  }

  _RfidSearchRequest _buildSearchByColorAndSize(
    ModelDetail detail,
    ModelColor color,
    ArticleVariant variant,
  ) {
    final articleHex = _encodeModelArticleHex(detail.modelCode);
    final colorHex = _encodeRfidCodeHex(
      color.rfidCode,
      _RfidEpcLayout.colorHexLength,
      fieldName: 'color',
    );
    final sizeHex = _encodeRfidCodeHex(
      variant.size.rfidCode,
      _RfidEpcLayout.sizeHexLength,
      fieldName: 'talle',
    );

    final mask =
        '${_RfidEpcLayout.companyHex}$articleHex$colorHex$sizeHex';

    return _RfidSearchRequest(
      title: 'Buscar EPC por Color y Talle',
      description: 'Todos los EPC del modelo del color y talle elegidos',
      strategy: _RfidSearchStrategy.radarMasked,
      mask: mask,
      maskStartAddress: 0,
      maskLength: mask.length ~/ 2,
      targetLabel: mask,
      matcher: (epc) => _normalizeEpcHex(epc).startsWith(mask),
    );
  }

  Widget _buildRfidSection({
    required ModelDetail detail,
    required ModelColor? selectedColor,
    required ArticleVariant? selectedVariant,
  }) {
    try {
      final articleHex = _encodeModelArticleHex(detail.modelCode);
      final colorHex = selectedColor == null
          ? null
          : _encodeRfidCodeHex(
              selectedColor.rfidCode,
              _RfidEpcLayout.colorHexLength,
              fieldName: 'color',
            );
      final sizeHex = selectedVariant == null
          ? null
          : _encodeRfidCodeHex(
              selectedVariant.size.rfidCode,
              _RfidEpcLayout.sizeHexLength,
              fieldName: 'talle',
            );

      final byModel = _buildSearchByModel(detail);
      final byColor = selectedColor == null
          ? null
          : _buildSearchByColor(detail, selectedColor);
      final bySize = selectedVariant == null
          ? null
          : _buildSearchBySize(detail, selectedVariant);
      final byColorAndSize =
          (selectedColor == null || selectedVariant == null)
              ? null
              : _buildSearchByColorAndSize(
                  detail,
                  selectedColor,
                  selectedVariant,
                );

      return Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Búsqueda RFID / EPC',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Empresa HEX: ${_RfidEpcLayout.companyHex}'),
                    Text('Artículo HEX: $articleHex'),
                    Text('Color HEX: ${colorHex ?? '-'}'),
                    Text('Talle HEX: ${sizeHex ?? '-'}'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _RfidActionButton(
                title: 'Buscar EPC por Modelo',
                subtitle: 'Todos los EPC del modelo',
                icon: Icons.sell_outlined,
                onPressed: () => _openRfidSearchRequest(byModel),
              ),
              const SizedBox(height: 8),
              _RfidActionButton(
                title: 'Buscar EPC por Color',
                subtitle: 'Todos los EPC del modelo del color elegido',
                icon: Icons.palette_outlined,
                onPressed: byColor == null
                    ? null
                    : () => _openRfidSearchRequest(byColor),
              ),
              const SizedBox(height: 8),
              _RfidActionButton(
                title: 'Buscar EPC por Talle',
                subtitle: 'Todos los EPC del modelo del talle elegido',
                icon: Icons.straighten_outlined,
                onPressed: bySize == null
                    ? null
                    : () => _openRfidSearchRequest(bySize),
              ),
              const SizedBox(height: 8),
              _RfidActionButton(
                title: 'Buscar EPC por Color y Talle',
                subtitle:
                    'Todos los EPC del modelo del color y talle elegidos',
                icon: Icons.tune_outlined,
                onPressed: byColorAndSize == null
                    ? null
                    : () => _openRfidSearchRequest(byColorAndSize),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      return _InfoMessage(
        message: 'No se pudo preparar la búsqueda RFID: $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final selectedColor = _getSelectedColor();
    final selectedVariant = _getSelectedVariant();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          detail?.modelDescription.isNotEmpty == true
              ? detail!.modelDescription
              : (widget.initialTitle?.trim().isNotEmpty == true
                  ? widget.initialTitle!.trim()
                  : 'Detalle de modelo'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : detail == null
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_message.isNotEmpty) _InfoMessage(message: _message),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        /// PRODUCTO
                        Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _ProductImage(
                                  imageUrl: detail.image.detailUrl ??
                                      detail.image.cardUrl ??
                                      detail.image.thumbUrl,
                                  width: 100,
                                  height: 100,
                                  borderRadius: 12,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        detail.modelDescription.isNotEmpty
                                            ? detail.modelDescription
                                            : 'Sin descripción',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text('Código: ${detail.modelCode}'),
                                      if (detail.season.isNotEmpty)
                                        Text('Temporada: ${detail.season}'),
                                      Text('Depósito: ${widget.depositUuid}'),
                                      if (selectedColor != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(
                                            'Color: ${selectedColor.description.isNotEmpty ? selectedColor.description : selectedColor.code}',
                                          ),
                                        ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Precio modelo: ${_formatPriceSummary(detail.priceSummary)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (detail.selectionContext != null) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          'Resuelto por barcode: ${detail.selectionContext!.barcode}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        _buildRfidSection(
                          detail: detail,
                          selectedColor: selectedColor,
                          selectedVariant: selectedVariant,
                        ),

                        const SizedBox(height: 16),

                        /// COLORES
                        const Text(
                          'Colores',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (detail.colors.isEmpty)
                          const Text('No hay colores disponibles.')
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: detail.colors.map((color) {
                              final isSelected =
                                  color.code == _selectedColorCode;

                              return ChoiceChip(
                                label: Text(
                                  color.description.isNotEmpty
                                      ? color.description
                                      : color.code,
                                ),
                                selected: isSelected,
                                onSelected: (_) => _selectColor(color.code),
                              );
                            }).toList(),
                          ),

                        const SizedBox(height: 16),

                        /// TALLES
                        const Text(
                          'Talles',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (selectedColor == null || selectedColor.sizes.isEmpty)
                          const Text('No hay talles disponibles para este color.')
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: selectedColor.sizes.map((variant) {
                              final isSelected =
                                  variant.size.code == _selectedSizeCode;

                              return ChoiceChip(
                                label: Text(
                                  variant.size.description.isNotEmpty
                                      ? variant.size.description
                                      : variant.size.code,
                                ),
                                selected: isSelected,
                                onSelected: variant.selectable
                                    ? (_) => _selectSize(variant.size.code)
                                    : null,
                              );
                            }).toList(),
                          ),

                        const SizedBox(height: 16),

                        /// STOCK
                        if (selectedVariant != null)
                          Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.circle,
                                        color: _getStatusColor(
                                          selectedVariant.stock.status,
                                        ),
                                        size: 12,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _getStatusLabel(
                                          selectedVariant.stock.status,
                                        ),
                                        style: TextStyle(
                                          color: _getStatusColor(
                                            selectedVariant.stock.status,
                                          ),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Talle: ${selectedVariant.size.description.isNotEmpty ? selectedVariant.size.description : selectedVariant.size.code}',
                                  ),
                                  const SizedBox(height: 8),
                                  Text('Stock: ${selectedVariant.stock.current}'),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.local_shipping_outlined,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Tránsito: ${selectedVariant.stock.transit}',
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Remoto: ${selectedVariant.stock.remote}',
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Replicado remoto: ${selectedVariant.stock.replicatedRemote}',
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Precio: ${formatPrice(selectedVariant.price)}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Barcode: ${selectedVariant.barcode}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

/// ------------------------------------------------------------
/// WIDGETS AUXILIARES
/// ------------------------------------------------------------

class _InfoMessage extends StatelessWidget {
  final String message;

  const _InfoMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Text(
        message,
        style: TextStyle(color: Colors.orange.shade900),
      ),
    );
  }
}

enum _RfidSearchStrategy {
  radarMasked,
  inventoryFiltered,
}

class _RfidSearchRequest {
  final String title;
  final String description;
  final _RfidSearchStrategy strategy;
  final String? mask;
  final int maskStartAddress;
  final int maskLength;
  final String targetLabel;
  final bool Function(String epc) matcher;

  _RfidSearchRequest({
    required this.title,
    required this.description,
    required this.strategy,
    required this.mask,
    required this.maskStartAddress,
    required this.maskLength,
    required this.targetLabel,
    required this.matcher,
  });
}

class _RfidEpcLayout {
  // Estructura usada en la app:
  // [empresa HEX 6] + [artículo HEX 6] + [color HEX 6] + [talle HEX 6] + [serie...]
  static const String companyHex = '008100';

  static const int companyHexLength = 6;
  static const int articleHexLength = 6;
  static const int colorHexLength = 3;
  static const int sizeHexLength = 3;
}

class _RfidActionButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onPressed;

  const _RfidActionButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.all(14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RfidEpcSearchScreen extends StatefulWidget {
  final _RfidSearchRequest request;

  const _RfidEpcSearchScreen({
    required this.request,
  });

  @override
  State<_RfidEpcSearchScreen> createState() => _RfidEpcSearchScreenState();
}

class _RfidEpcSearchScreenState extends State<_RfidEpcSearchScreen> {
  bool _isStarting = true;
  bool _isActive = false;
  String _message = '';

  String _lastEpc = '';
  double _signalProgress = 0;
  Color _signalColor = Colors.grey;

  final Map<String, Map<String, dynamic>> _matches = {};

  @override
  void initState() {
    super.initState();

    ChafonH103RfidService.initCallbacks(
      onTagRead: (tag) {
        if (widget.request.strategy != _RfidSearchStrategy.inventoryFiltered) {
          return;
        }
        _consumeTag(tag);
      },
      onRadarResult: (tag) {
        if (widget.request.strategy != _RfidSearchStrategy.radarMasked) {
          return;
        }
        _consumeTag(tag);
      },
      onReadError: (map) {
        final error = map['error']?.toString() ?? 'Unknown error';
        if (!mounted) return;

        setState(() {
          _message = error;
        });
      },
      onDisconnected: () {
        if (!mounted) return;

        setState(() {
          _isActive = false;
          _message = 'El lector RFID se desconectó.';
        });
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startSearch();
    });
  }

  void _consumeTag(dynamic tag) {
    final epc = tag['epc']?.toString() ?? '';
    final rssi = asInt(tag['rssi']);

    _recordMatch(epc, rssi);
  }

  void _recordMatch(String epc, int rssi) {
    final normalized = _normalizeEpcHex(epc);

    if (normalized.isEmpty) return;
    if (!widget.request.matcher(normalized)) return;
    if (!mounted) return;

    final now = DateTime.now();

    setState(() {
      if (_matches.containsKey(normalized)) {
        _matches[normalized]!['count'] =
            asInt(_matches[normalized]!['count']) + 1;
        _matches[normalized]!['rssi'] = rssi;
        _matches[normalized]!['lastSeen'] = now;
      } else {
        _matches[normalized] = {
          'count': 1,
          'rssi': rssi,
          'lastSeen': now,
        };
      }

      _lastEpc = normalized;
      _signalProgress = _rssiToProgress(rssi);
      _signalColor = _rssiToColor(rssi);
    });
  }

  Future<void> _startSearch() async {
    if (mounted) {
      setState(() {
        _isStarting = true;
        _isActive = false;
        _message = '';
        _matches.clear();
        _lastEpc = '';
        _signalProgress = 0;
        _signalColor = Colors.grey;
      });
    }

    try {
      await _stopSearchSilently();
      await ChafonH103RfidService.setRfidMode();

      if (widget.request.strategy == _RfidSearchStrategy.radarMasked) {
        await ChafonH103RfidService.startRadarMasked(
          maskStartAddress: widget.request.maskStartAddress,
          maskLength: widget.request.maskLength,
          mask: widget.request.mask!,
        );
      } else {
        await ChafonH103RfidService.startInventory();
      }

      if (!mounted) return;

      setState(() {
        _isActive = true;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _message = 'Error al iniciar la búsqueda RFID: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
      }
    }
  }

  Future<void> _stopSearchSilently() async {
    try {
      await ChafonH103RfidService.stopRadar();
    } catch (_) {}

    try {
      await ChafonH103RfidService.stopInventory();
    } catch (_) {}
  }

  Future<void> _stopSearch() async {
    await _stopSearchSilently();

    if (!mounted) return;

    setState(() {
      _isActive = false;
      _signalProgress = 0;
      _signalColor = Colors.grey;
    });
  }

  @override
  void dispose() {
    _stopSearchSilently();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _matches.entries.toList()
      ..sort((a, b) {
        final aDate = a.value['lastSeen'] as DateTime?;
        final bDate = b.value['lastSeen'] as DateTime?;
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.request.title),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.request.description,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Modo: ${widget.request.strategy == _RfidSearchStrategy.radarMasked ? 'Radar por máscara' : 'Inventario filtrado'}',
                      ),
                      const SizedBox(height: 8),
                      Text('Objetivo: ${widget.request.targetLabel}'),
                      if (widget.request.mask != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Mask Start: ${widget.request.maskStartAddress} | Mask Length: ${widget.request.maskLength}',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (_message.isNotEmpty) ...[
                const SizedBox(height: 12),
                _InfoMessage(message: _message),
              ],
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _signalProgress,
                minHeight: 18,
                color: _signalColor,
                backgroundColor: Colors.grey.shade300,
              ),
              const SizedBox(height: 8),
              Text(
                'Último EPC detectado: ${_lastEpc.isEmpty ? '-' : _lastEpc}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (_isStarting || _isActive) ? null : _startSearch,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(_isStarting ? 'Iniciando...' : 'Iniciar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isActive ? _stopSearch : null,
                      icon: const Icon(Icons.stop),
                      label: const Text('Detener'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'EPC detectados (${entries.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: entries.isEmpty
                    ? const Center(
                        child: Text('Todavía no se detectaron EPCs.'),
                      )
                    : ListView.separated(
                        itemCount: entries.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = entries[index];
                          final epc = item.key;
                          final data = item.value;
                          final lastSeen = data['lastSeen'] as DateTime?;

                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.nfc),
                              title: Text(epc),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('RSSI: ${data['rssi']} dBm'),
                                  Text('Lecturas: ${data['count']}'),
                                  Text(
                                    'Última detección: ${lastSeen != null ? _formatSeenTime(lastSeen) : '-'}',
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ------------------------------------------------------------
/// HELPERS
/// ------------------------------------------------------------

String? _resolveImageUrl(String? value) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) return null;

  final uri = Uri.tryParse(raw);
  if (uri == null) return null;

  if (uri.hasScheme) {
    return uri.toString();
  }

  final dynBaseUrl = ApiConfig.baseUrl;
  final baseUri = Uri.parse('$dynBaseUrl/');
  return baseUri.resolve(raw).toString();
}

bool _asBool(dynamic value) {
  if (value is bool) return value;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' || normalized == '1';
  }
  if (value is num) return value != 0;
  return false;
}

Color _getStatusColor(String status) {
  switch (status) {
    case 'out_of_stock':
      return Colors.red;
    case 'low_stock':
      return Colors.orange;
    case 'available':
      return Colors.green;
    default:
      return Colors.grey;
  }
}

String _getStatusLabel(String status) {
  switch (status) {
    case 'out_of_stock':
      return 'Sin stock';
    case 'low_stock':
      return 'Últimas unidades';
    case 'available':
      return 'Disponible';
    default:
      return 'Sin información';
  }
}

String _formatPriceSummary(PriceSummary summary) {
  if (summary.sameAcrossVariants || summary.minPrice == summary.maxPrice) {
    return formatPrice(summary.minPrice);
  }

  return '${formatPrice(summary.minPrice)} - ${formatPrice(summary.maxPrice)}';
}

String formatPrice(num value) {
  final int rounded = value.round();
  final raw = rounded.toString();
  final reversed = raw.split('').reversed.toList();

  final buffer = StringBuffer();

  for (int i = 0; i < reversed.length; i++) {
    if (i > 0 && i % 3 == 0) {
      buffer.write('.');
    }
    buffer.write(reversed[i]);
  }

  final formatted = buffer.toString().split('').reversed.join();
  return '\$$formatted';
}

String _encodeModelArticleHex(String modelCode) {
  final parsed = int.tryParse(modelCode.trim());

  if (parsed == null) {
    throw FormatException(
      'El modelCode "$modelCode" no es numérico y no se puede convertir a HEX.',
    );
  }

  return _toFixedHex(
    parsed,
    _RfidEpcLayout.articleHexLength,
    fieldName: 'artículo',
  );
}

String _encodeRfidCodeHex(
  int value,
  int width, {
  required String fieldName,
}) {
  if (value <= 0) {
    throw FormatException(
      'El RFID_CODE de $fieldName es inválido: $value',
    );
  }

  return _toFixedHex(value, width, fieldName: fieldName);
}

String _toFixedHex(
  int value,
  int width, {
  required String fieldName,
}) {
  final hex = value.toRadixString(16).toUpperCase();

  if (hex.length > width) {
    throw FormatException(
      'El valor RFID de $fieldName excede el ancho HEX esperado ($width).',
    );
  }

  return hex.padLeft(width, '0');
}

String _normalizeEpcHex(String value) {
  var normalized = value.trim().replaceAll(RegExp(r'\s+'), '');

  if (normalized.startsWith('0x') || normalized.startsWith('0X')) {
    normalized = normalized.substring(2);
  }

  return normalized.toUpperCase();
}

double _rssiToProgress(int rssi, {int min = -90, int max = -40}) {
  if (rssi <= min) return 0;
  if (rssi >= max) return 1;

  return (rssi - min) / (max - min);
}

Color _rssiToColor(int rssi) {
  final progress = _rssiToProgress(rssi);

  if (progress >= 0.70) return Colors.green;
  if (progress >= 0.40) return Colors.orange;
  return Colors.red;
}

String _formatSeenTime(DateTime dt) {
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  final ss = dt.second.toString().padLeft(2, '0');
  return '$hh:$mm:$ss';
}
