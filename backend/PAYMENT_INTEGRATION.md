# Customer Online Payment Integration

The customer QR online-payment flow is intentionally fail-closed until a real
server-verifiable payment provider is configured.

## Current architecture

`POST /api/public/payments` creates a `PaymentTransaction`, not an `Order`.

A configured provider adapter must:
1. create the provider-side payment;
2. return a checkout URL/reference;
3. expose server-side payment status and/or a signed webhook;
4. return `succeeded` only after the provider verifies the payment.

Only then does `paymentService.finalizeVerifiedPayment()` create the existing
`Order` with `paymentStatus: paid` and `status: open`.

The final Order is therefore never created merely because:
- a customer tapped Pay Online;
- a UPI/payment app opened;
- the browser returned from another app;
- localStorage says a payment was started;
- a customer supplied a UTR/reference.

## Provider adapter

Implement the existing contract in:

`backend/src/services/paymentProvider.js`

and select it with:

`PAYMENT_PROVIDER=<provider-name>`

The adapter must perform provider-specific signature/webhook verification on
the server. Do not add a frontend success flag or restore the old UTR flow.

Until an adapter and credentials are actually configured, `/api/public/payments`
returns a configuration error and the customer menu does not advertise online
payment. Pay at Counter remains available.

## Important

The repository currently contains no configured Razorpay, PhonePe, Cashfree,
PayU, Stripe, or other PSP credentials/webhook integration. This project
therefore does not claim automatic online-payment verification yet.
