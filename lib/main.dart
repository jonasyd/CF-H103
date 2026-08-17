//import 'dart:async';
//import 'dart:convert';

import 'package:flutter/material.dart';
//import 'package:http/http.dart' as http;

import 'configuracion_screen.dart';
import 'api_config.dart';
import 'stock_screen_real.dart';

// IMPORTS del ejemplo RFID
import 'rfid_example/device_scan_screen.dart';
import 'rfid_example/functions.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized(); // Obligatorio para SharedPreferences
  ApiConfig.init(); // Esperamos a que cargue los datos del disco
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Neo Retail Mobile',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Neo Retail Mobile'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  void _goToStockScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StockScreenReal()),
    );
  }

  void _goToConfigurationScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ConfiguracionScreen()),
    );
  }

  void _goToRfidExampleScan() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DeviceScanScreen()),
    );
  }

  void _goToRfidExampleFunctions() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const Functions()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            // Column is also a layout widget. It takes a list of children and
            // arranges them vertically. By default, it sizes itself to fit its
            // children horizontally, and tries to be as tall as its parent.
            //
            // Column has various properties to control how it sizes itself and
            // how it positions its children. Here we use mainAxisAlignment to
            // center the children vertically; the main axis here is the vertical
            // axis because Columns are vertical (the cross axis would be
            // horizontal).
            //
            // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
            // action in the IDE, or press "p" in the console), to see the
            // wireframe for each widget.
            children: [
              // Consulta de stock
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _goToStockScreen,
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Abrir consulta de stock'),
                ),
              ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _goToConfigurationScreen,
                  icon: const Icon(Icons.settings),
                  label: const Text('Abrir configuración'),
                ),
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _goToRfidExampleScan,
                  icon: const Icon(Icons.bluetooth_searching),
                  label: const Text('Probar ejemplo RFID: Device Scan'),
                ),
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _goToRfidExampleFunctions,
                  icon: const Icon(Icons.memory),
                  label: const Text('Probar ejemplo RFID: Functions'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
