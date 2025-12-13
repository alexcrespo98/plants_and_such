# ESP32-C6 Plant Moisture Monitoring System

Arduino code for the Seeed Studio XIAO ESP32C6 plant monitoring and automatic watering system.

## Features

### Core Monitoring
- **Soil Moisture Sensing**: Supports multiple capacitive moisture sensors
- **Environmental Monitoring**: DHT11/DHT22 temperature and humidity sensor
- **Web Interface**: Clean retro terminal aesthetic (green on black)
- **Real-time Updates**: Sensor data updates every 2 seconds

### Historical Data Tracking (NEW)
- **Two-Tier Storage System**:
  - **Detailed History**: 30-minute intervals for up to 7 days (336 data points)
  - **Compressed History**: 2-hour intervals for up to 30 days (360 data points)
- **Persistent Storage**: Data survives brief power outages using ESP32 Preferences
- **Interactive Graphs**: View historical temperature, humidity, and average soil moisture
- **Time Range Selector**: Switch between 24-hour, 7-day, and 30-day views

### Automatic Watering (NEW)
- **Configurable Schedule**: Set watering interval (1-48 hours) and duration (1-300 seconds)
- **Countdown Display**: Shows time until next automatic watering
- **Persistent Settings**: Configuration stored in EEPROM, survives reboots
- **Default Settings**: 12-hour interval, 20-second duration

### Manual Watering (NEW)
- **Custom Duration**: Specify watering duration (1-300 seconds, default 20)
- **Live Countdown**: Visual countdown timer while watering is active
- **Conflict Prevention**: Manual watering doesn't interfere with automatic schedule

## Hardware Requirements
- Seeed Studio XIAO ESP32C6
- DHT11 or DHT22 temperature/humidity sensor
- Capacitive soil moisture sensor(s)
- Relay module for pump control

## Memory Optimization
- Circular buffer implementation for efficient data storage
- Lightweight Chart.js for data visualization
- Optimized preferences storage to reduce flash wear
- Total memory footprint: ~10KB for historical data structures

## API Endpoints
- `GET /api/sensors` - Current sensor readings and watering status
- `GET /api/history` - Historical data (detailed and compressed)
- `GET /api/auto-water` - Automatic watering settings
- `POST /api/auto-water` - Update automatic watering settings
- `POST /api/manual-water` - Start manual watering with duration
- `POST /api/relay` - Direct relay control (legacy)

## Configuration
Edit the top of `ESP32c6_code.io` to configure:
- WiFi credentials
- Sensor pin assignments
- DHT sensor type
- Calibration values
