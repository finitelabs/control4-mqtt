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

- Changed Log Level in the DriverCentral build to stop at `4 - Debug`:
  `5 - Trace` and `6 - Ultra` are offered only while a Support Code from Finite
  Labs support has the Lua tab open, and a driver set to either goes back to
  `4 - Debug`.

## v20261106 - 2026-11-06

### Added

- Added a `Reconnect` command to the MQTT Broker, so Control4 programming can
  reconnect it to the broker the same way as the `Reconnect` action.
  <!-- #ifdef DRIVERCENTRAL -->
- Added a `Support Code` property to the MQTT Broker and MQTT Universal drivers.
  A code from Finite Labs support opens the driver's Lua tab in Composer for an
  hour; leave it blank otherwise.
- Added a `Cloud Monitoring` property, Enabled by default, and a
  `Diagnostics Snapshot` action to every driver. Cloud Monitoring sends Finite
  Labs an hourly report of the driver's memory use and a report of each error it
  hits; the documentation says what they hold.
  <!-- #endif -->

### Fixed

- Fixed an MQTT Universal relay item running the bound relay's programming each
  time the controller restarted or the relay was bound. Programming now runs
  only when the relay opens or closes.
- Fixed an MQTT Universal contact item running the bound contact's programming
  each time the controller restarted, the driver was updated or the contact was
  bound. Programming now runs only when the contact opens or closes.
- Fixed MQTT Universal declaring its events again too early in its startup,
  which could leave an event item missing from Programming after a controller
  reboot until the driver was reloaded.
- Fixed an MQTT Universal event item firing again, running its programming and
  pressing a bound button, when the driver was updated, the MQTT Broker
  reconnected or an item's settings were changed. An event item now fires only
  when a new message arrives.
- Fixed MQTT Universal skipping the Device Available and Device Unavailable
  programming for an availability change made while the controller was down, and
  showing `Connected` for a device that was already unavailable when the driver
  started.
- Fixed clearing MQTT Universal's `Availability Topic` deleting the Device
  Available and Device Unavailable events and the programming on them. The
  events now stay, and the availability readings go blank.
- Fixed MQTT Universal's relay, contact and event State variables and its
  Availability Status variable missing from programming until the first message
  arrived. They now appear, empty, as soon as the item is added or the
  `Availability Topic` is set.
- Fixed removing an MQTT Universal temperature or humidity item leaving its
  variable behind.
- Fixed MQTT Universal adding an item whose variable was already in use by
  another item, by Availability Status or by a property, so the two overwrote
  each other. The item is now refused, and the Add property says which variable
  is in use.
- Fixed MQTT Universal temperature and humidity items sending bound devices the
  same reading again with every message. A reading now goes out only when it
  changes.
- Fixed an MQTT Universal variable item keeping a value from Control4
  programming that the device refused. The variable now shows the device's value
  again at its next report.
- Fixed MQTT Universal's `6 - Ultra` logging not starting when `Log Mode` was
  turned on and not stopping when it turned off. `Log Level` now also returns to
  `3 - Info` when logging turns off, as on the MQTT Broker.
- Fixed MQTT Universal sometimes not finishing its start when one of its
  settings hit an error while loading.
- Fixed the MQTT Broker printing its password to the Lua output when debug
  printing was on.
- Fixed the MQTT Broker waiting 30 seconds to reconnect after every drop. It now
  tries again 2 seconds after a drop and waits longer after each failed attempt,
  up to 30 seconds.
- Fixed the MQTT Broker staying at `Connecting...` with no retry when its
  `Broker Address` did not resolve, and showing a bare `Disconnected` while it
  retried. `Driver Status` now shows why the connection dropped or failed, and
  the driver retries.
- Fixed the MQTT Broker's Broker Disconnected event firing again at each failed
  retry while the broker stayed down, and not firing when a Reconnect or a
  settings change closed a live connection. Broker Connected and Broker
  Disconnected now fire only when the connection changes.
- Fixed updating or removing the MQTT Broker leaving its old connection to the
  broker open.
  <!-- #ifdef DRIVERCENTRAL -->
- Fixed a licensed MQTT Broker staying disconnected until Reconnect when it lost
  the broker while the DriverCentral Cloud driver was not answering. It now
  reconnects on its usual retry.
  <!-- #endif -->
  <!-- #ifndef DRIVERCENTRAL -->
- Fixed automatic updates sometimes leaving an MQTT driver a version behind.
  Each driver now updates in turn.
- Fixed changing Automatic Updates or Update Channel on an MQTT driver briefly
  holding up every other MQTT driver, longer in a project with many, while the
  change was copied to them.
  <!-- #endif -->

### Changed

- Changed MQTT Universal's Composer category from Misc to Utility, so it is
  listed beside the MQTT Broker.
  <!-- #ifdef DRIVERCENTRAL -->
- Changed Automatic Updates to one setting for the MQTT Broker and MQTT
  Universal drivers: changing it on any of them now changes it on all of them.
- Without an active license or trial, the MQTT Broker now disconnects five
  minutes after it loads and shows `No active license`. It connects again as
  soon as a license is active, with no Reconnect needed.
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
