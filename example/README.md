# Tabris.js Network Diagnostics Plugin Example

## Build for the simulator

```bash
./build.sh
```

Copies the example to a temporary directory, rewrites the plugin reference
`spec="../"` to the absolute plugin path (Cordova cannot install a plugin from
a parent directory) and runs `tabris build ios --emulator --debug`. The last
output line is `APP_PATH=<path to the built .app>`.

## Install and launch on a simulator

```bash
../scripts/example-simulator.sh "<APP_PATH>" <simulator-udid>
```

Installs the app, launches it with the console attached and writes the console
log and a screenshot to `/tmp/claude/`.
