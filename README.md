# oupgrade

Program to check current device firmware version and perform upgrade if necessary. Depends on:

* UCI configuration to hold current firmware version number and build number
* An API to read data on the latest firmware releases

Read on to find out how to configure oupgrade based on your needs.

## Usage

Run `oupgrade --help` for information on using the program.

## UCI Configuration

Depends on following config in `/etc/config/onion`:

```
config onion
        option version '0.3.2'
        option build '232'

config oupgrade 'oupgrade'
        option api_url 'https://api.onioniot.com/firmware'
        option ack_upgrade '1'
        option auto_update '0'
        option update_frequency 'monthly'
```

* `api_url` - specifies the URL of the Firmware API
  * Expecting a URL
* `ack_upgrade` - Update acknowledge nable/disable - ie sending a message to the Firmware API when an upgrade is started and completed
  * `0` for disabled, `1` for enabled
* `auto_update` - enable/disable automatic updates (updates run with `--force` and `--latest` flags)
  * `0` for disabled, `1` for enabled
* `update_frequency` - specify the frequency of automatic updates
  * Valid options are `daily`, `weekly`, `monthly`

## Specifying Firmware API URL

Device administrators can use UCI configuration to specify the URL that will be used by `oupgrade` to read the most recent firmware info. **This allows Omega2 users to use the existing upgrade mechanism but with a custom firmware server, and perhaps custom firmware.**

> If the API URL is not specified, `oupgrade` will default to https://api.onioniot.com/firmware

Expecting the API to have the following endpoint:

```
GET /{device}/{firmwareType}
```

Where:

* `{device}` is the device name. 
  * Determined by oupgrade by running `ubus call system board ` and reading the `board_name` key-value pair. With Onion products: `omega2`, `omega2p`, `omega2pro`, etc    
* `{firmwareType}` can be `stable` or `latest`
  * `stable` - indicates a **stable** firmware, safe to be released to be used by all devices
  * `latest` - indicates the latest released firmware, the bleeding edge. May not be safe for all devices. 
  
Expecting the following response:

```
{
  "version": "0.3.2",
  "url": "http://repo.onioniot.com/omega2/images/omega2-v0.3.2-b235.bin",
  "build": 235,
  "device": "omega2",
  "stable": false
}
```

## Acknowledging Firmware Updates

With this feature, devices have the ability to report to an API when firmware upgrades are started and completed. **This provides device administrators with data on which firmware versions are being used by deployed devices.**

> If update acknowledge enabled is not specified, it will default to **disabled**.

### The HTTP Request

The HTTP request will be made to the following endpoint on the API URL specified in the configuration:

```
POST /
```

With a `x-www-form-urlencoded` payload containing the following:

* `mac_addr` - the device `ra0` MAC address (matches the sticker on the device)
* `device` - the device name 
  * Determined by oupgrade by running `ubus call system board ` and reading the `board_name` key-value pair. With Onion products: `omega2`, `omega2p`, `omega2pro`, etc
* `firmware_version` - the firmware version number, eg `0.3.2`
* `firmware_build` - the firmware build number, eg `232`
* `upgrade_status` - status of the upgrade: `starting` or `complete`

### When the Acknowledge is Triggered

Firmware updates will be acknowledged in two scenarios:

1. The start of a firmware upgrade
2. When a firmware upgrade is completed

#### Start of a Firmware Upgrade

After the new target firmware is downloaded and before the system upgrade starts, the update acknowledge will be sent, with `starting` set as the `upgrade_status` in the payload.

#### Firmware Upgrade Completed

Firmware upgrade completed acknowledgements will be sent once the device boots the new firmware for the first time. The mechanism for tracking this is a `/etc/oupgrade` file that holds the device's firmware version number and build number in plain text.

The `oupgrade` program will run automatically at boot with the `--acknowledge` flag.

Possible scenarios:

* If the `/etc/oupgrade` file does not exist -> an upgrade has been completed
  * Create the `/etc/oupgrade` file and populate it with the current firmware version and build numbers
  * Send a firmware upgrade completed acknowledge
* If the `/etc/oupgrade` file exists but the version number and build it contains does not match the system's version data -> an upgrade has been completed
  * Populate the `/etc/oupgrade` file with the current firmware version and build numbers
  * Send a firmware upgrade completed acknowledge
* All other cases -> no updates
  * Do nothing


## Automatic Updates

UCI configuration can now be used to configure automatic firmware updates on a regular interval. **This provides Omega2 users with a mechanism to make sure deployed devices automatically update to new firmware.**

> If not specified, automatic updates will be **disabled** by default.

The UCI configuration determines if automatic updates are enabled, and if so, the interval at which the update check will be performed. See the [UCI configuration section](#uci-configuration) for more details on the configuration options. 

The available update check intervals are `daily`, `weekly`, and `monthly`.

Once the configuration has been set, run `oupgrade autoupdate` for the changes to be applied.

### Example

Let's say we want weekly updates, run the following commands:

```
uci set onion.oupgrade.auto_update='1'
uci set onion.oupgrade.update_frequency='weekly'
uci commit
oupgrade autoupdate
```

Now the device will check once a week for firmware updates.

### An Important Note:

If automatic updates are enabled, the oupgrade program will be run at the specified interval with the `latest` flag.

This means it will check for firmware information from the `{device}/latest` endpoint *(latest flag)*. The upgrade will only take place if the endpoint reports a firmware with a **greater version number** is available.
