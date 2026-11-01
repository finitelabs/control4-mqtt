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

<!-- #ifdef DRIVERCENTRAL -->

## Unreleased

### Added

- Added a `Support Code` property to the MQTT Broker and MQTT Universal drivers.
  A code from Finite Labs support opens the driver's Lua tab in Composer for an
  hour; leave it blank otherwise.
  <!-- #ifdef DRIVERCENTRAL -->
- Added a `Cloud Monitoring` property, Enabled by default, and a
  `Diagnostics Snapshot` action to every driver. Cloud Monitoring sends Finite
  Labs an hourly report of the driver's memory use and a report of each error it
  hits; the documentation says what they hold.
  <!-- #endif -->

### Fixed

- Fixed an MQTT Universal relay item running the bound relay's programming every
  time the controller restarted. Programming now runs only when the relay opens
  or closes.

### Changed

- Automatic Updates now syncs across all MQTT Broker and MQTT Universal driver
  instances.

<!-- #endif -->

## v20261024 - 2026-10-24

### Fixed

- Fixed an MQTT event's button link acting on one press twice, which turned a
  bound on/off light straight back off and left a dimmer off instead of ramping
  it. Event button links now send the same command pair a Control4 keypad sends
  for a tap.
- Fixed the Device Available, Device Unavailable and event item Triggered events
  leaving the device's name out of their script title in Composer Pro. The title
  now names the device.
- Fixed MQTT Universal temperature sensor items not updating a bound thermostat.
- Fixed MQTT Universal sensor and number variable items accepting a `nan` or
  `inf` payload, such as a failed probe publishes. The last good value is kept.
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

- Fixed MQTT Universal variables losing their programming "Set Variable"
  callback after the first inbound MQTT message on the variable's state topic.
- Fixed MQTT Universal BOOL variables not toggling reliably from programming due
  to incorrect serialization to Control4.
- Fixed MQTT Universal variables losing their writable state after a controller
  reboot or driver reload.

<!-- #ifndef DRIVERCENTRAL -->

- Fixed automatic driver updates not working when the leader instance is removed
  from the project.

<!-- #endif -->

## v20260217 - 2026-02-17

### Changed

<!-- #ifndef DRIVERCENTRAL -->

- Broker properties (Automatic Updates, Update Channel) now automatically sync
  across all MQTT Broker driver instances.
  <!-- #endif -->
- Temperature conversions (Fahrenheit/Celsius) now use single decimal precision
  instead of rounding to the nearest integer or half degree.

### Fixed

- Fixed variable restore order during driver initialization on controller
  reboot.

## v20260127 - 2026-01-27

### Fixed

- Fixed incorrect DriverCentral product ID in MQTT Universal driver.

## v20260120 - 2026-01-20

### Fixed

- Fixed consumer bindings (e.g., BUTTON_LINK for Event entities) not restoring
  their connections on controller reboot. The bindings module now tracks
  connection info and automatically re-establishes consumer binding connections
  when bindings are restored.

## v20260119 - 2026-01-19

### Added

- Added Event entity type to MQTT Universal driver for receiving MQTT events and
  triggering Control4 buttons/keypads.

### Changed

- Updated MQTT Broker documentation to include Programming section with events
  and conditionals.
- Updated MQTT Universal documentation to include missing read-only properties
  and BUTTON_LINK binding information.

### Removed

- Removed deprecated MQTT Switch, MQTT Contact, and MQTT Button drivers.

## v20260117 - 2026-01-17

### Added

- Added the MQTT Universal driver for managing multiple MQTT devices from a
  single driver instance. Supports relays, contacts, buttons, variables, and
  sensors with features including:
  - Keypad button linking for MQTT buttons
  - Device availability conditionals and events
  - State variables for relay and contact items
  - JSONPath value extraction for complex JSON payloads
- Added "Broker Connected" conditional and events to the MQTT Broker driver.

### Deprecated

- Deprecated the MQTT Switch, MQTT Contact, and MQTT Button drivers. Use MQTT
  Universal instead. This is the terminal release for these drivers.

## v20251229 - 2025-12-29

### Added

- Initial Release.
