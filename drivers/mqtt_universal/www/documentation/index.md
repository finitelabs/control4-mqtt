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

The MQTT Universal driver brings MQTT devices and values into Control4. You add
relays, contact sensors, buttons, events and variables, and give each its own
state and command topics. It reaches the broker through the MQTT Broker driver.

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
  - [Events](#events)
  - [Conditionals](#conditionals)
  - [Commands](#commands)
  - [Variables](#variables)
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

- **Relays** - Create `RELAY` bindings for on/off control with state feedback
- **Contact Sensors** - Create `CONTACT_SENSOR` bindings for open/closed state
- **Buttons** - Publish press commands to MQTT topics, with optional keypad
  linking
- **Events** - Create `BUTTON_LINK` bindings that trigger on MQTT messages, for
  keypad integration

**Variables:**

- **String/Bool/Number/Float** - Create Control4 variables synced with MQTT
- **Temperature** - Create `TEMPERATURE_VALUE` bindings for thermostat
  integration
- **Humidity** - Create `HUMIDITY_VALUE` bindings for humidity sensor
  integration

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

Displays the state of the driver's link to the broker and of the device:

- `Connected` while the MQTT Broker is connected to the broker.
- `Disconnected` while it is not, or while the driver is not bound to an MQTT
  Broker.
- `Device unavailable` while the broker is connected and
  [Availability Status](#availability-status-read-only) reads `Unavailable`.

##### Driver Version (read-only)

Displays the current version of the driver.

<!-- #ifdef DRIVERCENTRAL -->

##### Log Level \[ 0 - Fatal | 1 - Error | 2 - Warning | **_3 - Info_** | 4 - Debug \]

Sets the logging level. Default is `3 - Info`. It returns to `3 - Info` when
[Log Mode](#log-mode--off--print--log--print-and-log-) turns off. While a
Support Code has Composer's Lua tab open, it also offers `5 - Trace` and
`6 - Ultra`.

<!-- #else -->

##### Log Level \[ 0 - Fatal | 1 - Error | 2 - Warning | **_3 - Info_** | 4 - Debug | 5 - Trace | 6 - Ultra \]

Sets the logging level. Default is `3 - Info`. It returns to `3 - Info` when
[Log Mode](#log-mode--off--print--log--print-and-log-) turns off.

<!-- #endif -->

##### Log Mode \[ **_Off_** | Print | Log | Print and Log \]

Sets the logging mode. Default is `Off`.

<!-- #ifdef DRIVERCENTRAL -->

##### Support Code

Leave it blank unless Finite Labs support gives you a code: for an hour, it
opens Composer's Lua tab to this driver and adds `5 - Trace` and `6 - Ultra` to
Log Level.

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

These settings track one availability topic for the whole driver.

##### Availability Topic

Sets the topic the driver subscribes to for the device's availability. Leave it
empty if the device has no availability topic. Setting it adds the Device
Available and Device Unavailable events, the availability conditional and the
Availability Status variable. Set [Payload Available](#payload-available),
[Payload Not Available](#payload-not-available) or both to say which payloads
mean what.

Changing or clearing it blanks Availability Topic Value, Availability Value Path
Result and Availability Status until a payload arrives on the new topic.
Clearing it keeps the events, the conditional and the programming on them.

##### Availability Topic Value (read-only)

Shown only when [Availability Topic](#availability-topic) is set. Displays the
last payload received on it.

##### Availability Value Path

Shown only when [Availability Topic](#availability-topic) is set. Sets a
JSONPath that picks the availability value out of a JSON payload. Leave it empty
to use the whole payload. It takes the same paths as [Value Path](#value-path).

##### Availability Value Path Result (read-only)

Shown only when [Availability Topic](#availability-topic) and
[Availability Value Path](#availability-value-path) are set. Displays the value
the path picked from the last payload, or `Error: Invalid JSON` or
`Error: Path not found`.

##### Availability Status (read-only)

Shown only when [Availability Topic](#availability-topic) is set. Displays
`Available` or `Unavailable` once a payload matches.

##### Payload Available

Shown only when [Availability Topic](#availability-topic) is set. Sets the
payload that means the device is available. If only this is set, any other
payload means unavailable. If both payloads are set, a payload that matches
neither is ignored.

##### Payload Not Available

Shown only when [Availability Topic](#availability-topic) is set. Sets the
payload that means the device is unavailable. If only this is set, any other
payload means available.

#### Add Devices

Each Add property takes the name of a new item. The item is not added, and the
property shows an error for 2 seconds, when another item has the same name
(`Error: Item with name '<name>' already exists`) or a variable the item would
own is in use (`Error: Variable '<variable>' is already in use`). A variable is
in use when another item owns it, when it is Availability Status, or when a
property has its name. A run of spaces in a variable name counts as one
underscore.

##### Add Relay

Enter a name to create a new relay. This creates a `RELAY` binding that can be
connected to other Control4 devices or used in programming. The relay supports
ON, OFF, TOGGLE, and TRIGGER commands.

##### Add Contact

Enter a name to create a new contact sensor. This creates a `CONTACT_SENSOR`
binding that reports OPEN or CLOSED state based on MQTT messages.

##### Add Button

Enter a name to create a new button. Buttons publish a configured payload to an
MQTT topic when triggered via the Press command.

##### Add Event

Enter a name to create a new event. Events subscribe to MQTT topics and trigger
connected Control4 buttons/keypads when messages arrive.

#### Add Variables

These work as the [Add Devices](#add-devices) properties do.

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
`TEMPERATURE_VALUE` binding that can be connected to thermostats.

##### Add Humidity Variable

Enter a name to create a new HUMIDITY variable. This creates a `HUMIDITY_VALUE`
binding that can be connected to humidity sensors.

#### Manage Items

These properties are shown only once the driver has at least one item. Each
entry in their lists reads `Name (TYPE) [ID]`.

##### Remove Item

> ⚠️ Removing an item also removes its connection and the bindings made to it.
> Removing an event item also removes its event and the programming on it.

Selects an item to remove. The item's variables are removed with it.

##### Configure Item

Selects an item to show its settings under
[Item Configuration](#item-configuration). A new item is selected here when you
add it.

#### Item Configuration

These properties are shown when an item is selected in
[Configure Item](#configure-item). Which ones appear depends on the item's type
and on the topics it has.

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

### MQTT Broker (consumer)

Binds to the MQTT Broker driver, which carries every message the items send and
receive. When you add the driver, it binds itself to the first MQTT Broker
driver in the project.

### {name} (provider, dynamic)

Adding a relay, contact, button, temperature variable or humidity variable adds
a connection named for the item:

| Item                 | Binding Class       | Purpose                                                                   |
| -------------------- | ------------------- | ------------------------------------------------------------------------- |
| Relay                | `RELAY`             | Takes on and off commands and reports the relay's state                   |
| Contact              | `CONTACT_SENSOR`    | Reports whether the contact is open or closed                             |
| Button               | `BUTTON_LINK`       | Lets a bound device press the button                                      |
| Temperature variable | `TEMPERATURE_VALUE` | Reports the temperature, in the item's Temperature Scale, when it changes |
| Humidity variable    | `HUMIDITY_VALUE`    | Reports the humidity when it changes                                      |

### {name} (consumer, dynamic)

Adding an event adds a `BUTTON_LINK` connection named for the item. Each time
the event fires, a device bound here gets a button press, as from a keypad
button.

> **Note:** `{name}` is the item's name. A button's connection and an event's
> connection have the same binding class but point opposite ways: a button lets
> another device press it, and an event acts as a keypad button that drives the
> device bound to it.

# <span style="color:#660066">Programming</span>

## Events

| Event              | Description                                                                                                                                                                                                   |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Device Available   | Fires when the device changes from unavailable to available, including a change made while the controller was down. Added when [Availability Topic](#availability-topic) is set, and kept when it is cleared. |
| Device Unavailable | Fires when the device changes from available to unavailable, including a change made while the controller was down. Added and kept with Device Available.                                                     |
| `{name} Triggered` | Fires when an event item receives a new message that passes its [Event Type Filter](#event-type-filter).                                                                                                      |

## Conditionals

| Conditional                | Description                                                                                            |
| -------------------------- | ------------------------------------------------------------------------------------------------------ |
| Device availability status | Tests whether the device is `Available` or `Unavailable`. Added and kept with the availability events. |

## Commands

| Command | Parameters | Description                                                            |
| ------- | ---------- | ---------------------------------------------------------------------- |
| Press   | Button     | Publishes the chosen button item's Payload Press to its Command Topic. |

## Variables

| Variable            | Type                          | Description                                                                                                                                                                              |
| ------------------- | ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `{name}`            | STRING, BOOL, NUMBER or FLOAT | A string, bool, number or float item's value from its State Topic. Writable: setting it publishes the new value to its Command Topic, and the next value on its State Topic replaces it. |
| `{name}`            | FLOAT                         | A temperature or humidity item's last reading. Read-only.                                                                                                                                |
| `{name} State`      | STRING                        | A relay's `On` or `Off`, a contact's `Open` or `Closed`, or an event's last event type. Read-only.                                                                                       |
| Availability Status | STRING                        | `Available` or `Unavailable`, or empty until a payload on the Availability Topic matches. Read-only.                                                                                     |

> **Note:** `{name}` is the item's name. A temperature or humidity item's
> variable appears with its first reading. A State variable appears, empty, as
> soon as its item is added, and Availability Status as soon as an Availability
> Topic is set.

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
[driver-support@finitelabs.com](mailto:driver-support@finitelabs.com).

<!-- #else -->

If you have any questions or issues integrating this driver with Control4, you
can file an issue on GitHub:

https://github.com/finitelabs/control4-mqtt/issues/new

<a href="https://www.buymeacoffee.com/derek.miller" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

<!-- #endif -->

<!-- #embed-changelog -->
