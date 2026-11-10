<p><img src="https://drivercentral.io/images/companies/61/MQTT/facts-strip-2400x136.png?1794015757814" alt="" width="1200" height="68" /></p>

## Overview

*This software is neither affiliated with nor endorsed by either Control4 or
MQTT.*

The MQTT drivers bring MQTT devices and values into Control4. The MQTT Broker
driver connects Control4 to any MQTT broker on your network, and the MQTT
Universal driver turns MQTT topics into Control4 relays, contact sensors,
buttons, events and variables, each on its own MQTT topics.

## Features

- Local control over your network, with no cloud service
- Connects to any standard MQTT broker, with username and password sign-in
- Relays and contact sensors with state feedback from MQTT topics
- Buttons that publish to MQTT, and events that trigger keypad Button Links from
  MQTT messages
- Variables synced with MQTT, with temperature and humidity connections for
  thermostats and sensors
- Values read from nested JSON payloads
- Device Available and Unavailable events from an availability topic
- Automatic reconnection, with messages kept for devices that subscribe late

## Included drivers

### MQTT Broker

Connects to the MQTT broker and shares that one connection with every MQTT
Universal driver bound to it.

### MQTT Universal

Turns MQTT topics into Control4 relays, contact sensors, buttons, events and
variables. Bind each one to the MQTT Broker.

## System requirements

- Control4 OS 3.3+
- An MQTT broker on the local network
