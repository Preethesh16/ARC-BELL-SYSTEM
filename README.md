# ARC-BELL-SYSTEM

## Overview

This project implements an **Automatic Bell System** using an ESP01S microcontroller (based on ESP8266) to control a relay that rings a bell. The system fetches schedules from a Firebase Realtime Database and triggers the bell at specified times. It also supports manual bell ringing via Firebase commands.

The system is designed for educational institutions (like colleges) where bells need to ring automatically for class timings, breaks, etc. It uses a department-based structure, allowing different schedules for different departments.

## Features

- **Automatic Scheduling**: Bell rings at predefined times stored in Firebase.
- **Multiple Modes**: Supports different schedule modes (e.g., regular, exam, holiday) that can be switched remotely.
- **Manual Trigger**: Allows manual bell ringing via Firebase database updates.
- **Real-time Clock**: Uses NTP (Network Time Protocol) for accurate time synchronization.
- **WiFi Connectivity**: Connects to WiFi for Firebase communication.
- **Relay Control**: Controls a physical relay to activate the bell circuit.
- **Department-based**: Configurable for different departments with unique schedules.

## Hardware Requirements

- **ESP01S Module**: A small WiFi-enabled microcontroller board based on ESP8266.
- **Relay Module**: A 5V relay to control the bell circuit (connected to GPIO 0).
- **Power Supply**: 3.3V for ESP01S, appropriate voltage for the relay.
- **Bell Circuit**: The relay connects to the bell's electrical circuit.
- **USB-to-Serial Adapter**: For programming the ESP01S (optional, for initial setup).

## Software Requirements

- **PlatformIO**: IDE for embedded development (used for building and uploading code).
- **Arduino Framework**: The code uses Arduino-style programming.
- **Libraries**:
  - `ESP8266WiFi`: For WiFi connectivity.
  - `Firebase_ESP_Client`: For interacting with Firebase Realtime Database.
  - `NTPClient`: For synchronizing time with NTP servers.

## Project Structure

```
esp01-relay/
├── platformio.ini          # PlatformIO configuration
├── src/
│   └── main.cpp            # Main application code
├── include/
│   └── secrets.h           # WiFi and Firebase credentials
├── lib/                    # Dependencies (managed by PlatformIO)
├── test/                   # Test files (if any)
└── README.md               # This file
```

## Setup Instructions

### 1. Install PlatformIO

If you haven't already, install PlatformIO in VS Code or as a standalone tool.

### 2. Clone or Download the Project

Place the project folder in your PlatformIO projects directory.

### 3. Configure Secrets

Edit `include/secrets.h` with your WiFi and Firebase details:

```cpp
#define WIFI_SSID "Your_WiFi_Name"
#define WIFI_PASSWORD "Your_WiFi_Password"
#define FIREBASE_LEGACY_TOKEN "Your_Firebase_Legacy_Token"
#define DATABASE_URL "Your_Firebase_Database_URL"
```

**Note**: Never commit `secrets.h` to version control. Keep it private.

### 4. Firebase Setup

