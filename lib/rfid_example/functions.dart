import 'package:chafon_h103_rfid/chafon_h103_rfid.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'device_scan_screen.dart';

class Functions extends StatefulWidget {
  const Functions({super.key});

  @override
  State<Functions> createState() => _FunctionsState();
}

class _FunctionsState extends State<Functions> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool isLoading = false;
  bool isBarcodeBusy = false;
  bool isBarcodeTriggerActive = false;
  bool _isNavigatingAway = false;
  bool _isChangingMode = false;

  Map<String, Map<String, dynamic>> tagMap = {};
  String lastTagInfo = 'Tag not read';
  String log = '';
  String selectedMemoryBank = 'EPC';
  final memoryBankOptions = ['TID', 'EPC'];
  int? outputPower;
  int? batteryLevel;

  // Controladores para Radar
  final TextEditingController epcController = TextEditingController();
  final TextEditingController maskStartController = TextEditingController();
  final TextEditingController maskLengthController = TextEditingController();
  final TextEditingController maskHexController = TextEditingController();

  // Barcode state
  String currentReadMode = 'rfid';
  String lastBarcodeValue = 'No barcode read';
  final List<Map<String, dynamic>> barcodeHistory = [];
  String? _lastBarcodeDedupValue;
  DateTime? _lastBarcodeDedupAt;

  // 'epc' o 'mask'
  String radarSearchMode = 'epc';

  // Radar UI state
  double radarProgress = 0.0;
  Color radarColor = Colors.grey;
  String radarTarget = '';
  String lastRadarEpc = '';
  bool isRadarActive = false;

  int _normalizePower(int? p) {
    final v = (p == null || p == 0) ? 6 : p;
    return v.clamp(5, 33);
  }

  int _memBankCode(String bank) {
    switch (bank) {
      case 'TID':
        return 0x02;
      case 'EPC':
      default:
        return 0x01;
    }
  }

  int _normalizeRssi(int rssi, {int min = -90, int max = -40}) {
    if (rssi < min) return 0;
    if (rssi > max) return 100;
    return ((rssi - min) * 100 / (max - min)).toInt();
  }

  String _normalizeHex(String value) {
    var v = value.trim().replaceAll(RegExp(r'\s+'), '');
    if (v.startsWith('0x') || v.startsWith('0X')) {
      v = v.substring(2);
    }
    return v.toUpperCase();
  }

  bool _isValidHex(String value) {
    return RegExp(r'^[0-9A-Fa-f]+$').hasMatch(value);
  }

  String _formatTime(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  bool _isBarcodeTab(int index) => index == 3;

  bool _isRfidTab(int index) => index >= 0 && index <= 2;

  void _handleRadar(String epc, int rssi) {
    if (!isRadarActive) return;

    final strength = _normalizeRssi(rssi);

    SystemSound.play(SystemSoundType.click);

    Color color;
    if (strength > 70) {
      color = Colors.green;
    } else if (strength > 40) {
      color = Colors.yellow;
    } else {
      color = Colors.red;
    }

    setState(() {
      radarProgress = strength / 100;
      radarColor = color;
      lastRadarEpc = epc;
    });
  }

  Future<void> _refreshReadMode() async {
    try {
      final mode = await ChafonH103RfidService.getReadMode();
      if (!mounted || mode == null) return;
      setState(() {
        currentReadMode = mode;
      });
    } catch (_) {}
  }

  Future<void> _initializeScreen() async {
    await loadDeviceConfig();
    await _refreshReadMode();
    await _syncModeForCurrentTab(force: true);
    await ChafonH103RfidService.getBatteryLevel();
  }

  Future<void> _syncModeForCurrentTab({bool force = false}) async {
    if (!mounted) return;

    final index = _tabController.index;

    if (_isBarcodeTab(index)) {
      await _setBarcodeMode(force: force, updateLog: false);
      return;
    }

    if (_isRfidTab(index)) {
      await _setRfidMode(force: force, updateLog: false);
      return;
    }

    // Settings: conservar estado previo
    await _refreshReadMode();
  }

  Future<void> _setBarcodeMode({
    bool force = false,
    bool updateLog = true,
  }) async {
    if (_isChangingMode) return;
    if (!force && currentReadMode == 'barcode') return;

    _isChangingMode = true;
    if (mounted) setState(() => isBarcodeBusy = true);

    try {
      final result = await ChafonH103RfidService.setBarcodeMode();
      await _refreshReadMode();

      if (!mounted) return;
      if (updateLog) {
        setState(() {
          log = '📷 Barcode mode: $result';
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error enabling barcode mode: $e')),
      );
    } finally {
      _isChangingMode = false;
      if (mounted) setState(() => isBarcodeBusy = false);
    }
  }

  Future<void> _setRfidMode({
    bool force = false,
    bool updateLog = true,
  }) async {
    if (_isChangingMode) return;
    if (!force && currentReadMode == 'rfid') return;

    _isChangingMode = true;
    if (mounted) setState(() => isBarcodeBusy = true);

    try {
      final result = await ChafonH103RfidService.setRfidMode();
      await _refreshReadMode();

      if (!mounted) return;
      if (updateLog) {
        setState(() {
          log = '🏷️ RFID mode: $result';
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error switching to RFID mode: $e')),
      );
    } finally {
      _isChangingMode = false;
      if (mounted) setState(() => isBarcodeBusy = false);
    }
  }

  Future<void> loadDeviceConfig() async {
    setState(() => isLoading = true);
    try {
      final config = await ChafonH103RfidService.getAllDeviceConfig();
      setState(() {
        outputPower = (config['power'] ?? 20).clamp(5, 33);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to get device configuration: $e")),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> sendConfigToDevice() async {
    final power = _normalizePower(outputPower);
    try {
      final result = await ChafonH103RfidService.setOnlyOutputPower(
        power: power,
        saveToFlash: true,
        resumeInventory: false,
        region: 2,
      );

      if (!mounted) return;
      if (result == "flash_saved" || result == "ok" || result == "params_saved_to_flash") {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Parameters saved (FLASH)"), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Parameters not written: $result"), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  void _recordBarcode(String value) {
    final now = DateTime.now();

    if (_lastBarcodeDedupValue == value &&
        _lastBarcodeDedupAt != null &&
        now.difference(_lastBarcodeDedupAt!).inMilliseconds <= 500) {
      return;
    }

    _lastBarcodeDedupValue = value;
    _lastBarcodeDedupAt = now;

    SystemSound.play(SystemSoundType.click);

    setState(() {
      lastBarcodeValue = value;
      barcodeHistory.insert(0, {
        'value': value,
        'time': now,
      });

      if (barcodeHistory.length > 100) {
        barcodeHistory.removeRange(100, barcodeHistory.length);
      }
    });
  }

  Future<void> _stopBarcodeIfActiveSilently() async {
    if (!isBarcodeTriggerActive && currentReadMode != 'barcode') {
      return;
    }

    try {
      await ChafonH103RfidService.stopBarcodeScan();
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      isBarcodeTriggerActive = false;
    });
  }

  Future<void> _startBarcodeScan() async {
    setState(() => isBarcodeBusy = true);
    try {
      if (currentReadMode != 'barcode') {
        await ChafonH103RfidService.setBarcodeMode();
      }

      final result = await ChafonH103RfidService.startBarcodeScan();
      await _refreshReadMode();

      if (!mounted) return;
      setState(() {
        log = '▶️ Barcode scan started: $result';
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error starting barcode scan: $e')),
      );
    } finally {
      if (mounted) setState(() => isBarcodeBusy = false);
    }
  }

  void _clearBarcodeHistory() {
    setState(() {
      barcodeHistory.clear();
      lastBarcodeValue = 'No barcode read';
      _lastBarcodeDedupValue = null;
      _lastBarcodeDedupAt = null;
    });
  }

  Future<void> _goToDeviceScan() async {
    if (_isNavigatingAway || !mounted) return;
    _isNavigatingAway = true;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const DeviceScanScreen()),
      (route) => false,
    );
  }

  void _handleTabChanged() {
    if (!mounted) return;
    if (_tabController.indexIsChanging) return;
    _syncModeForCurrentTab();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(_handleTabChanged);

    _initializeScreen();

    ChafonH103RfidService.initCallbacks(
      onTagRead: (tag) {
        final epc = tag['epc'];
        final rssi = tag['rssi'];

        setState(() {
          if (tagMap.containsKey(epc)) {
            tagMap[epc]!['count'] += 1;
            tagMap[epc]!['rssi'] = rssi;
            tagMap[epc]!['lastSeen'] = DateTime.now();
          } else {
            tagMap[epc] = {
              'count': 1,
              'rssi': rssi,
              'lastSeen': DateTime.now(),
            };
          }
        });
      },
      onTagReadSingle: (tag) {
        final status = tag['status'] ?? -1;
        final epc = tag['epc']?.toString() ?? '';
        final data = tag['data']?.toString() ?? '';

        if (data.trim().isEmpty) return;

        setState(() {
          lastTagInfo = 'Single tag read:\nEPC: ${epc.isEmpty ? "<empty>" : epc}\nData: $data\nStatus: $status';
        });
      },
      onRadarResult: (tag) {
        final epc = tag['epc']?.toString() ?? '';
        final rssi = tag['rssi'] ?? -99;
        _handleRadar(epc, rssi);
      },
      onBatteryLevel: (map) {
        final level = map['level'];
        setState(() {
          batteryLevel = level;
        });
      },
      onBatteryTimeout: () {
        setState(() {
          log = '⏰ Battery read timeout';
        });
      },
      onBarcodeRead: (barcode) {
        final value = barcode['value']?.toString().trim() ?? '';
        if (value.isEmpty) return;
        _recordBarcode(value);
      },
      onKeyState: (state) {
        final keyState = state['state']?.toString() ?? '';
        setState(() {
          isBarcodeTriggerActive = keyState == 'start';
        });
      },
      onReadError: (map) {
        final error = map['error']?.toString() ?? 'Unknown error';
        setState(() {
          log = '❌ $error';
        });
      },
      onDisconnected: () async {
        await _goToDeviceScan();
      },
      onFlashSaved: () {},
    );
  }

  @override
  void dispose() {
    epcController.dispose();
    maskStartController.dispose();
    maskLengthController.dispose();
    maskHexController.dispose();
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _startRadar() async {
    try {
      await _stopBarcodeIfActiveSilently();

      if (radarSearchMode == 'epc') {
        final epc = _normalizeHex(epcController.text);

        if (epc.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ingrese un EPC válido')),
          );
          return;
        }

        if (!_isValidHex(epc) || epc.length.isOdd) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('El EPC debe ser HEX válido y tener longitud par')),
          );
          return;
        }

        await ChafonH103RfidService.startRadar(epc);

        setState(() {
          isRadarActive = true;
          radarTarget = epc;
          radarProgress = 0;
          radarColor = Colors.grey;
          lastRadarEpc = '';
          log = '🎯 Radar EPC iniciado';
        });
      } else {
        final startText = maskStartController.text.trim();
        final lengthText = maskLengthController.text.trim();
        final mask = _normalizeHex(maskHexController.text);

        if (startText.isEmpty || lengthText.isEmpty || mask.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Complete Start Address, Length y Mask')),
          );
          return;
        }

        final int? maskStartAddress = int.tryParse(startText);
        final int? maskLength = int.tryParse(lengthText);

        if (maskStartAddress == null || maskLength == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Start Address y Length deben ser numéricos')),
          );
          return;
        }

        if (maskStartAddress < 0 || maskStartAddress > 31) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Mask Start Address debe estar entre 0 y 31')),
          );
          return;
        }

        if (maskLength < 0 || maskLength > 31) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Mask Length debe estar entre 0 y 31')),
          );
          return;
        }

        if (!_isValidHex(mask) || mask.length.isOdd) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Mask debe ser HEX válido y tener longitud par')),
          );
          return;
        }

        if (mask.length != maskLength * 2) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Mask Length está en bytes. Debe coincidir con ${maskLength * 2} caracteres HEX.',
              ),
            ),
          );
          return;
        }

        await ChafonH103RfidService.startRadarMasked(
          maskStartAddress: maskStartAddress,
          maskLength: maskLength,
          mask: mask,
        );

        setState(() {
          isRadarActive = true;
          radarTarget = 'start=$maskStartAddress len=$maskLength mask=$mask';
          radarProgress = 0;
          radarColor = Colors.grey;
          lastRadarEpc = '';
          log = '🎯 Radar por máscara iniciado';
        });
      }

      await _refreshReadMode();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al iniciar radar: $e')),
      );
    }
  }

  Future<void> _stopRadar() async {
    try {
      await ChafonH103RfidService.stopRadar();
      setState(() {
        isRadarActive = false;
        radarTarget = '';
        radarProgress = 0;
        radarColor = Colors.grey;
        lastRadarEpc = '';
        log = '🛑 Radar detenido';
      });
      await _refreshReadMode();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al detener radar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final powLabel = outputPower?.toString() ?? '...';

    return Scaffold(
      appBar: AppBar(
        title: const Text("Functions"),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.wifi), text: "Continuous Read"),
            Tab(icon: Icon(Icons.radio_button_checked), text: "Single read"),
            Tab(icon: Icon(Icons.radar), text: "Radar Search"),
            Tab(icon: Icon(Icons.qr_code_scanner), text: "Barcode"),
            Tab(icon: Icon(Icons.settings), text: "Settings"),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Text(
                batteryLevel != null ? "🔋 $batteryLevel%" : "🔋 ...",
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildContinuousInventoryTab(),
                _buildSingleReadTab(),
                _buildRadarTab(),
                _buildBarcodeTab(),
                _buildSettingsTab(powLabel),
              ],
            ),
    );
  }

  Widget _buildContinuousInventoryTab() {
    final tagEntries = tagMap.entries.toList();

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: tagEntries.length,
              itemBuilder: (_, index) {
                final epc = tagEntries[index].key;
                final data = tagEntries[index].value;

                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.nfc),
                    title: Text("EPC: $epc"),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("RSSI: ${data['rssi']} dBm"),
                        Text("Read Count: ${data['count']}"),
                        Text("Last Seen: ${data['lastSeen']}"),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text("Start"),
                onPressed: () async {
                  await _stopBarcodeIfActiveSilently();
                  final result = await ChafonH103RfidService.startInventory();
                  await _refreshReadMode();
                  setState(() {
                    log = '📡 Started: $result';
                  });
                },
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.cleaning_services_rounded),
                label: const Text("Clear"),
                onPressed: () => setState(() => tagMap.clear()),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.stop),
                label: const Text("Stop"),
                onPressed: () async {
                  final result = await ChafonH103RfidService.stopInventory();
                  setState(() {
                    log = '🛑 Stopped: $result';
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(log, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildSingleReadTab() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ElevatedButton.icon(
            icon: const Icon(Icons.radio_button_checked),
            label: const Text("Read Single Tag"),
            onPressed: () async {
              await _stopBarcodeIfActiveSilently();
              final bank = _memBankCode(selectedMemoryBank);
              await ChafonH103RfidService.readSingleTagFromBank(bank);
              await _refreshReadMode();
            },
          ),
          const SizedBox(height: 20),
          const Text("Read Result:", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(lastTagInfo, style: const TextStyle(fontSize: 14)),
          ),
          const SizedBox(height: 20),
          DropdownButton<String>(
            value: selectedMemoryBank,
            items: memoryBankOptions
                .map((bank) => DropdownMenuItem<String>(value: bank, child: Text("Memory Bank: $bank")))
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => selectedMemoryBank = value);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRadarTab() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('EPC Completo'),
                    value: 'epc',
                    groupValue: radarSearchMode,
                    onChanged: isRadarActive ? null : (val) => setState(() => radarSearchMode = val!),
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('Por Máscara'),
                    value: 'mask',
                    groupValue: radarSearchMode,
                    onChanged: isRadarActive ? null : (val) => setState(() => radarSearchMode = val!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (radarSearchMode == 'epc') ...[
              TextField(
                controller: epcController,
                enabled: !isRadarActive,
                decoration: const InputDecoration(
                  labelText: "EPC to Search",
                  border: OutlineInputBorder(),
                ),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: maskStartController,
                      enabled: !isRadarActive,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: "Mask Start Addr",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: maskLengthController,
                      enabled: !isRadarActive,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: "Mask Length",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: maskHexController,
                enabled: !isRadarActive,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-FxX\s]')),
                ],
                decoration: const InputDecoration(
                  labelText: "Mask (HEX)",
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 24),
            LinearProgressIndicator(
              value: radarProgress,
              minHeight: 20,
              color: radarColor,
              backgroundColor: Colors.grey,
            ),
            const SizedBox(height: 12),
            Text(
              "Objetivo: ${radarTarget.isEmpty ? '-' : radarTarget}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              "Detected EPC: $lastRadarEpc",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: isRadarActive ? null : _startRadar,
                  icon: const Icon(Icons.location_searching),
                  label: const Text("Start Radar"),
                ),
                ElevatedButton.icon(
                  onPressed: isRadarActive ? _stopRadar : null,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text("Stop Radar"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarcodeTab() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Current mode: ${currentReadMode.toUpperCase()}",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Trigger: ${isBarcodeTriggerActive ? "ACTIVE" : "IDLE"}",
                    style: TextStyle(
                      color: isBarcodeTriggerActive ? Colors.green : Colors.grey[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            "Last barcode:",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              lastBarcodeValue,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: isBarcodeBusy ? null : _startBarcodeScan,
                icon: const Icon(Icons.play_arrow),
                label: const Text("Start Scan"),
              ),
              ElevatedButton.icon(
                onPressed: _clearBarcodeHistory,
                icon: const Icon(Icons.cleaning_services),
                label: const Text("Clear"),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            "History (${barcodeHistory.length})",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: barcodeHistory.isEmpty
                ? const Center(
                    child: Text('No barcode read yet'),
                  )
                : ListView.separated(
                    itemCount: barcodeHistory.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, index) {
                      final item = barcodeHistory[index];
                      final value = item['value']?.toString() ?? '';
                      final time = item['time'] as DateTime?;

                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.qr_code),
                          title: Text(value),
                          subtitle: Text(
                            time != null ? 'Read at: ${_formatTime(time)}' : '',
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab(String powLabel) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("📶 Output Power ($powLabel dBm)", style: const TextStyle(fontWeight: FontWeight.bold)),
          Slider(
            value: (outputPower ?? 20).toDouble(),
            min: 5,
            max: 33,
            divisions: 28,
            label: '${outputPower?.toInt() ?? 20} dBm',
            onChanged: (value) => setState(() => outputPower = value.toInt()),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.save),
            label: const Text("Save Parameters"),
            onPressed: () async => await sendConfigToDevice(),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () async {
              await ChafonH103RfidService.getBatteryLevel();
            },
            child: const Text("🔋 Check Battery"),
          ),
          const SizedBox(height: 16),
          Text(log),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.link_off),
            label: const Text("Disconnect"),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await ChafonH103RfidService.disconnect();
              await _goToDeviceScan();
            },
          ),
        ],
      ),
    );
  }
}