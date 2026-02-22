# Register

A SwiftUI implementation of a payment terminal for [APIS]. Uses MQTT to listen
for events from the server and the Square Mobile Payments SDK to handle
payments.

[APIS]: https://github.com/furthemore/APIS

## Using

The app must import settings from a QR code. The data must be formatted as follows:

```jsonc
{
    "terminalName": "",
    "endpoint": "",
    "token": "",
    "webViewUrl": "",
    "themeColor": "",
    "mqttHost": "",
    "mqttPort": "",
    "mqttUsername": "",
    "mqttPassword": "",
    "mqttPrefix": "",
    "squareApplicationId": "",
    "squareLocationId": ""
}
```

## Integration

The app depends on the following API endpoints.

### `POST /registration/terminal/square/token`

This is called when the client requests a new token to authenticate the Square
Mobile Payments SDK. No meaningful data is provided in the request body, the key
is provided as a bearer token in the `Authorization` header.

When the OAuth flow has completed on the server, the `updateToken` MQTT event
should be emitted.

### `POST /registration/terminal/square/completed`

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

Various JSON-encoded events should be emitted to control cart and payment
behaviors. Topics should all have the `mqttPrefix` prefix.

#### `payment/cart/clear`

Clears the cart. This is automatically performed when switching modes. No body
is required.

#### `payment/cart/update`

Updates the payment screen cart.

```jsonc
{
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
```

#### `payment/print`

Print data to a connected Bluetooth printer.

```jsonc
{
    "url": "https://example.com/file.pdf", // URL to PDF
    "serialNumber": null // Printer serial number, null selects one at random
}
```

#### `payment/process`

Processes the payment by starting the Square Mobile Payments SDK.

```jsonc
{
    "processPayment": {
        "orderId": "", // Square Order ID, if desired
        "total": 100, // total payment expected, in cents
        "note": "", // a note attached to the transaction, displayed to the user
        "reference": "" // an internal reference, included when completing the transaction
    }
}
```

#### `payment/registration/cancel`

Cancel an on-terminal registration. No body is required.

#### `payment/registration/display`

Display on-site registration on the device.

```jsonc
{
    "url": "https://example.com",
    "token": ""
}
```

#### `payment/state`

Switches the state of the terminal. May be any string, but only the following
values are used:

* `open` - Sets terminal to accept payments
* `close` - Sets terminal to closed screen

### `payment/update/config`

Updates the Terminal's configuration. The body should be the same as the data
contained within the configuration QR code.

### `payment/update/token`

Update the authorization token for use with the Mobile Payments SDK.

```jsonc
{
    "updateSquareToken": {
        "accessToken": ""
    }
}
```

## Printing

This app supports directly printing badges using Zebra Bluetooth printers. You
must add the [Link-OS SDK][linkos-sdk] to the app before building by placing the
headers in Register/Frameworks/Headers and the framework in Register/Frameworks.

[linkos-sdk]: https://www.zebra.com/ap/en/support-downloads/software/printer-software/link-os-multiplatform-sdk.html
