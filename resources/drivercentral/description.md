<p><img src="https://drivercentral.io/images/companies/61/MQTT/facts-strip-2400x136.png?1794015757814" alt="" width="1200" height="68" /></p>

## Overview

The MQTT drivers bring MQTT devices and values into Control4. The MQTT Broker
driver connects Control4 to any MQTT broker on your network, and the MQTT
Universal driver turns MQTT topics into Control4 relays, contact sensors,
buttons, events and variables, each on its own MQTT topics.

## Features

- Local network communication requiring no cloud services
- Connects to any standard MQTT broker, with username and password sign-in
- Relays and contact sensors with state feedback from MQTT topics
- Buttons that publish to MQTT, and events that trigger keypad Button Links from
  MQTT messages
- Variables synced with MQTT, with temperature and humidity connections for
  thermostats and sensors
- Values read from nested JSON payloads
- Device Available and Unavailable events from an availability topic
- Automatic reconnection, with messages kept for devices that subscribe late

## System requirements

- Control4 OS 3.3+
- An MQTT broker accessible on the local network
