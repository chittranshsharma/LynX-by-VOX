# LynX Ai+IOT Maritime Navigation System

A comprehensive Flutter-based maritime navigation application that provides real-time weather monitoring, GPS tracking, storm detection, and port management for vessels at sea.

## Features

### Core Navigation
- **Real-time GPS Tracking**: Live vessel positioning using NEO-6M GPS module
- **Interactive Maritime Chart**: OpenStreetMap-based navigation with vessel and port markers
- **Speed Calculation**: Automatic speed computation in knots based on GPS coordinates
- **Distance Tracking**: Real-time calculation of traveled distance

### Weather Monitoring
- **DHT11 Integration**: Live temperature and humidity readings from ESP32
- **Storm Detection**: Advanced algorithm analyzing weather patterns for storm prediction
- **Trend Analysis**: Historical weather data visualization with trend charts
- **Weather Forecasting**: Predictive analytics for upcoming weather conditions

### Port Management
- **Nearest Port Detection**: Automatic identification of closest available ports
- **Safe Port Recommendations**: Real-time port safety assessment during storms
- **Route Planning**: Visual route display with polyline mapping to selected ports
- **Port Database**: Comprehensive database of major Indian ports with coordinates

### Safety Features
- **Emergency Protocol**: Interactive emergency checklist for crisis situations
- **Storm Alerts**: Real-time weather warnings with severity levels
- **Automatic Redirection**: Smart port redirection during hazardous conditions
- **Session Tracking**: Voyage statistics and performance metrics

## Hardware Requirements

- ESP32 Development Board
- DHT11 Temperature/Humidity Sensor
- NEO-6M GPS Module
- MicroSD Card Module (optional)
- Mobile device or laptop/pc with Flutter support

## Software Requirements

- Flutter SDK (>=3.0.0)
- Dart SDK (>=3.0.0)
- Android Studio / VS Code
- ESP32 Arduino Core

## Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  http: ^1.1.0
  flutter_map: ^6.0.1
  latlong2: ^0.8.1
```

## Installation

1. **Clone the repository**:
```bash
git clone https://github.com/chittranshsharma/LynX-by-VOX.git
cd LynX-by-VOX
```

2. **Install Flutter dependencies**:
```bash
flutter pub get
```

3. **Configure ESP32**:
   - Upload the companion Arduino code to your ESP32
   - Ensure ESP32 creates WiFi access point "LynX-ESP32"
   - Verify DHT11 sensor is connected to GPIO 4
   - Connect NEO-6M GPS module to appropriate UART pins

4. **Run the application**:
```bash
flutter run
```

## Configuration

### ESP32 Network Settings
The app expects the ESP32 to create a WiFi access point with:
- **SSID**: LynX-ESP32
- **Password**: vox45678
- **IP Address**: 192.168.4.1

### API Endpoint
The app fetches data from: `http://192.168.4.1/data`

Expected JSON response format:
```json
{
  "temperature": 25.30,
  "humidity": 60.20,
  "latitude": 28.247528,
  "longitude": 76.813625,
  "sd_available": true
}
```

## Usage

### Initial Setup
1. Power on the ESP32 system
2. Connect your mobile device to "LynX-ESP32" WiFi network
3. Launch the Flutter application
4. Wait for GPS lock and sensor initialization

### Navigation
- View real-time position on the interactive map
- Monitor current speed and distance traveled
- Track weather conditions via temperature and humidity displays
- Receive automatic storm warnings and safety recommendations

### Port Operations
- Access "SAFE PORT" from the navigation menu
- View nearest ports with distance, ETA, and facilities
- Select destination ports for route planning
- Get automatic redirection suggestions during storms

### Emergency Procedures
- Access "EMERGENCY" for crisis management protocols
- Follow the interactive emergency checklist
- Monitor storm history and severity levels
- Use session summary for voyage documentation

## Storm Detection Algorithm

The application uses a multi-factor storm detection system:

