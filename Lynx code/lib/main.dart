import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'constants.dart';
import 'dashboard.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Lynx Maritime AI System',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kDarkBlue,
        colorScheme: ColorScheme.dark(
          primary: kTealAccent,
          secondary: kNeonGreen,
        ),
        useMaterial3: true,
      ),
     home: const DashboardPage(),
    );
  }
}

class SensorMapPage extends StatefulWidget {
  const SensorMapPage({super.key});

  @override
  State<SensorMapPage> createState() => _SensorMapPageState();
}

class _SensorMapPageState extends State<SensorMapPage> {
  double? temperature;
  double? humidity;
  bool isConnected = false;
  DateTime? lastUpdate;

  final String esp32IP = '192.168.4.1'; // Replace with your ESP32 IP
  LatLng myLocation = const LatLng(28.247528, 76.813625);
  final MapController mapController = MapController();

  List<Map<String, dynamic>> ports = [
    {"name": "Mumbai Port", "location": const LatLng(18.9483, 72.8402)},
    {"name": "Jawaharlal Nehru Port", "location": const LatLng(18.9467, 72.9530)},
    {"name": "Chennai Port", "location": const LatLng(13.0827, 80.2785)},
    {"name": "Kolkata Port", "location": const LatLng(22.5396, 88.3130)},
    {"name": "Visakhapatnam Port", "location": const LatLng(17.6868, 83.2185)},
    {"name": "Cochin Port", "location": const LatLng(9.9667, 76.2667)},
    {"name": "Paradip Port", "location": const LatLng(20.3167, 86.6167)},
    {"name": "Mormugao Port", "location": const LatLng(15.4167, 73.8000)},
    {"name": "Tuticorin Port", "location": const LatLng(8.7832, 78.1348)},
  ];

  Map<String, dynamic>? nearestPort;
  Timer? autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    fetchData();
    autoRefreshTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      fetchData();
    });
  }

  @override
  void dispose() {
    autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> fetchData() async {
    try {
      final response = await http.get(
        Uri.parse('http://$esp32IP/data'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            temperature = (data['temperature'] as num?)?.toDouble();
            humidity = (data['humidity'] as num?)?.toDouble();
            isConnected = true;
            lastUpdate = DateTime.now();

            if (data['latitude'] != null && data['longitude'] != null) {
              myLocation = LatLng(
                (data['latitude'] as num).toDouble(),
                (data['longitude'] as num).toDouble(),
              );
              mapController.move(myLocation, mapController.camera.zoom);
            }

            nearestPort = findNearestPort();
          });
        }
      } else {
        if (mounted) setState(() => isConnected = false);
      }
    } catch (e) {
      if (mounted) setState(() => isConnected = false);
    }
  }

  Map<String, dynamic> findNearestPort() {
    final Distance distance = const Distance();
    Map<String, dynamic> nearest = ports.first;
    double minDist = distance(myLocation, ports.first["location"]);

    for (var port in ports) {
      double d = distance(myLocation, port["location"]);
      if (d < minDist) {
        minDist = d;
        nearest = port;
      }
    }
    return nearest;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Marine Dashboard"),
        backgroundColor: const Color(0xFF0D47A1), // deep marine blue
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Row(
              children: [
                Icon(
                  isConnected ? Icons.wifi : Icons.wifi_off,
                  color: isConnected ? Colors.greenAccent : Colors.redAccent,
                  size: 20,
                ),
                const SizedBox(width: 4),
                Text(
                  isConnected ? 'Connected' : 'Offline',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (lastUpdate != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              color: isConnected ? Colors.green.shade900 : Colors.red.shade900,
              child: Text(
                'Last Update: ${lastUpdate!.hour.toString().padLeft(2, '0')}:'
                '${lastUpdate!.minute.toString().padLeft(2, '0')}:'
                '${lastUpdate!.second.toString().padLeft(2, '0')}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: isConnected ? Colors.greenAccent : Colors.redAccent,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

          // Info Rectangles
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: _InfoRectangle(
                    title: "Temperature",
                    value: temperature != null
                        ? "${temperature!.toStringAsFixed(1)} °C"
                        : "--",
                    color: Colors.orange,
                    icon: Icons.thermostat,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _InfoRectangle(
                    title: "Humidity",
                    value: humidity != null
                        ? "${humidity!.toStringAsFixed(1)} %"
                        : "--",
                    color: Colors.cyan,
                    icon: Icons.water_drop,
                  ),
                ),
              ],
            ),
          ),

          // Marine Map
          Expanded(
            child: FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: myLocation,
                initialZoom: 5.5,
                minZoom: 3.0,
                maxZoom: 18.0,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.example.krishcontro',
                ),
                MarkerLayer(
                  markers: [
                    // Ship
                    Marker(
                      point: myLocation,
                      width: 50,
                      height: 50,
                      child: const Icon(
                        Icons.directions_boat,
                        color: Color(0xFF00E5FF), // neon cyan
                        size: 40,
                      ),
                    ),
                    // Ports
                    ...ports.map((port) => Marker(
                          point: port["location"],
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.anchor,
                            color: Color(0xFFFF1744), // neon red
                            size: 35,
                          ),
                        )),
                  ],
                ),
              ],
            ),
          ),

          // Info Box
          if (nearestPort != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              color: Colors.black54,
              child: Text(
                "Ship: ${myLocation.latitude.toStringAsFixed(4)}, ${myLocation.longitude.toStringAsFixed(4)}\n"
                "Nearest Port: ${nearestPort!['name']} - "
                "${nearestPort!['location'].latitude.toStringAsFixed(4)}, ${nearestPort!['location'].longitude.toStringAsFixed(4)}",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00E5FF), // neon cyan text
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Info Rectangle Widget (Dark theme)
class _InfoRectangle extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;

  const _InfoRectangle({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(153), // 0.6 * 255 ≈ 153
            blurRadius: 12,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "$title: $value",
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}