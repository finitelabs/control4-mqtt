<!-- Copyright 2026 Finite Labs, LLC. All rights reserved. -->

<img alt="MQTT" src="./images/header.png" width="500"/>

______________________________________________________________________

# <span style="color:#660066">Overview</span>

> DISCLAIMER: This software is neither affiliated with nor endorsed by either
> Control4 or MQTT.

The MQTT Broker driver connects Control4 to any MQTT broker. It manages the
connection and provides pub/sub services to child drivers that connect via the
MQTT broker connection binding.

## Driver Suite

The MQTT driver suite consists of two drivers:

| Driver             | Direction | Purpose                                                                                         |
| ------------------ | --------- | ----------------------------------------------------------------------------------------------- |
| **MQTT Broker**    | N/A       | Connection management to your MQTT broker                                                       |
| **MQTT Universal** | Inbound   | External MQTT device -> Control4 (create relays, contacts, buttons, variables from MQTT topics) |

**Typical Setup:**

1. Add the **MQTT Broker** driver and configure your broker connection
1. Add **MQTT Universal** if you need to bring external MQTT devices into
   Control4

# <span style="color:#660066">Index</span>

<div style="font-size: small">

- [System Requirements](#system-requirements)
- [Features](#features)
- [Installer Setup](#installer-setup)
  - [Driver Installation](#driver-installation)
  - [Driver Setup](#driver-setup)
    - [Driver Properties](#driver-properties)
      - [Cloud Settings](#cloud-settings)
      - [Driver Settings](#driver-settings)
      - [Broker Settings](#broker-settings)
    - [Driver Actions](#driver-actions)
  - [Connections](#connections)
- [Programming](#programming)
  - [Events](#events)
  - [Conditionals](#conditionals)
  - [Commands](#commands)
- [Support](#support)
- [Changelog](#changelog)

</div>

# <span style="color:#660066">System Requirements</span>

- Control4 OS 3.3+
- An MQTT broker accessible on the local network

# <span style="color:#660066">Features</span>

- Local network communication requiring no cloud services
- Connects to any standard MQTT broker
- Supports username/password authentication
- Manages subscriptions for connected child drivers
- Automatic reconnection on disconnect
- Message caching for late-subscribing devices

# <span style="color:#660066">Installer Setup</span>

## Driver Installation

1. Download the latest `control4-mqtt.zip` from
   [Github](https://github.com/finitelabs/control4-mqtt/releases/latest).

1. Extract and
   [install](https://www.control4.com/help/c4/software/cpro/dealer-composer-help/content/composerpro_userguide/adding_drivers_manually.htm)
   the `mqtt_broker.c4z` and `mqtt_universal.c4z` drivers.

1. Use the "Search" tab to find the "MQTT Broker" driver and add it to your
   project.

   > ⚠️ A **_single_** broker driver instance is required per broker you wish to
   > connect to.

1. Configure the [Broker Settings](#broker-settings) with the connection
   information.

1. After a few moments the [`Driver Status`](#driver-status-read-only) will
   display `Connected`. If the driver fails to connect, set the
   [`Log Mode`](#log-mode--off--print--log--print-and-log-) property to `Print`
   and run action [`Reconnect`](#reconnect) from the actions tab. Then check the
   lua output window for more information.

## Driver Setup

### Driver Properties

#### Cloud Settings

##### Automatic Updates \[ Off | **_On_** \]

Turns on/off the GitHub cloud automatic updates. Changing it on any MQTT Broker
item changes it on all of them.

##### Update Channel \[ **_Production_** | Prerelease \]

Sets the update channel for which releases are considered during an automatic
update from the GitHub repo releases. Changing it on any MQTT Broker item
changes it on all of them.

#### Driver Settings

##### Driver Status (read-only)

Displays the state of the connection to the broker:

- `Connecting...` while the driver waits for the broker to answer.
- `Connected` once the broker accepts the connection.
- `Connect failed: <reason>`, or `Connect failed` when the broker gives no
  reason, when an attempt fails. The driver tries again.
- `Disconnected: <reason> (retrying)` when a connection drops. The driver tries
  again.
- `Disconnected` when the broker closes the connection cleanly. The driver does
  not try again until you run [`Reconnect`](#reconnect) or change a
  [Broker Setting](#broker-settings).
- `Not configured` while [`Broker Address`](#broker-address) is empty.

The driver waits 2 seconds before its first retry and doubles the wait after
each retry that fails, up to 30 seconds, so a broker that stays down is retried
every 30 seconds. The wait goes back to 2 seconds once a connection has stayed
up for two minutes.

##### Driver Version (read-only)

Displays the current version of the driver.

##### Log Level \[ 0 - Fatal | 1 - Error | 2 - Warning | **_3 - Info_** | 4 - Debug | 5 - Trace | 6 - Ultra \]

Sets the logging level. Default is `3 - Info`.

##### Log Mode \[ **_Off_** | Print | Log | Print and Log \]

Sets the logging mode. Default is `Off`.

#### Broker Settings

##### Broker Address

Sets the broker's IP address. A host name also works when the controller can
resolve it. HTTPS is not supported.

> ⚠️ If you are using an IP address, you should ensure it will not change by
> assigning a static IP or creating a DHCP reservation.

##### Port \[ 1 - 65535, default: **_1883_** \]

Sets the port the broker listens on. Default is `1883`.

##### Username

Sets the username for broker authentication (optional).

##### Password

Sets the password for broker authentication (optional).

##### Keep Alive \[ 10 - 3600, default: **_60_** \]

Sets the keep-alive interval in seconds. Default is `60`.

### Driver Actions

#### Update Drivers

Trigger all MQTT drivers to update from the latest release on GitHub, regardless
of the current version.

#### Reconnect

Closes the connection to the broker and connects again. Control4 programming can
do the same with the [`Reconnect`](#commands) command.

## Connections

### MQTT Broker (provider)

Each MQTT Universal driver binds here to send and receive its messages through
this broker.

# <span style="color:#660066">Programming</span>

## Events

| Event               | Description                                                                                                                                           |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Broker Connected    | Fires when the driver connects to the MQTT broker.                                                                                                    |
| Broker Disconnected | Fires once when a connection to the MQTT broker ends, whether the broker drops it or the driver closes it. It does not fire again while retries fail. |

## Conditionals

| Conditional                   | Description                                                |
| ----------------------------- | ---------------------------------------------------------- |
| MQTT broker connection status | Tests whether the broker is `Connected` or `Disconnected`. |

## Commands

| Command   | Parameters | Description                                                                         |
| --------- | ---------- | ----------------------------------------------------------------------------------- |
| Reconnect | None       | Closes the connection to the broker and connects again, as the action of that name. |

# <span style="color:#660066">Support</span>

If you have any questions or issues integrating this driver with Control4, you
can file an issue on GitHub:

https://github.com/finitelabs/control4-mqtt/issues/new

<a href="https://www.buymeacoffee.com/derek.miller" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

# <span style="color:#660066">Changelog</span>

<!--
Template for a new release entry (copy below the heading, fill in, uncomment):

## v[Version] - YYYY-MM-DD

### Added
- Added

### Fixed
- Fixed

### Changed
- Changed

### Removed
- Removed
-->

## Unreleased

### Changed

- Changed Log Level in the DriverCentral build to stop at 4 - Debug, and to
  offer 5 - Trace and 6 - Ultra only while a Support Code from Finite Labs
  support has the Lua tab open.

## v20261106 - 2026-11-06

### Added

- Added a Reconnect command to the MQTT Broker, so Control4 programming can
  reconnect it the same way as the Reconnect action.

### Fixed

- Fixed MQTT Universal relay and contact items running their programming at a
  controller restart or a new binding, so it now runs only when they open or
  close.
- Fixed an MQTT Universal event item sometimes missing from programming after a
  controller reboot until the driver was reloaded.
- Fixed an MQTT Universal event item firing again after a driver update, a
  broker reconnect or a settings change, so it now fires only when a new message
  arrives.
- Fixed MQTT Universal missing an availability change made while the controller
  was down, and showing Connected for a device that was unavailable when the
  driver started.
- Fixed clearing MQTT Universal's Availability Topic deleting the Device
  Available and Device Unavailable events and their programming.
- Fixed MQTT Universal's State and Availability Status variables missing from
  programming until the first message arrived.
- Fixed removing an MQTT Universal temperature or humidity item leaving its
  variable behind.
- Fixed MQTT Universal accepting an item whose variable was already in use,
  which let the two overwrite each other.
- Fixed MQTT Universal temperature and humidity items sending bound devices the
  same reading again with every message.
- Fixed an MQTT Universal variable item keeping a value from Control4
  programming that the device refused.
- Fixed MQTT Universal's Log Mode not starting or stopping 6 - Ultra logging, or
  returning Log Level to 3 - Info when it turned off.
- Fixed MQTT Universal sometimes not finishing its start when one of its
  settings hit an error while loading.
- Fixed the MQTT Broker printing its password to the Lua output when debug
  printing was on.
- Fixed the MQTT Broker waiting 30 seconds to reconnect after a drop, so it now
  tries again within 2 seconds.
- Fixed the MQTT Broker not retrying when its Broker Address did not resolve,
  and Driver Status not saying why a connection dropped or failed.
- Fixed the MQTT Broker's Broker Disconnected event firing at each failed retry
  and missing a drop caused by Reconnect or a settings change.
- Fixed updating or removing the MQTT Broker leaving its old connection to the
  broker open.
- Fixed automatic updates sometimes leaving an MQTT driver a version behind.
- Fixed changing Automatic Updates or Update Channel on one MQTT driver briefly
  holding up the others.

### Changed

- Changed MQTT Universal's Composer category from Misc to Utility, so it is
  listed beside the MQTT Broker.

## v20261024 - 2026-10-24

### Fixed

- Fixed an MQTT event's button link acting twice on one press, which could turn
  a bound light straight back off.
- Fixed the Device Available, Device Unavailable and Triggered events leaving
  the device's name out of their title in Composer Pro programming.
- Fixed MQTT Universal temperature sensor items not updating a bound thermostat.
- Fixed MQTT Universal sensor and number variable items taking a nan or inf
  payload in place of the last good value.
- Fixed an automatic update sometimes leaving companion drivers on the previous
  version until the next update, which could make them stop responding in the
  meantime.

## v20260415 - 2026-04-15

### Fixed

- Fixed MQTT Broker auto-reconnect reliability.

## v20260414 - 2026-04-14

### Fixed

- Fixed MQTT Universal variables no longer taking Set Variable from programming
  after their first MQTT message.

- Fixed MQTT Universal boolean variables not toggling reliably from programming.

- Fixed MQTT Universal variables becoming read-only after a controller reboot or
  driver reload.

- Fixed automatic driver updates stopping when the MQTT driver that ran them was
  removed from the project.

## v20260217 - 2026-02-17

### Changed

- Changed Automatic Updates and Update Channel to stay the same on every MQTT
  Broker driver in the project.
- Changed temperature conversions between Fahrenheit and Celsius to keep one
  decimal place instead of rounding to a whole or half degree.

### Fixed

- Fixed variables restoring in the wrong order after a controller reboot.

## v20260127 - 2026-01-27

### Fixed

- Fixed incorrect DriverCentral product ID in MQTT Universal driver.

## v20260120 - 2026-01-20

### Fixed

- Fixed MQTT Universal's connections to other devices not reconnecting after a
  controller reboot.

## v20260119 - 2026-01-19

### Added

- Added event items to MQTT Universal, which receive MQTT events and press
  linked Control4 buttons.

### Changed

- Updated the MQTT Broker and MQTT Universal documentation with their
  programming, read-only properties and button link connections.

### Removed

- Removed deprecated MQTT Switch, MQTT Contact, and MQTT Button drivers.

## v20260117 - 2026-01-17

### Added

- Added the MQTT Universal driver, which runs many MQTT devices from one driver
  with relays, contacts, buttons, variables and sensors.
- Added keypad button links for MQTT buttons, device availability events and
  conditionals, and state variables for relay and contact items.
- Added reading values out of JSON payloads by JSONPath.
- Added a Broker Connected conditional and events to the MQTT Broker driver.

### Deprecated

- Deprecated the MQTT Switch, MQTT Contact and MQTT Button drivers in favor of
  MQTT Universal, and this is their last release.

## v20251229 - 2025-12-29

### Added

- Initial Release.
