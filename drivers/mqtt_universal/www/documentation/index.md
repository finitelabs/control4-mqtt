<!-- Copyright 2026 Finite Labs, LLC. All rights reserved. -->

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

______________________________________________________________________

# <span style="color:#660066">Overview</span>

> DISCLAIMER: This software is neither affiliated with nor endorsed by either
> Control4 or MQTT.

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

# <span style="color:#660066">System Requirements</span>

- Control4 OS 3.3+
- MQTT Broker driver installed and connected

# <span style="color:#660066">Features</span>

**Devices:**

- **Relays** - Create RELAY bindings for on/off control with state feedback
- **Contact Sensors** - Create CONTACT_SENSOR bindings for open/closed state
- **Buttons** - Publish press commands to MQTT topics, with optional keypad
  linking
- **Events** - Create BUTTON_LINK bindings that trigger on MQTT messages, for
  keypad integration

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

# <span style="color:#660066">Installer Setup</span>

## Driver Installation

1. Ensure the MQTT Broker driver is installed and connected.
1. Add the "MQTT Universal" driver to your project.
1. In the Connections tab, bind the MQTT Universal driver to the MQTT Broker.
1. Configure global availability settings (optional).
1. Add devices and variables, then configure their MQTT topics.

## Driver Setup

### Driver Properties

<!-- #ifdef DRIVERCENTRAL -->

#### Cloud Settings

##### Cloud Status (read-only)

Displays the DriverCentral cloud license status.

##### Automatic Updates \[ Off | **_On_** \]

Turns on/off the DriverCentral cloud automatic updates. Changing it on any MQTT
Broker or MQTT Universal item changes it on all of them.

<!-- #endif -->

#### Driver Settings

##### Driver Status (read-only)

Displays the current status of the driver.

##### Driver Version (read-only)

Displays the current version of the driver.

##### Log Level \[ 0 - Fatal | 1 - Error | 2 - Warning | **_3 - Info_** | 4 - Debug | 5 - Trace | 6 - Ultra \]

Sets the logging level. Default is `3 - Info`.

##### Log Mode \[ **_Off_** | Print | Log | Print and Log \]

Sets the logging mode. Default is `Off`.

<!-- #ifdef DRIVERCENTRAL -->

##### Support Code

Leave it blank unless Finite Labs support gives you a code: it opens Composer's
Lua tab to this driver for an hour.

##### Cloud Monitoring \[ Disabled | **_Enabled_** \]

When Enabled, the driver sends Finite Labs a short report once an hour, and a
report of each error it hits, at most 10 a minute. We use them to find and fix
problems in the driver. Set it to Disabled to send nothing.

A report holds the controller's MAC address and OS version, the driver's name,
version, device ID and DriverCentral license status, how much memory the driver
uses, and the sizes of its largest internal tables. An error report also holds
the error message and where in the driver it happened. Before a message is sent,
anything in it that looks like a password, token, key, network address or email
address is removed.

The Diagnostics Snapshot action prints a report in the Lua output, and sends it
only while Cloud Monitoring is Enabled.

<!-- #endif -->

#### Availability Settings

These settings control global device availability for all items in the driver.

##### Availability Topic

The MQTT topic to subscribe for availability status (optional). When a message
is received, the driver will fire Device Available or Device Unavailable events.

##### Availability Topic Value (read-only)

Shows the raw payload received from the availability topic.

##### Availability Status (read-only)

Shows the current availability status (Available or Unavailable).

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

##### Add Event

Enter a name to create a new event. Events subscribe to MQTT topics and trigger
connected Control4 buttons/keypads when messages arrive.

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

These properties are shown only once the driver has at least one item. Each
entry in their lists reads `Name (TYPE) [ID]`.

##### Remove Item \[ **_(Select)_** | *added items...* \]

> ⚠️ Removing an item also removes its connection and the bindings made to it.
> Removing an event item also removes its event and the programming on it.

Selects an item to remove. The variables of a relay, contact, event, string,
bool, number or float item are removed with it.

##### Configure Item \[ **_(Select)_** | *added items...* \]

