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

<!-- #ifdef DRIVERCENTRAL -->

### Changed

- Changed Log Level in the DriverCentral build to stop at 4 - Debug unless a
  Support Code from Finite Labs support has the Lua tab open.

<!-- #endif -->

## v20261106 - 2026-11-06

### Added

- Added a Reconnect command to the MQTT Broker, so Control4 programming can
  reconnect it the same way as the Reconnect action.
  <!-- #ifdef DRIVERCENTRAL -->
- Added a Support Code property to the MQTT Broker and MQTT Universal drivers,
  which opens the driver's Lua tab in Composer for an hour with a code from
  Finite Labs support.
- Added a Cloud Monitoring property, Enabled by default, that sends Finite Labs
  an hourly report of each driver's memory use and a report of each error it
  hits, and a Diagnostics Snapshot action.
  <!-- #endif -->

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
  <!-- #ifndef DRIVERCENTRAL -->
- Fixed automatic updates sometimes leaving an MQTT driver a version behind.
- Fixed changing Automatic Updates or Update Channel on one MQTT driver briefly
  holding up the others.
  <!-- #endif -->

### Changed

- Changed MQTT Universal's Composer category from Misc to Utility, so it is
  listed beside the MQTT Broker.
  <!-- #ifdef DRIVERCENTRAL -->
- Changed Automatic Updates to one setting shared by every MQTT Broker and MQTT
  Universal driver in the project.
  <!-- #endif -->

## v20261024 - 2026-10-24

### Fixed

- Fixed an MQTT event's button link acting twice on one press, which could turn
  a bound light straight back off.
- Fixed the Device Available, Device Unavailable and Triggered events leaving
  the device's name out of their title in Composer Pro programming.
- Fixed MQTT Universal temperature sensor items not updating a bound thermostat.
- Fixed MQTT Universal sensor and number variable items taking a nan or inf
  payload in place of the last good value.
  <!-- #ifndef DRIVERCENTRAL -->
- Fixed an automatic update sometimes leaving companion drivers on the previous
  version until the next update, which could make them stop responding in the
  meantime.
  <!-- #endif -->

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

<!-- #ifndef DRIVERCENTRAL -->

- Fixed automatic driver updates stopping when the MQTT driver that ran them was
  removed from the project.

<!-- #endif -->

## v20260217 - 2026-02-17

### Changed

<!-- #ifndef DRIVERCENTRAL -->

- Changed Automatic Updates and Update Channel to stay the same on every MQTT
  Broker driver in the project.
  <!-- #endif -->
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
