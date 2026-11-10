<p><img src="https://drivercentral.io/images/companies/61/MQTT/facts-strip-2400x136.png?1794015757814" alt="" width="1200" height="68" /></p>

## Overview

The MQTT Broker driver connects Control4 to an MQTT broker (such as Mosquitto,
HiveMQ, or other MQTT-compatible platforms). It manages the connection and
provides pub/sub services to child drivers (switch, button, contact, etc.) that
connect via the MQTT broker connection binding.

## Features

- Local network communication requiring no cloud services
- Connects to any standard MQTT broker
- Supports username/password authentication
- Manages subscriptions for connected child drivers
- Automatic reconnection on disconnect
- Message caching for late-subscribing devices

## System requirements

- Control4 OS 3.3+
- An MQTT broker accessible on the local network
