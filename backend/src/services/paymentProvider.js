// Provider-neutral payment gateway contract.
//
// The customer QR flow must never treat a raw `upi://pay` handoff, browser
// redirect, or frontend flag as proof of payment. A real PSP must provide a
// server-verifiable transaction state/signature/webhook before an Order is
// created.
//
// Set PAYMENT_PROVIDER only when a real provider adapter is implemented and
// its credentials/webhook configuration are present. Until then, the public
// online-payment endpoint fails closed rather than falling back to UTR.

class UnconfiguredPaymentProvider {
  constructor() {
    this.name = 'unconfigured';
  }

  async createPayment() {
    const error = new Error(
      'Online payment is not configured. Please choose Pay at Counter.'
    );
    error.statusCode = 503;
    error.code = 'PAYMENT_PROVIDER_NOT_CONFIGURED';
    throw error;
  }

  async getPaymentStatus() {
    const error = new Error('Online payment provider is not configured.');
    error.statusCode = 503;
    error.code = 'PAYMENT_PROVIDER_NOT_CONFIGURED';
    throw error;
  }

  async verifyWebhook() {
    const error = new Error('Online payment provider is not configured.');
    error.statusCode = 503;
    error.code = 'PAYMENT_PROVIDER_NOT_CONFIGURED';
    throw error;
  }
}

function getPaymentProvider() {
  // This intentionally does not pretend that a UPI deep link is a provider.
  // Add a real adapter here (Razorpay/PhonePe/Cashfree/etc.) only when its
  // server credentials and webhook/signature verification are configured.
  switch (String(process.env.PAYMENT_PROVIDER || '').trim().toLowerCase()) {
    default:
      return new UnconfiguredPaymentProvider();
  }
}

module.exports = { getPaymentProvider };
