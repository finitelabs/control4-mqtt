[copyright]: # "Copyright 2026 Finite Labs, LLC. All rights reserved."

<style>
@media print {
   .noprint {
      visibility: hidden;
      display: none;
   }
   * {
        -webkit-print-color-adjust: exact;
        print-color-adjust: exact;
    }
}
</style>

<img alt="MQTT" src="./images/header.png" width="500"/>

---

# <span style="color:#660066">Overview</span>

<!-- #ifndef DRIVERCENTRAL -->

> DISCLAIMER: This software is neither affiliated with nor endorsed by either
> Control4 or MQTT.

<!-- #endif -->

The MQTT Bridge driver bridges Control4 devices to MQTT, allowing external
systems to monitor and control them. It publishes device state changes to MQTT
topics and subscribes to command topics for external control.

**Direction:** Control4 → MQTT (outbound state) and MQTT → Control4 (inbound
commands)

**Related Drivers:**

- **MQTT Broker** - Manages the connection to your MQTT broker
- **MQTT Universal** - For inbound-only MQTT integration (external devices →
  Control4)
- **MQTT Bridge** - For bridging C4 devices to MQTT (this driver)

# <span style="color:#660066">Index</span>

<div style="font-size: small">

- [System Requirements](#system-requirements)
- [Features](#features)
- [Topic Structure](#topic-structure)
- [Installer Setup](#installer-setup)
  <!-- #ifdef DRIVERCENTRAL -->
  - [DriverCentral Cloud Setup](#drivercentral-cloud-setup)
  <!-- #endif -->
  - [Driver Installation](#driver-installation)
  - [Driver Setup](#driver-setup)
    - [Driver Properties](#driver-properties)
- [Integration Examples](#integration-examples)
<!-- #ifdef DRIVERCENTRAL -->
- [Developer Information](#developer-information)
<!-- #endif -->
- [Support](#support)
- [Changelog](#changelog)

</div>

<div style="page-break-after: always"></div>

# <span style="color:#660066">System Requirements</span>

- Control4 OS 3.3+
- MQTT Broker driver installed and connected
- An MQTT broker accessible on the local network

# <span style="color:#660066">Features</span>

- Exposes Control4 lights to MQTT for external monitoring and control
- Publishes state changes in real-time as lights change
- Accepts commands from external systems to control lights
- Retained messages ensure external systems always have current state
- Uses C4-native scale (0-100) for brightness levels
- Publishes device metadata (name, room, type) for easy integration

<div style="page-break-after: always"></div>

# <span style="color:#660066">Topic Structure</span>

The driver uses the following topic structure (default prefix: `c4`):

```
{prefix}/light/{device_id}/state    # Published - current light state (retained)
{prefix}/light/{device_id}/command  # Subscribed - incoming commands
{prefix}/light/{device_id}/config   # Published - device metadata (retained)
```

## State Topic

Published whenever a light's state changes:

```json
{ "on": true, "level": 75 }
```

- `on` (boolean): Whether the light is on
- `level` (integer 0-100): Brightness level in C4-native scale

## Command Topic

Subscribe to control lights from external systems:

```json
{ "on": true, "level": 50 }
```

Supported commands:

- `{"on": true}` - Turn on at full brightness (100)
- `{"on": false}` - Turn off
- `{"level": 50}` - Set to specific level (0-100)
- `{"on": true, "level": 75}` - Turn on at specific level

## Config Topic

Published when a light is selected (retained):

```json
{
  "name": "Kitchen Main Light",
  "room": "Kitchen",
  "type": "dimmer"
}
```

- `name`: Device friendly name from Control4
- `room`: Room name from Control4
- `type`: "dimmer" (supports levels) or "switch" (on/off only)

<div style="page-break-after: always"></div>

# <span style="color:#660066">Installer Setup</span>

<!-- #ifdef DRIVERCENTRAL -->

## DriverCentral Cloud Setup

> If you already have the
> [DriverCentral Cloud driver](https://drivercentral.io/platforms/control4-drivers/utility/drivercentral-cloud-driver/)
> installed in your project you can continue to
> [Driver Installation](#driver-installation).

This driver relies on the DriverCentral Cloud driver to manage licensing and
automatic updates. If you are new to using DriverCentral you can refer to their
[Cloud Driver](https://help.drivercentral.io/407519-Cloud-Driver) documentation
for setting it up.

<!-- #endif -->

## Driver Installation

1. Ensure the **MQTT Broker** driver is installed and connected to your MQTT
   broker.

<!-- #ifdef DRIVERCENTRAL -->

2. Download the latest `control4-mqtt.zip` from
   [DriverCentral](https://drivercentral.io/platforms/control4-drivers/utility/mqtt).

<!-- #else -->

2. Download the latest `control4-mqtt.zip` from
   [Github](https://github.com/finitelabs/control4-mqtt/releases/latest).

<!-- #endif -->

3. Extract and install the `mqtt_bridge.c4z` driver.

4. Add the "MQTT Bridge" driver to your project from the Search tab.

   > ⚠️ Only **one** Bridge driver instance is needed - it manages multiple
   > devices.

5. The driver will automatically bind to the MQTT Broker driver.

## Driver Setup

### Driver Properties

#### Driver Settings

##### Driver Status (read-only)

Displays the current connection status.

##### Driver Version (read-only)

Displays the current version of the driver.

##### Log Level [ Fatal | Error | Warning | **_Info_** | Debug | Trace | Ultra ]

Sets the logging level. Default is `Info`.

##### Log Mode [ **_Off_** | Print | Log | Print and Log ]

Sets the logging mode. Default is `Off`.

#### MQTT Settings

##### Topic Prefix

The base topic prefix. Default: `c4`. The device type (e.g., `light`) is added
automatically.

Example: With prefix `c4` and device ID `123`, topics will be:

- `c4/light/123/state`
- `c4/light/123/command`
- `c4/light/123/config`

##### QoS [ **_0_** | 1 | 2 ]

MQTT Quality of Service level for all messages. Default is `0`.

#### Device Selection

##### Select Lights

Use the device selector to choose which lights to expose to MQTT. You can select
multiple lights. Selected lights will:

1. Have their state published to MQTT
2. Accept commands from MQTT
3. Publish their configuration (name, room, type)

<div style="page-break-after: always"></div>

# <span style="color:#660066">Integration Examples</span>

## Home Assistant

Subscribe to all light states:

```yaml
mqtt:
  sensor:
    - name: "C4 Light States"
      state_topic: "c4/light/+/state"
      value_template: "{{ value_json.level }}"
```

Control a light (device ID 123):

```yaml
mqtt:
  light:
    - name: "Kitchen Light"
      state_topic: "c4/light/123/state"
      command_topic: "c4/light/123/command"
      brightness_state_topic: "c4/light/123/state"
      brightness_command_topic: "c4/light/123/command"
      brightness_value_template: "{{ value_json.level }}"
      brightness_scale: 100
      on_command_type: "brightness"
      payload_on: '{"on": true}'
      payload_off: '{"on": false}'
      state_value_template: "{{ 'ON' if value_json.on else 'OFF' }}"
```

<div style="page-break-after: always"></div>

<!-- #ifdef DRIVERCENTRAL -->

# <span style="color:#660066">Developer Information</span>

<p align="center">
<img alt="Finite Labs" src="./images/finite-labs-logo.png" width="400"/>
</p>

Copyright © 2026 Finite Labs LLC

All information contained herein is, and remains the property of Finite Labs LLC
and its suppliers, if any. The intellectual and technical concepts contained
herein are proprietary to Finite Labs LLC and its suppliers and may be covered
by U.S. and Foreign Patents, patents in process, and are protected by trade
secret or copyright law. Dissemination of this information or reproduction of
this material is strictly forbidden unless prior written permission is obtained
from Finite Labs LLC. For the latest information, please visit
https://drivercentral.io/platforms/control4-drivers/utility/mqtt

<!-- #endif -->

# <span style="color:#660066">Support</span>

<!-- #ifdef DRIVERCENTRAL -->

If you have any questions or issues integrating this driver with Control4 or
MQTT, you can contact us at
[driver-support@finitelabs.com](mailto:driver-support@finitelabs.com) or
call/text us at [+1 (949) 371-5805](tel:+19493715805).

<!-- #else -->

If you have any questions or issues integrating this driver with Control4, you
can file an issue on GitHub:

https://github.com/finitelabs/control4-mqtt/issues/new

<a href="https://www.buymeacoffee.com/derek.miller" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

<!-- #endif -->

<div style="page-break-after: always"></div>

<!-- #embed-changelog -->
