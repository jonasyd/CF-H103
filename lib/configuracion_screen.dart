import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:convert';

import 'neo_types.dart';
import 'api_config.dart';

class ConfiguracionScreen extends StatefulWidget {
  const ConfiguracionScreen({super.key});

  @override
  State<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends State<ConfiguracionScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _depositsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargarConfiguracion();
  }

  // Carga la URL guardada al abrir la pantalla
  Future<void> _cargarConfiguracion() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _urlController.text =
          prefs.getString('backend_url') ??
          'https://dev.neoretail.com.ar/api/mobile/v1';

      // Si no hay nada guardado, mostramos el default como string para que el usuario vea el formato
      _depositsController.text =
          prefs.getString('deposits_list') ?? jsonEncode(defaultDepositOptions);
    });
  }

  // Guarda la nueva URL
  Future<void> _guardarConfiguracion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('backend_url', _urlController.text);
      await prefs.setString('deposits_list', _depositsController.text);

      // Actualizar memoria
      ApiConfig.setBaseUrl(_urlController.text);

      Iterable l = json.decode(_depositsController.text);
      List<DepositOption> list = List<DepositOption>.from(
        l.map((model) => DepositOption.fromJson(model)),
      );
      ApiConfig.setDeposits(list);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuración guardada correctamente')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error en el formato de depósitos: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Backend Endpoint',
                hintText: 'https://ejemplo.com/api',
                border: OutlineInputBorder(),
              ),
            ),
            // Añade este bloque para separar
            const SizedBox(height: 12.0),
            TextField(
              controller: _depositsController,
              maxLines: 5, // Para que sea cómodo editar el JSON
              decoration: const InputDecoration(
                labelText: 'Configuración de Depósitos (JSON)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _guardarConfiguracion,
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}
