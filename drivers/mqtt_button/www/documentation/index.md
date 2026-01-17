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

# ⚠️ <span style="color:#cc0000">DEPRECATED</span>

> **This driver is deprecated.** Please use the **MQTT Universal** driver
> instead, which provides all the functionality of this driver plus additional
> features like conditionals, events, state variables, and support for multiple
> devices in a single driver instance.

---

# <span style="color:#660066">Overview</span>

<!-- #ifndef DRIVERCENTRAL -->

> DISCLAIMER: This software is neither affiliated with nor endorsed by either
> Control4 or MQTT.

<!-- #endif -->

The MQTT Button driver provides a simple way to trigger MQTT messages from
Control4 programming. When pressed, it publishes a configurable payload to an
MQTT topic. This is useful for triggering automations, scenes, or commands on
MQTT-connected devices.

# <span style="color:#660066">Index</span>

<div style="font-size: small">

- [System Requirements](#system-requirements)
- [Features](#features)
- [Installer Setup](#installer-setup)
  - [Driver Installation](#driver-installation)
  - [Driver Setup](#driver-setup)
    - [Driver Properties](#driver-properties)
      <!-- #ifdef DRIVERCENTRAL -->
      - [Cloud Settings](#cloud-settings)
      <!-- #endif -->
      - [Driver Settings](#driver-settings)
      - [MQTT Settings](#mqtt-settings)
  - [Driver Actions](#driver-actions)
  - [Programming Commands](#programming-commands)
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

# <span style="color:#660066">Features</span>

- Publish MQTT messages from Control4 programming
- Configurable command topic and payload
- Monitor device availability via availability topic
- Configurable QoS and retain settings

<div style="page-break-after: always"></div>

# <span style="color:#660066">Installer Setup</span>

## Driver Installation

1. Ensure the MQTT Broker driver is installed and connected.
2. Add the "MQTT Button" driver to your project.
3. In the Connections tab, bind the MQTT Button to the MQTT Broker.
4. Configure the MQTT topic and payload (see below).

## Driver Setup

### Driver Properties

<!-- #ifdef DRIVERCENTRAL -->

#### Cloud Settings

##### Cloud Status

Displays the DriverCentral cloud license status.

##### Automatic Updates

Turns on/off the DriverCentral cloud automatic updates.

<!-- #endif -->

#### Driver Settings

##### Driver Status (read-only)

Displays the current status of the driver.

##### Driver Version (read-only)

Displays the current version of the driver.

##### Log Level [ Fatal | Error | Warning | **_Info_** | Debug | Trace | Ultra ]

Sets the logging level. Default is `Info`.

##### Log Mode [ **_Off_** | Print | Log | Print and Log ]

Sets the logging mode. Default is `Off`.

#### MQTT Settings

##### Command Topic

The MQTT topic to publish the press command to. This is required.

##### Payload Press

The payload to send when the button is pressed. Default is `PRESS`.

##### Availability Topic

The MQTT topic to subscribe for device availability (optional). When configured,
the driver will show "Device unavailable" when the device goes offline.

##### Payload Available

The payload that indicates the device is available. Default is `online`.

##### Payload Not Available

The payload that indicates the device is unavailable. Default is `offline`.

##### QoS [ **_0_** | 1 | 2 ]

MQTT Quality of Service level for publishing. Default is `0`.

##### Retain [ Yes | **_No_** ]

Whether to set the retain flag on published command messages. Default is `No`.

### Driver Actions

##### Press

Press the button (publishes the payload to the command topic).

### Programming Commands

The following commands are available in Composer programming:

- **Press** - Press the button

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
