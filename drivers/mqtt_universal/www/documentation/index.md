[copyright]: # "Copyright 2025 Finite Labs, LLC. All rights reserved."

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

The MQTT Universal driver is a comprehensive solution for integrating MQTT
devices and variables with Control4. It allows you to dynamically create relays,
contact sensors, buttons, and variables that sync with MQTT topics. Each item
can be configured with its own state and command topics, enabling flexible
integration with any MQTT-based system.

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
      - [Availability Settings](#availability-settings)
      - [Add Devices](#add-devices)
      - [Add Variables](#add-variables)
      - [Manage Items](#manage-items)
      - [Item Configuration](#item-configuration)
  - [Connections](#connections)
  - [Programming](#programming)
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

**Devices:**

- **Relays** - Create RELAY bindings for on/off control with state feedback
- **Contact Sensors** - Create CONTACT_SENSOR bindings for open/closed state
- **Buttons** - Publish press commands to MQTT topics

**Variables:**

- **String/Bool/Number/Float** - Create Control4 variables synced with MQTT
- **Temperature** - Create TEMPERATURE_VALUE bindings for thermostat integration
- **Humidity** - Create HUMIDITY_VALUE bindings for humidity sensor integration

**Common Features:**

- Global device availability monitoring via MQTT topic
- Device Available/Unavailable events for programming
- Configurable QoS and retain settings per item
- "Match one, default other" state parsing for flexible payload matching
- JSONPath extraction for nested JSON payloads
- All items persist across driver restarts

<div style="page-break-after: always"></div>

# <span style="color:#660066">Installer Setup</span>

## Driver Installation

1. Ensure the MQTT Broker driver is installed and connected.
2. Add the "MQTT Universal" driver to your project.
3. In the Connections tab, bind the MQTT Universal driver to the MQTT Broker.
4. Configure global availability settings (optional).
5. Add devices and variables, then configure their MQTT topics.

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

#### Availability Settings

These settings control global device availability for all items in the driver.

##### Availability Topic

The MQTT topic to subscribe for availability status (optional). When a message
is received, the driver will fire Device Available or Device Unavailable events.

##### Payload Available

The payload that indicates the device is available.

##### Payload Not Available

The payload that indicates the device is unavailable.

##### Availability Value Path

JSONPath expression to extract the availability value from a JSON payload. Leave
empty to use the raw payload. This property appears when Availability Topic is
configured.

Example: If your availability topic publishes `{"status": "online"}`, set this
to `$.status` to extract the `online` value.

##### Availability Value Path Result (read-only)

Shows the result of the JSONPath extraction, or an error message if extraction
failed. This property appears when both Availability Topic and Availability
Value Path are configured.

#### Add Devices

##### Add Relay

Enter a name to create a new relay. This creates a RELAY binding that can be
connected to other Control4 devices or used in programming. The relay supports
ON, OFF, TOGGLE, and TRIGGER commands.

##### Add Contact

Enter a name to create a new contact sensor. This creates a CONTACT_SENSOR
binding that reports OPEN or CLOSED state based on MQTT messages.

##### Add Button

Enter a name to create a new button. Buttons publish a configured payload to an
MQTT topic when triggered via the Press command.

#### Add Variables

##### Add String Variable

Enter a name to create a new STRING variable.

##### Add Bool Variable

Enter a name to create a new BOOL variable.

##### Add Number Variable

Enter a name to create a new NUMBER variable.

##### Add Float Variable

Enter a name to create a new FLOAT variable.

##### Add Temperature Variable

Enter a name to create a new TEMPERATURE variable. This creates a
TEMPERATURE_VALUE binding that can be connected to thermostats.

##### Add Humidity Variable

Enter a name to create a new HUMIDITY variable. This creates a HUMIDITY_VALUE
binding that can be connected to humidity sensors.

#### Manage Items

##### Remove Item

Select an item from the list to delete it. Format: `Name (TYPE) [ID]`

##### Configure Item

Select an item from the list to configure its MQTT settings. When selected, the
Item Configuration properties will appear below.

#### Item Configuration

These properties appear when an item is selected in "Configure Item". The
available properties depend on the item type and configured topics.

##### State Topic

The MQTT topic to subscribe for state updates.

##### Command Topic

The MQTT topic to publish commands to.

##### Relay-Specific Properties

These appear when a relay is selected:

- **Payload On** - Payload to send for ON command (default: `ON`)
- **Payload Off** - Payload to send for OFF command (default: `OFF`)
- **State On** - Payload indicating ON state (if only this is set, other values
  mean OFF)
- **State Off** - Payload indicating OFF state (if only this is set, other
  values mean ON)
- **Optimistic** - Update state immediately on command (Auto: yes if no State
  Topic)

##### Contact-Specific Properties

These appear when a contact is selected:

- **State Open** - Payload indicating OPEN state (default: `OPEN`)
- **State Closed** - Payload indicating CLOSED state (default: `CLOSED`)

##### Button-Specific Properties

These appear when a button is selected:

- **Payload Press** - Payload to send when pressed (default: `PRESS`)

##### JSONPath Properties

These properties appear when a State Topic is configured:

- **Value Path** - JSONPath expression to extract a value from a JSON payload.
  Leave empty to use the raw payload. Supports dot notation for nested fields
  and array indices.
- **Value Path Result** (read-only) - Shows the extracted value or an error
  message. Only appears when Value Path is configured.

**JSONPath Examples:**

| Payload                         | Value Path            | Result |
| ------------------------------- | --------------------- | ------ |
| `{"temperature": 72.5}`         | `$.temperature`       | `72.5` |
| `{"sensors": {"temp": 68}}`     | `$.sensors.temp`      | `68`   |
| `{"readings": [{"value": 42}]}` | `$.readings[0].value` | `42`   |
| `{"data": [10, 20, 30]}`        | `$.data[1]`           | `20`   |

##### Common Properties

These properties appear based on topic configuration:

- **QoS** - MQTT Quality of Service level (0, 1, or 2). Appears when State Topic
  or Command Topic is configured.
- **Retain** - Whether to retain published messages on the broker. Appears when
  Command Topic is configured.

##### Temperature-Specific Properties

- **Temperature Scale** - Scale of temperature values from MQTT: Celsius or
  Fahrenheit.

## Connections

When you add relays, contacts, or sensor variables, dynamic bindings are created
that appear in the Connections tab:

- **Relays** create RELAY bindings
- **Contacts** create CONTACT_SENSOR bindings
- **Temperature variables** create TEMPERATURE_VALUE bindings
- **Humidity variables** create HUMIDITY_VALUE bindings

These bindings can be connected to other Control4 devices (thermostats, security
panels, etc.) or used directly in programming.

### Programming

**Events:**

- **Device Available** - Fires when availability payload is received
- **Device Unavailable** - Fires when not-available payload is received

**Conditionals:**

- **Device Available** - Check if the device is available or unavailable

**Commands:**

- **Press** - Press a button by name (for button items)

**Variables:**

Variable-type items (STRING, BOOL, NUMBER, FLOAT, TEMPERATURE, HUMIDITY) create
Control4 variables that can be read in conditionals and written to trigger
publishing to the command topic.

<div style="page-break-after: always"></div>

<!-- #ifdef DRIVERCENTRAL -->

# <span style="color:#660066">Developer Information</span>

<p align="center">
<img alt="Finite Labs" src="./images/finite-labs-logo.png" width="400"/>
</p>

Copyright 2025 Finite Labs LLC

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