1. **Absolute Thresholds**: Temperature and humidity limits
2. **Rapid Change Detection**: Sudden weather pattern shifts
3. **Trend Analysis**: Historical data pattern recognition
4. **Rate of Change**: Minute-by-minute weather monitoring
5. **Consecutive Warnings**: Multi-reading confirmation system

### Storm Severity Levels
- **Normal**: Stable weather conditions
- **Warning**: Minor weather deterioration detected
- **Storm Likely**: High probability of storm development
- **Storm Detected**: Active storm conditions confirmed

## Port Database

The application includes major Indian ports:
- Mumbai Port
- Chennai Port
- Kolkata Port
- Jawaharlal Nehru Port
- Visakhapatnam Port
- Cochin Port
- Paradip Port
- Mormugao Port
- Tuticorin Port

Each port entry includes:
- Precise GPS coordinates
- Distance calculations from current position
- ETA estimations based on current speed
- Facility information
- Safety ratings

## System Architecture

```
┌─────────────────┐    WiFi     ┌─────────────────┐
│     ESP32       │◄────────────┤  Flutter App    │
│                 │             │                 │
│ • DHT11 Sensor  │    JSON     │ • Navigation    │
│ • NEO-6M GPS    │    Data     │ • Storm Alert   │
│ • WiFi AP       │◄────────────┤ • Port Manager  │
│ • Web Server    │             │ • Emergency     │
└─────────────────┘             └─────────────────┘
```

## Troubleshooting

### Common Issues

**App won't connect to ESP32:**
- Verify WiFi credentials match ESP32 configuration
- Check ESP32 is broadcasting "LynX-ESP32" network
- Ensure mobile device is connected to correct network

**No GPS data:**
- Verify NEO-6M wiring to ESP32
- Check GPS module has clear sky view
- Allow time for initial GPS fix (cold start can take 30+ seconds)

**Inaccurate weather readings:**
- Verify DHT11 sensor wiring
- Check sensor is not exposed to direct heat/moisture
- Ensure adequate power supply to ESP32

**Storm detection too sensitive:**
- Adjust threshold values in storm detection algorithm
- Increase consecutive warning requirements
- Modify trend analysis parameters

## Development

### Project Structure
```
lib/
├── main.dart
├── dashboard_page.dart
├── widgets/
│   └── trend_painter.dart
└── models/
    ├── port.dart
    └── weather_data.dart
```

### Adding New Ports
```dart
ports.add({
  "name": "New Port Name",
  "location": const LatLng(latitude, longitude),
  "facilities": ["Fuel", "Repair", "Supplies"],
  "safety": 95
});
```

### Customizing Storm Detection
Modify the storm detection thresholds in `_DashboardPageState`:
```dart
static const double TEMP_LIMIT_LOW = -10.0;
static const double TEMP_LIMIT_HIGH = 50.0;
static const double HUMIDITY_LIMIT = 98.0;
```

## Performance Optimization

- Data fetching occurs every 2 seconds to balance real-time updates with battery life
- Map rendering is optimized for smooth zooming and panning
- Historical data is limited to last 20 readings to manage memory usage
- GPS calculations use efficient distance algorithms

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/new-feature`)
3. Commit your changes (`git commit -am 'Add new feature'`)
4. Push to the branch (`git push origin feature/new-feature`)
5. Create a Pull Request

### Development Guidelines
- Follow Flutter/Dart style guidelines
- Add unit tests for new features
- Update documentation for API changes
- Test with actual hardware before submitting

## License

This project is licensed under the MIT License.

## Support

For issues, questions, or contributions:
- Create an issue on GitHub
- Check existing documentation
- Review troubleshooting section

## Changelog

### Version 1.0.0
- Initial release with core navigation features
- Real-time weather monitoring
- Storm detection system
- Port database integration
- Emergency protocols

## Acknowledgments

- Flutter team for the excellent framework
- OpenStreetMap contributors for maritime charts
- ESP32 community for hardware integration examples
