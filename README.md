# Register

A SwiftUI implementation of a payment terminal for [APIS]. Uses MQTT to
listen for events from the server and the Square Reader SDK to handle payments.

[APIS]: https://github.com/furthemore/APIS

## Building

The Square Reader SDK must be downloaded manually. You can do this by running
the following script in the project root directory:

```bash
ruby <(curl https://connect.squareup.com/readersdk-installer) install --app-id $APP_ID --repo-password $ACCESS_TOKEN
```

Xcode should automatically fetch the remaining dependencies and then it's ready
to build! All other configuration happens at runtime.

## Using

The app can be manually configured or it can import settings from a QR code. The
automatic setup data must be formatted as follows:

```jsonc
{
  "terminalName": "", // optional, can be specified in-app
  "host": "https://example.com/registration",
  "token": "your-registration-token"
}
```

## Integration

The app depends on the following API endpoints.

### `POST /terminal/register`

This is called when registering the terminal using the provided configuration
data. The body of the request is the following JSON:

```jsonc
{
    "terminalName": "",
    "host": "",
    "token": ""
}
```

It expects a response like the following from the server:

```jsonc
{
    "terminalName": "", // may be different, the terminal will use this value
    "host": "",
    "token": "",
    "key": "", // a secret key this terminal uses to authenticate requests
    "webViewURL": "", // website URL to be displayed on the payment screen
    "allowCash": false, // if the Square Reader SDK should allow cash transactions
    "mqttHost": "",
    "mqttPort": "",
    "mqttUserName": "",
    "mqttPassword": "",
    "mqttTopic": ""
}
```

It connects to the MQTT server via WebSockets.

### `POST /terminal/square/token`

This is called when the client requests a new token to authenticate the Square
Reader SDK. No meaningful data is provided in the request body, the key is
provided via the `x-terminal-key` header.

The server should return a JSON-encoded string with the Square token.

### `POST /terminal/square/complete`

This is called when the terminal completes a payment with the Square Reader SDK.
It is authenticated with the `x-terminal-key` header. The body of this request
is JSON-encoded like the following:

```jsonc
{
    "reference": "",
    "clientTransactionId": "",
    "serverTransactionId": ""
}
```

It expects a response like the following:

```jsonc
{
    "success": true
}
```

### MQTT

Various JSON-encoded events should be emitted to the MQTT topic to control cart
and payment behaviors.

#### Open

Switches the terminal to the payments screen.

```jsonc
{
    "open": {}
}
```

#### Close

Switches the terminal to the close screen.

```jsonc
{
    "close": {}
}
```

#### Clear Cart

Clears the cart. This is automatically performed when switching modes.

```jsonc
{
    "clearCart": {}
}
```

#### Process Payment

Processes the payment by starting the Square Reader SDK.

```jsonc
{
    "total": 100, // total payment expected, in cents
    "note": "", // a note attached to the transaction, displayed to the user
    "reference": "" // an internal reference, included when completing the transaction
}
```

#### Update Cart

Updates the payment screen cart.

```jsonc
{
    "updateCart": {
        "cart": {
            "badges": [{
                "id": 1,
                "firstName": "",
                "lastName": "",
                "badgeName": "",
                "effectiveLevelName": "",
                "effectiveLevelPrice": "",
                "discountedPrice": null
            }],
            "charityDonation": "10.00",
            "organizationDonation": "0.00",
            "totalDiscount": null,
            "total": "30.00"
        }
    }
}
```
