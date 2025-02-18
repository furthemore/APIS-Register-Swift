# Register

A SwiftUI implementation of a payment terminal for [APIS]. Uses MQTT to listen
for events from the server and the Square Mobile Payments SDK to handle
payments.

[APIS]: https://github.com/furthemore/APIS

## Using

Before deployment, the `squareApplicationId` in Register.swift must be updated.

The app can be manually configured or it can import settings from a QR code. The
automatic setup data must be formatted as follows:

```jsonc
{
  "terminalName": "", // optional, can be specified in-app
  "host": "https://example.com/registration",
  "token": ""
}
```

## Integration

The app depends on the following API endpoints.

### `POST /terminal/register`

This is called when registering the terminal using the provided configuration
data. The body of the request is the following JSON:

```jsonc
{
    "terminalName": "", // name to use for this terminal
    "token": "" // a secret key used to authorize the terminal
}
```

It expects a response like the following from the server:

```jsonc
{
    "terminalName": "", // may be different, the terminal will use this value
    "host": "", // APIS endpoint, ending in /register
    "token": "", // the same secret key as was provided
    "key": "", // a secret key this terminal uses to authenticate requests
    "webViewURL": "", // website URL to be displayed on the payment screen
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
Mobile Payments SDK. No meaningful data is provided in the request body, the key
is provided as a bearer token in the `Authorization` header.

When the OAuth flow has completed on the server, the `updateToken` MQTT event
should be emitted.

### `POST /terminal/square/completed`

This is called when the terminal completes a payment with the Square Mobile
Payments SDK. It is authenticated with a bearer authorization header. The body of
this request is JSON-encoded like the following:

```jsonc
{
    "reference": "",
    "transactionId": ""
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

Processes the payment by starting the Square Mobile Payments SDK.

```jsonc
{
    "processPayment": {
        "total": 100, // total payment expected, in cents
        "note": "", // a note attached to the transaction, displayed to the user
        "reference": "" // an internal reference, included when completing the transaction
    }
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
                "effectiveLevel": {
                    "name": "",
                    "price": "0.00"
                },
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

### Update Square Mobile Payments SDK Authorization

Update the authorization token for use with the Mobile Payments SDK.

```jsonc
{
    "updateToken": {
        "token": ""
    }
}
```
