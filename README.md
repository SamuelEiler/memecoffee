# MeCoffee

Open-source app for the [MeCoffee PID controller](https://www.me-company.nl/mecoffee/) on the Rancilio Silvia — Flutter (Android/iOS) + Python terminal client.

The original meBarista app is no longer maintained. This project replaces it with a modern, open-source alternative that connects over BLE and exposes the full parameter set of the MeCoffee PID kit.

---

## Features

- Live boiler temperature and setpoint display with chart
- PID power bar and raw P/I/D terms
- Set brew and steam temperature from the app
- Adjust PID P/I/D parameters
- Shot timer with configurable target time and vibration alert
- Auto-reconnect on disconnect
- Python terminal dashboard for scripting and debugging

---

## Repository layout

```
mecoffee/
├── app/        Flutter app (Android + iOS)
└── python/     Terminal dashboard (macOS / Linux)
```

---

## Flutter app

### Requirements

- Flutter 3.x
- Android 6+ or iOS 12+
- A Rancilio Silvia with the MeCoffee PID kit installed

### Run

```bash
cd app
flutter pub get
flutter run
```

The app scans for a BLE device whose name starts with `meCoffee`, connects automatically, and reconnects if the connection drops.

### Permissions

Android permissions are declared in `AndroidManifest.xml`:
- `BLUETOOTH_SCAN` (never for location)
- `BLUETOOTH_CONNECT`

No location permission is required on Android 12+.

---

## Python terminal client

### Requirements

- Python 3.10+
- A BLE adapter (built-in on most laptops)

### Setup

```bash
cd python
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### Run

```bash
python dashboard.py
```

The dashboard auto-discovers the MeCoffee device, displays live temperature, PID output, and device parameters, and lets you edit settings interactively.

---

## Protocol notes

The MeCoffee PID uses an HM-10 BLE UART module:

| UUID | Role |
|------|------|
| `0000ffe0-…` | Service |
| `0000ffe1-…` | Characteristic — notify + write-without-response |

Data is plain ASCII, `\r\n`-delimited. Commands **must** be prefixed with `\n` to flush the device's UART parser, e.g. `\ncmd dump OK\r\n`.

See [`app/lib/protocol.dart`](app/lib/protocol.dart) and [`python/protocol.py`](python/protocol.py) for the full parser and command builder.

---

## Contributing

Pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) if one exists, or open an issue to discuss changes first.

---

## License

MIT
