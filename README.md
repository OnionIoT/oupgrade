# oupgrade
Script to check firmware version and perform upgrade if necessary

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
* `ack_upgrade` - enable/disable acknowledging firmware upgrades - ie sending a message to the Firmware API when an upgrade is started and completed
* `auto_update` - enable/disable automatic updates (updates run with `--force` and `--latest` flags)
* `update_frequency` - specify the frequency of automatic updates, valid options are `daily`, `weekly`, `monthly`

## Specifying Firmware API URL

Can now use UCI configuration to specify the URL that will be used by `oupgrade` to read the most recent firmware info. 

Expecting the following endpoints:

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
