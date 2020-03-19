# oupgrade
Script to check firmware version and perform upgrade if necessary

## Reads Configuration from UCI

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