- Create a Firebase project at [Firebase Console](https://console.firebase.google.com/).
- Enable Realtime Database.
- Generate a legacy database secret token.
- Set up the database structure as follows:

```
college-bell-system-26e92-default-rtdb
├── departments
│   └── icbs  # Department ID (configurable in code)
│       ├── mode: "regular"  # Current mode (e.g., "regular", "exam")
│       ├── manualRing: false  # Boolean for manual trigger
│       └── schedules
│           ├── regular
│           │   └── times: [480, 540, 600, ...]  # Minutes since midnight
│           └── exam
│               └── times: [480, 600, 720, ...]
```

Times are stored as minutes past midnight (e.g., 8:00 AM = 480 minutes).

### 5. Hardware Connections

- Connect the relay to GPIO 0 (pin 0) of ESP01S.
- Ensure the relay is powered appropriately (usually 5V).
- The relay should be normally open (NO) for the bell circuit.

### 6. Build and Upload

- Open the project in PlatformIO.
- Select the `esp01_1m` environment.
- Build the project.
- Upload to the ESP01S via USB-to-Serial adapter.

### 7. Monitor

Use PlatformIO's serial monitor to view debug output.

## How It Works

### Main Loop

The ESP01S runs a continuous loop that performs several checks at different intervals:

1. **Time Check (every 1 second)**: Updates NTP time, checks if current time matches any scheduled bell time.
2. **Mode Check (every 30 seconds)**: Polls Firebase for mode changes and reloads schedules if needed.
3. **Schedule Reload (every 60 seconds)**: Refreshes the schedule from Firebase to catch any updates.
4. **Manual Check (every 5 seconds)**: Checks for manual ring commands from Firebase.

### Bell Triggering

When a bell time is reached or manual trigger is activated:

- The relay pin is set LOW for 5 seconds (activating the bell).
- Then set back to HIGH.
- Prevents duplicate triggers in the same minute.

### Firebase Integration

- **Reading**: Fetches mode, schedules, and manual triggers.
- **Writing**: Resets manual trigger flag after activation.

## Code Explanation

### Key Components

- **WiFi Connection**: Connects to specified WiFi network.
- **Firebase Initialization**: Sets up connection to Realtime Database.
- **NTP Client**: Maintains accurate time (UTC+5:30 for Indian time).
- **Schedule Management**: Loads and stores bell times in an array.
- **Relay Control**: Simple digital output to control the relay.

### Important Variables

- `DEPARTMENT_ID`: Identifies the department (set to "icbs").
- `RELAY_PIN`: GPIO pin for relay (0).
- `scheduleTimes[]`: Array holding bell times in minutes.
- `lastLoadedMode`: Tracks current schedule mode.

### Functions

- `loadSchedule(mode)`: Fetches schedule from Firebase for given mode.
- `triggerBell(currentMinute)`: Activates relay and logs the event.

## Libraries Used

1. **ESP8266WiFi**: Handles WiFi connectivity for the ESP8266 chip.
2. **Firebase_ESP_Client**: Official Firebase library for ESP8266, supports Realtime Database operations.
3. **NTPClient**: Synchronizes device time with NTP servers for accurate scheduling.

## Techniques Used

- **IoT (Internet of Things)**: Device connects to internet for remote control and data fetching.
- **Real-time Database**: Firebase provides live data synchronization.
- **Time Synchronization**: NTP ensures accurate timing for schedules.
- **Polling Architecture**: Regularly checks Firebase for updates (not push-based due to ESP8266 limitations).
- **Embedded Programming**: Low-power microcontroller programming with Arduino framework.
- **Relay Control**: Digital output to control high-voltage circuits safely.
- **Error Handling**: Serial logging for debugging connectivity and data issues.

## Usage

1. **Power on the device**: It will connect to WiFi and Firebase automatically.
2. **Set mode in Firebase**: Change `/departments/icbs/mode` to switch schedules.
3. **Update schedules**: Modify times arrays in Firebase for different modes.
4. **Manual ring**: Set `/departments/icbs/manualRing` to `true` in Firebase to ring bell immediately.

## Troubleshooting

- **WiFi Connection Issues**: Check SSID/password in `secrets.h`, ensure signal strength.
- **Firebase Errors**: Verify database URL, legacy token, and internet connectivity.
- **Time Sync Problems**: Check NTP server reachability, adjust UTC offset if needed.
- **Relay Not Working**: Verify GPIO pin connection, relay power supply, and bell circuit.
- **Schedules Not Loading**: Check Firebase database structure and permissions.

## Future Improvements

- Implement push notifications instead of polling.
- Add more departments support.
- Include battery backup or power failure handling.
- Add web interface for easier schedule management.
- Implement logging of bell events to Firebase.

## Contributing

For juniors learning embedded systems and IoT:
- Start by understanding basic ESP8266 programming.
- Learn Firebase Realtime Database concepts.
- Experiment with relay modules and basic electronics.
- Practice time-based programming with NTP.

## License

This project is for educational purposes. Ensure compliance with local regulations for IoT devices and electrical installations.