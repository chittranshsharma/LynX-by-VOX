import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  double? temperature;
  double? humidity;
  bool isConnected = false;
  DateTime? lastUpdate;

  // For tracking previous readings
  double? prevTemperature;
  double? prevHumidity;
  bool isStorm = false;
  String stormSeverity = 'Normal';
  String stormReason = '';
  List<String> stormHistory = [];
  List<double> tempHistory = [];
  List<double> humidityHistory = [];
  int consecutiveWarnings = 0;
  
  // Session tracking
  DateTime sessionStartTime = DateTime.now();
  int stormsAvoided = 0;
  int portsVisited = 0;
  double totalDistanceTraveled = 0.0;
  List<String> achievements = [];
  
  // Historical data for storm prediction
  List<Map<String, dynamic>> historicalReadings = [];
  
  // Debug mode
  bool debugMode = false;
  
  // Coordinate offset (in case ESP32 sends coordinates with offset)
  double latOffset = 0.0;
  double lngOffset = 0.0;
  
  // Emergency protocol checklist
  List<Map<String, dynamic>> emergencyChecklist = [
    {"task": "Sound ship's horn (3 long blasts)", "completed": false},
    {"task": "Turn on navigation lights", "completed": false},
    {"task": "Broadcast MAYDAY on VHF Channel 16", "completed": false},
    {"task": "Activate emergency position beacon", "completed": false},
    {"task": "Prepare lifeboats for deployment", "completed": false},
    {"task": "Inform all crew members", "completed": false},
  ];

  // Absolute limits - Very conservative for room conditions
  static const double TEMP_LIMIT_LOW = -10.0;   // Extremely cold
  static const double TEMP_LIMIT_HIGH = 50.0;   // Extremely hot
  static const double HUMIDITY_LIMIT = 98.0;    // Near saturation
  // Rapid change thresholds - Much less sensitive
  static const double TEMP_DROP_THRESHOLD = 10.0;  // sudden drop in °C
  static const double HUMIDITY_RISE_THRESHOLD = 25.0; // sudden rise in %

  final String esp32IP = '192.168.4.1';
  LatLng myLocation = const LatLng(28.247528, 76.813625);
  final MapController mapController = MapController();

  List<Map<String, dynamic>> ports = [
    {"name": "Mumbai Port", "location": const LatLng(18.9483, 72.8402)},
    {"name": "Chennai Port", "location": const LatLng(13.0827, 80.2785)},
    {"name": "Kolkata Port", "location": const LatLng(22.5396, 88.3130)},
    {"name": "Jawaharlal Nehru Port", "location": const LatLng(18.9467, 72.9530)},
    {"name": "Visakhapatnam Port", "location": const LatLng(17.6868, 83.2185)},
    {"name": "Cochin Port", "location": const LatLng(9.9667, 76.2667)},
    {"name": "Paradip Port", "location": const LatLng(20.3167, 86.6167)},
    {"name": "Mormugao Port", "location": const LatLng(15.4167, 73.8000)},
    {"name": "Tuticorin Port", "location": const LatLng(8.7832, 78.1348)},
  ];
  Map<String, dynamic>? nearestPort;
  Timer? autoRefreshTimer;
  Map<String, dynamic>? selectedSafePort;
  String shipName = 'MV Atlantic Star';
  String shipId = 'MVAT-2024';
  double shipSpeedKnots = 0.0;
  LatLng? _lastLocation;
  DateTime? _lastUpdateTime;

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
            
            // Add to historical readings for storm prediction
            if (temperature != null && humidity != null) {
              historicalReadings.add({
                'timestamp': DateTime.now(),
                'temperature': temperature!,
                'humidity': humidity!,
              });
              if (historicalReadings.length > 20) {
                historicalReadings.removeAt(0); // Keep last 20 readings
              }
            }
            // Always use hardcoded coordinates instead of ESP32 coordinates
            // Hardcoded coordinates: Latitude: 28.247528, Longitude: 76.813625
            LatLng newLocation = const LatLng(28.247528, 76.813625);
            
            if (debugMode) {
              print('Using hardcoded coordinates: ${newLocation.latitude}, ${newLocation.longitude}');
              if (data['latitude'] != null && data['longitude'] != null) {
                print('ESP32 sent coordinates but ignoring them: lat=${data['latitude']}, lng=${data['longitude']}');
              }
            }
            
            // Calculate distance traveled (using hardcoded location)
            if (_lastLocation != null) {
              final Distance distance = const Distance();
              double distKm = distance(_lastLocation!, newLocation) / 1000;
              totalDistanceTraveled += distKm;
            }
            
            // Update speed calculation (using hardcoded location)
            if (_lastLocation != null && _lastUpdateTime != null) {
              final Distance distance = const Distance();
              double distMeters = distance(_lastLocation!, newLocation);
              double timeSec = lastUpdate!.difference(_lastUpdateTime!).inMilliseconds / 1000.0;
              if (timeSec > 0) {
                double speedMS = distMeters / timeSec;
                shipSpeedKnots = speedMS * 1.94384; // 1 m/s = 1.94384 knots
              }
            }
            
            _lastLocation = myLocation;
            _lastUpdateTime = lastUpdate;
            myLocation = newLocation;
            mapController.move(myLocation, mapController.camera.zoom);
            nearestPort = findNearestPort();

            // --- Smart storm detection logic ---
            isStorm = false;
            stormSeverity = 'Normal';
            stormReason = '';
            // Add to history
            if (temperature != null) tempHistory.add(temperature!);
            if (humidity != null) humidityHistory.add(humidity!);
            if (tempHistory.length > 5) tempHistory.removeAt(0);
            if (humidityHistory.length > 5) humidityHistory.removeAt(0);

            // 1. Absolute thresholds
            if ((temperature != null && temperature! < TEMP_LIMIT_LOW) ||
                (temperature != null && temperature! > TEMP_LIMIT_HIGH) ||
                (humidity != null && humidity! > HUMIDITY_LIMIT)) {
              isStorm = true;
              stormSeverity = 'Storm Detected';
              stormReason = 'Absolute threshold exceeded';
            }
            // 2. Rapid change
            if (temperature != null && humidity != null && prevTemperature != null && prevHumidity != null) {
              double tempDrop = prevTemperature! - temperature!;
              double humidityRise = humidity! - prevHumidity!;
              if (tempDrop >= TEMP_DROP_THRESHOLD && humidityRise >= HUMIDITY_RISE_THRESHOLD) {
                isStorm = true;
                stormSeverity = 'Storm Likely';
                stormReason = 'Rapid temp drop + humidity rise';
              }
            }
            // 3. Trend analysis (steady drop/rise) - Very conservative
            if (tempHistory.length == 5 && humidityHistory.length == 5) {
              // Check for very significant drops/rises only
              double tempDrop = tempHistory[0] - tempHistory[4];
              double humidityRise = humidityHistory[4] - humidityHistory[0];
              if (tempDrop >= 15.0 && humidityRise >= 40.0) {
                isStorm = true;
                stormSeverity = 'Warning';
                stormReason = 'Significant temp drop & humidity rise';
              }
            }
            // 4. Rate of change (per minute)
            if (prevTemperature != null && prevHumidity != null && lastUpdate != null && _lastUpdateTime != null) {
              double timeMin = lastUpdate!.difference(_lastUpdateTime!).inMilliseconds / 60000.0;
              if (timeMin > 0) {
                double tempRate = (temperature! - prevTemperature!) / timeMin;
                double humidityRate = (humidity! - prevHumidity!) / timeMin;
                if (tempRate.abs() > 15.0 || humidityRate.abs() > 30.0) {
                  isStorm = true;
                  stormSeverity = 'Warning';
                  stormReason = 'High rate of change';
                }
              }
            }
            // 5. Consecutive warnings - Require more consecutive readings
            if (isStorm) {
              consecutiveWarnings++;
            } else {
              consecutiveWarnings = 0;
            }
            if (consecutiveWarnings >= 3) {  // Increased from 2 to 3
              stormSeverity = 'Storm Detected';
            }
            
            // 6. Additional safety: Don't trigger storm if we don't have enough historical data
            if (tempHistory.length < 3 || humidityHistory.length < 3) {
              isStorm = false;
              stormSeverity = 'Normal';
              stormReason = '';
            }
            // Add to storm history
            if (isStorm) {
              String event = '[${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}] $stormSeverity: $stormReason';
              if (stormHistory.isEmpty || stormHistory.last != event) {
                stormHistory.add(event);
                if (stormHistory.length > 5) stormHistory.removeAt(0);
              }
            if (debugMode) {
              print('Storm Detection Debug:');
              print('  Temperature: $temperature°C, Humidity: $humidity%');
              print('  Storm Status: $isStorm, Severity: $stormSeverity');
              print('  Reason: $stormReason');
              print('  Consecutive Warnings: $consecutiveWarnings');
              print('  History Length: temp=${tempHistory.length}, humidity=${humidityHistory.length}');
            }
            }
            // Save current readings for next comparison
            prevTemperature = temperature;
            prevHumidity = humidity;
            // --- End smart storm detection ---
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

  // Storm prediction based on trends
  String getStormPrediction() {
    if (historicalReadings.length < 5) return "Insufficient data";
    
    // Analyze temperature trend
    double tempTrend = 0;
    double humidityTrend = 0;
    
    for (int i = 1; i < historicalReadings.length; i++) {
      tempTrend += historicalReadings[i]['temperature'] - historicalReadings[i-1]['temperature'];
      humidityTrend += historicalReadings[i]['humidity'] - historicalReadings[i-1]['humidity'];
    }
    
    tempTrend /= (historicalReadings.length - 1);
    humidityTrend /= (historicalReadings.length - 1);
    
    if (tempTrend < -1.0 && humidityTrend > 2.0) {
      return "Storm likely in 15-30 minutes";
    } else if (tempTrend < -0.5 && humidityTrend > 1.0) {
      return "Weather deteriorating";
    } else {
      return "Conditions stable";
    }
  }

  // Get route polyline points
  List<LatLng> getRoutePoints() {
    if (selectedSafePort == null) return [];
    return [myLocation, selectedSafePort!["location"]];
  }

  List<Map<String, dynamic>> getNearestPorts(int count) {
    final Distance distance = const Distance();
    List<Map<String, dynamic>> sorted = List.from(ports);
    sorted.sort((a, b) => distance(myLocation, a["location"]).compareTo(distance(myLocation, b["location"])));
    return sorted.take(count).toList();
  }

  // Helper to check if a port is safe (for demo, use storm status)
  bool isPortSafe(Map<String, dynamic> port) {
    // For demo, if storm is detected, mark nearest port as unsafe
    if (!isStorm) return true;
    if (nearestPort != null && port["name"] == nearestPort!["name"]) return false;
    return true;
  }

  // Helper to get the next safest port
  Map<String, dynamic>? getNextSafePort() {
    final nearestPorts = getNearestPorts(3);
    for (var port in nearestPorts) {
      if (isPortSafe(port)) return port;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1929),
      body: Stack(
        children: [
          Row(
            children: [
              // Left Navigation
              Container(
                width: 250,
                color: const Color(0xFF162635),
            child: Column(
              children: [
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.computer, color: Color(0xFF4ECDC4)),
                        SizedBox(width: 8),
                        Text('LynX', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF4ECDC4))),
                      ],
                    ),
                    const SizedBox(height: 32),
                    _navButton(Icons.dashboard, 'DASHBOARD', 'Command Center'),
                    _navButton(Icons.anchor, 'SAFE PORT', 'Port Recommendations'),
                    _navButton(Icons.warning, 'EMERGENCY', 'Crisis Management'),
                    _navButton(Icons.history, 'LOGS', 'Navigation History'),
                    _navButton(Icons.settings, 'SETTINGS', 'System Configuration'),
                    const Spacer(),
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('AI CORE ONLINE\nAll systems nominal', style: TextStyle(color: Color(0xFF00FF9D), fontSize: 13)),
                    ),
                  ],
                ),
              ),
              // Main Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Storm banner
                      stormBanner(),
                      
                      // Mini weather trend charts
                      if (historicalReadings.length >= 3)
                        Container(
                          height: 60,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Temperature Trend', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                    Expanded(
                                      child: CustomPaint(
                                        painter: TrendPainter(
                                          data: historicalReadings.map((r) => r['temperature'] as double).toList(),
                                          color: Colors.orange,
                                        ),
                                        size: const Size(double.infinity, 30),
                                      ),
                                    ),
                                  ],
                                ),
          ),
          const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Humidity Trend', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                    Expanded(
                                      child: CustomPaint(
                                        painter: TrendPainter(
                                          data: historicalReadings.map((r) => r['humidity'] as double).toList(),
                                          color: Colors.blue,
                                        ),
                                        size: const Size(double.infinity, 30),
                                      ),
                                    ),
                                  ],
                                ),
          ),
        ],
      ),
                        ),
                      
                      const SizedBox(height: 8),
                      
                      // Live Temperature & Humidity Row
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
      ),
            child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
              children: [
                                  const Icon(Icons.thermostat, color: Colors.orange, size: 28),
                                  const SizedBox(width: 8),
                                  Text(
                                    temperature != null ? '${temperature!.toStringAsFixed(1)} °C' : '-- °C',
                                    style: const TextStyle(fontSize: 18, color: Colors.orange, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.water_drop, color: Colors.blue, size: 28),
                const SizedBox(width: 8),
                                  Text(
                                    humidity != null ? '${humidity!.toStringAsFixed(1)} %' : '-- %',
                                    style: const TextStyle(fontSize: 18, color: Colors.blue, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('Navigation Chart', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
          Expanded(
                        child: FlutterMap(
                          mapController: mapController,
                  options: MapOptions(
                            initialCenter: myLocation,
                            initialZoom: 6.0,
                            minZoom: 3.0,
                            maxZoom: 18.0,
                            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                      subdomains: const ['a', 'b', 'c'],
                    ),
                            // Route polyline
                            if (selectedSafePort != null)
                              PolylineLayer(
                                polylines: [
                                  Polyline(
                                    points: getRoutePoints(),
                                    strokeWidth: 3.0,
                                    color: Colors.cyanAccent,
                                  ),
                                ],
                              ),
                            MarkerLayer(
                              markers: [
                                // Ship marker
                                Marker(
                                  point: myLocation,
                                  width: 40,
                                  height: 40,
                                  child: const Icon(Icons.directions_boat, color: Colors.blue, size: 35),
                                ),
                                // Ports
                                ...ports.map((port) => Marker(
                                      point: port["location"],
                                      width: 40,
                                      height: 40,
                                      child: Icon(
                                        Icons.anchor,
                                        color: selectedSafePort != null && port["name"] == selectedSafePort!["name"] ? Colors.amber : (nearestPort != null && port["name"] == nearestPort!["name"] ? Colors.green : Colors.red),
                                        size: 30,
                                      ),
                                    )),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (nearestPort != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          color: Colors.black.withOpacity(0.2),
                          child: Column(
                            children: [
              Text(
                "Ship Coordinates: ${myLocation.latitude.toStringAsFixed(4)}, ${myLocation.longitude.toStringAsFixed(4)}",
                style: const TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.bold),
              ),
              Text(
                "Data Source: ${isConnected ? 'ESP32 Live' : 'Default Location'}",
                style: TextStyle(fontSize: 12, color: isConnected ? Colors.greenAccent : Colors.orange),
              ),
                              const SizedBox(height: 4),
                              Text(
                                "Nearest Port: ${nearestPort!["name"]} | Coordinates: ${nearestPort!["location"].latitude.toStringAsFixed(4)}, ${nearestPort!["location"].longitude.toStringAsFixed(4)}",
                                style: const TextStyle(fontSize: 15, color: Colors.greenAccent, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
                ),
              ),
            ],
          ),
          // Floating Speed UI (read-only)
          Positioned(
            bottom: 32,
            right: 32,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
                color: Colors.blueGrey.shade900.withOpacity(0.95),
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
      ),
      child: Row(
                mainAxisSize: MainAxisSize.min,
        children: [
                  const Icon(Icons.speed, color: Colors.cyanAccent, size: 28),
                  const SizedBox(width: 10),
                  Text(
                    shipSpeedKnots.isNaN ? '-- knots' : '${shipSpeedKnots.toStringAsFixed(2)} knots',
                    style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget stormBanner() {
    final nearestIsUnsafe = isStorm && nearestPort != null && !isPortSafe(nearestPort!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          color: stormSeverity == 'Storm Detected' ? Colors.red : stormSeverity == 'Storm Likely' ? Colors.orange : stormSeverity == 'Warning' ? Colors.amber : Colors.green,
          padding: const EdgeInsets.all(8),
      child: Column(
        children: [
              Text(
                stormSeverity == 'Normal'
                    ? '✅ Conditions normal'
                    : '⚠️ $stormSeverity! $stormReason',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Prediction: ${getStormPrediction()}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              if (nearestIsUnsafe)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                    onPressed: () {
                      final saferPort = getNextSafePort();
                      if (saferPort != null) {
                        setState(() {
                          selectedSafePort = saferPort;
                        });
                      }
                    },
                    child: const Text('Redirect to Safer Port'),
                  ),
                ),
              ],
            ),
          ),
        if (stormHistory.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Storm History:', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                ...stormHistory.reversed.map((e) => Text(e, style: const TextStyle(color: Colors.white70, fontSize: 13))),
              ],
            ),
          ),
        ],
    );
  }

  Widget _navButton(IconData icon, String title, String subtitle, {bool highlight = false}) {
    if (title == 'FUTURE VISION') return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFF00FF9D).withOpacity(0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(icon, color: highlight ? const Color(0xFF00FF9D) : Colors.white),
        title: Text(title, style: TextStyle(color: highlight ? const Color(0xFF00FF9D) : Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: TextStyle(color: Colors.white54)),
        onTap: () {
          if (title == 'SAFE PORT') {
            _showSafePortDialog();
          } else if (title == 'SETTINGS') {
            _showSettingsDialog();
          } else if (title == 'LOGS') {
            _showComingSoonDialog(title);
          } else if (title == 'DASHBOARD') {
            _showSessionSummary(); // Changed to show session summary
          } else if (title == 'EMERGENCY') {
            _showEmergencyDialog(); // Changed to show emergency protocol
          }
        },
      ),
    );
  }

  void _showSafePortDialog() {
    final nearestPorts = getNearestPorts(3);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF162635),
          title: const Text('Nearest Safe Ports', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: nearestPorts.map((port) {
              final Distance distance = const Distance();
              final distKm = distance(myLocation, port["location"]) / 1000;
              final etaHours = (shipSpeedKnots > 0.1) ? (distKm / (shipSpeedKnots * 1.852)) : null; // 1 knot = 1.852 km/h
              final isSelected = selectedSafePort != null && selectedSafePort!["name"] == port["name"];
              final isRecommended = port == nearestPorts.first;
              final facilities = port["facilities"] ?? ["Fuel", "Repair", "Supplies"];
              final safety = port["safety"] ?? 90;
              return Card(
                color: isSelected ? Colors.green.withOpacity(0.15) : Colors.white10,
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(port["name"], style: TextStyle(color: isSelected ? Colors.greenAccent : Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                          if (isRecommended)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(12)),
                              child: const Text('Recommended', style: TextStyle(color: Colors.white, fontSize: 12)),
                            ),
                          if (isSelected)
                            const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Icon(Icons.check_circle, color: Colors.greenAccent),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('Lat: ${port["location"].latitude.toStringAsFixed(4)}, Lng: ${port["location"].longitude.toStringAsFixed(4)}', style: const TextStyle(color: Colors.white70)),
                      Text('Distance: ${distKm.toStringAsFixed(2)} km', style: const TextStyle(color: Colors.white70)),
                      Text('ETA: ${etaHours != null ? etaHours.toStringAsFixed(2) + ' h' : '--'}', style: const TextStyle(color: Colors.white70)),
                      Row(
                        children: [
                          const Text('Facilities: ', style: TextStyle(color: Colors.white70)),
                          ...facilities.map<Widget>((f) => Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: Chip(label: Text(f, style: const TextStyle(fontSize: 11)), backgroundColor: Colors.blueGrey.shade700, labelStyle: const TextStyle(color: Colors.white)),
                              )),
                        ],
                      ),
                      Row(
                        children: [
                          const Text('Safety: ', style: TextStyle(color: Colors.white70)),
                          Text('$safety%', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                          onPressed: () {
                            setState(() {
                              selectedSafePort = port;
                            });
                            Navigator.of(context).pop();
                          },
                          child: const Text('Select This Port'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _showSettingsDialog() {
    final nameController = TextEditingController(text: shipName);
    final idController = TextEditingController(text: shipId);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF162635),
          title: const Text('Settings', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ship Name:', style: TextStyle(color: Colors.white70)),
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(hintText: 'Enter ship name', hintStyle: TextStyle(color: Colors.white54)),
              ),
              const SizedBox(height: 12),
              const Text('Ship ID:', style: TextStyle(color: Colors.white70)),
              TextField(
                controller: idController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(hintText: 'Enter ship ID', hintStyle: TextStyle(color: Colors.white54)),
              ),
              const SizedBox(height: 12),
              Text('Current Coordinates: ${myLocation.latitude.toStringAsFixed(4)}, ${myLocation.longitude.toStringAsFixed(4)}', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(
                    value: debugMode,
                    onChanged: (value) {
                      setState(() {
                        debugMode = value ?? false;
                      });
                    },
                    activeColor: Colors.blue,
                  ),
                  const Text('Debug Mode (Show Console Logs)', style: TextStyle(color: Colors.white70)),
                ],
              ),
              const SizedBox(height: 8),
              Text('Connection: ${isConnected ? 'Online' : 'Offline'}', style: TextStyle(color: isConnected ? Colors.greenAccent : Colors.redAccent)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  shipName = nameController.text;
                  shipId = idController.text;
                });
                Navigator.of(context).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _showComingSoonDialog(String title) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF162635),
          title: Text('$title', style: const TextStyle(color: Colors.white)),
          content: const Text('This feature is coming soon!', style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }


  // Emergency protocol dialog
  void _showEmergencyDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF162635),
          title: const Text('🚨 EMERGENCY PROTOCOL', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 400,
      child: Column(
              mainAxisSize: MainAxisSize.min,
              children: emergencyChecklist.map((item) {
                return CheckboxListTile(
                  title: Text(item["task"]!, style: const TextStyle(color: Colors.white)),
                  value: item["completed"],
                  onChanged: (bool? value) {
                    setState(() {
                      item["completed"] = value ?? false;
                    });
                  },
                  activeColor: Colors.red,
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () {
                // Reset checklist
                for (var item in emergencyChecklist) {
                  item["completed"] = false;
                }
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Reset Checklist'),
            ),
          ],
        );
      },
    );
  }

  // Session summary dialog
  void _showSessionSummary() {
    Duration sessionDuration = DateTime.now().difference(sessionStartTime);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF162635),
          title: const Text('📊 Session Summary', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
        children: [
              Text('Session Duration: ${sessionDuration.inHours}h ${sessionDuration.inMinutes % 60}m', style: const TextStyle(color: Colors.white)),
              Text('Distance Traveled: ${totalDistanceTraveled.toStringAsFixed(2)} km', style: const TextStyle(color: Colors.white)),
              Text('Storms Avoided: $stormsAvoided', style: const TextStyle(color: Colors.white)),
              Text('Ports Visited: $portsVisited', style: const TextStyle(color: Colors.white)),
              Text('Current Speed: ${shipSpeedKnots.toStringAsFixed(2)} knots', style: const TextStyle(color: Colors.white)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () {
                // Reset session
                setState(() {
                  sessionStartTime = DateTime.now();
                  stormsAvoided = 0;
                  portsVisited = 0;
                  totalDistanceTraveled = 0.0;
                  achievements.clear();
                });
                Navigator.of(context).pop();
              },
              child: const Text('Reset Session'),
            ),
          ],
        );
      },
    );
  }
}

// Custom painter for trend charts
class TrendPainter extends CustomPainter {
  final List<double> data;
  final Color color;

  TrendPainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final path = ui.Path();
    final minValue = data.reduce((a, b) => a < b ? a : b);
    final maxValue = data.reduce((a, b) => a > b ? a : b);
    final range = maxValue - minValue;

    if (range == 0) return;

    for (int i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * size.width;
      final y = size.height - ((data[i] - minValue) / range) * size.height;
      
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}