Selects an item to show its settings under
[Item Configuration](#item-configuration). A new item is selected here when you
add it.

#### Item Configuration

These properties are shown when an item is selected in
[Configure Item](#configure-item--select--added-items-). Which ones appear
depends on the item's type and on the topics it has.

##### State Topic

Shown for every item except a button. Sets the topic the item subscribes to for
its state or value.

##### State Topic Value (read-only)

Shown only when the item has a [State Topic](#state-topic). Displays the last
payload received on it.

##### Value Path

Shown only when the item has a [State Topic](#state-topic). Sets a JSONPath that
picks the value out of a JSON payload. Leave it empty to use the whole payload.
The item's other settings then work on the value it picks.

A path starts with `$`, names nested fields with dots and picks an array entry
by its index in brackets, counting from 0:

| Payload                         | Value Path            | Result |
| ------------------------------- | --------------------- | ------ |
| `{"temperature": 72.5}`         | `$.temperature`       | `72.5` |
| `{"sensors": {"temp": 68}}`     | `$.sensors.temp`      | `68`   |
| `{"readings": [{"value": 42}]}` | `$.readings[0].value` | `42`   |
| `{"data": [10, 20, 30]}`        | `$.data[1]`           | `20`   |

##### Value Path Result (read-only)

Shown only when the item has a State Topic and a [Value Path](#value-path).
Displays the value the path picked from the last payload, or
`Error: Invalid JSON` or `Error: Path not found`.

##### State (read-only)

Shown only for a relay or contact with a State Topic. Displays `On` or `Off` for
a relay and `Open` or `Closed` for a contact. It stays empty until a payload
matches.

##### State On

Shown only for a relay with a [State Topic](#state-topic). Sets the payload that
means the relay is on. If only this is set, any other payload means off. If both
State On and State Off are set, a payload that matches neither is ignored. A new
item starts with both empty, and the relay shows no state until one is set.

##### State Off

Shown only for a relay with a State Topic. Sets the payload that means the relay
is off. If only this is set, any other payload means on.

##### Command Topic

Shown for a relay, a button, and a string, bool, number or float variable. Sets
the topic the item publishes to.

##### Payload On

Shown only for a relay with a [Command Topic](#command-topic). Sets the payload
published when the relay turns on. A new item starts with it empty, so enter the
payload your device expects: an empty field publishes an empty payload.

##### Payload Off

Shown only for a relay with a Command Topic. Sets the payload published when the
relay turns off. Like Payload On, it starts empty.

##### Optimistic \[ **_Auto_** | Yes | No \]

Shown only for a relay. Sets whether the relay's state changes as soon as it
publishes a command. `Auto` does so only when the item has no State Topic, `Yes`
always does, and `No` waits for the State Topic. Default is `Auto`.

##### State Open

Shown only for a contact with a [State Topic](#state-topic). Sets the payload
that means the contact is open. If only this is set, any other payload means
closed. If both State Open and State Closed are set, a payload that matches
neither is ignored. A new item starts with both empty, and the contact shows no
state until one is set.

##### State Closed

Shown only for a contact with a State Topic. Sets the payload that means the
contact is closed. If only this is set, any other payload means open.

##### Payload Press

Shown only for a button with a [Command Topic](#command-topic). Sets the payload
published when the button is pressed, by the Press command or by a device bound
to its connection. A new item starts with it empty, and an empty field publishes
an empty payload.

##### Event Type Filter

Shown only for an event. Lists the event types the event accepts, separated by
commas. A message whose value, after any Value Path, matches none of them is
ignored. Leave it empty to accept every message.

##### QoS \[ **_0_** | 1 | 2 \]

Shown only when the item has a State Topic or a Command Topic. Sets the MQTT
quality of service level the item subscribes and publishes with. Default is `0`.

##### Retain \[ Yes | **_No_** \]

Shown only when the item has a Command Topic. Sets whether the broker keeps the
last message the item publishes for clients that subscribe later. Default is
`No`.

##### Temperature Scale \[ **_Celsius_** | Fahrenheit \]

Shown only for a temperature variable. Sets the scale of the values on the State
Topic, so its connection reports the right temperature. Default is `Celsius`.

## Connections

When you add relays, contacts, buttons, or sensor variables, dynamic bindings
are created that appear in the Connections tab:

- **Relays** create RELAY bindings
- **Contacts** create CONTACT_SENSOR bindings
- **Buttons** create BUTTON_LINK bindings (provider, for sending commands to
  MQTT)
- **Events** create BUTTON_LINK bindings (consumer, for triggering keypads)
- **Temperature variables** create TEMPERATURE_VALUE bindings
- **Humidity variables** create HUMIDITY_VALUE bindings

These bindings can be connected to other Control4 devices (thermostats, security
panels, keypads, etc.) or used directly in programming.

### Programming

**Events:**

- **Device Available** - Fires when availability payload is received
- **Device Unavailable** - Fires when not-available payload is received
- **{Event Name} Triggered** - Fires when an event item receives a matching MQTT
  message

**Conditionals:**

- **Device Available** - Check if the device is available or unavailable

**Commands:**

- **Press** - Press a button by name (for button items)

**Variables:**

Variable-type items (STRING, BOOL, NUMBER, FLOAT, TEMPERATURE, HUMIDITY) create
Control4 variables that can be read in conditionals and written to trigger
publishing to the command topic.

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

<!-- #embed-changelog -->
