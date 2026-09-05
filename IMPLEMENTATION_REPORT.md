# Fast N Fresh — Kitchen + Payment Workflow Fix

### Kitchen workflow
QR/staff dine-in order → **NEW** → **Accept & Prepare** → **Preparing** → **Mark Ready** → **Ready / Open Bill** → staff checkout → **Completed**.

Kitchen status and payment status are separate. The word “Pending” is no longer used as the kitchen order status. Payment appears separately as **CASH • DUE**, **UPI • VERIFY PAYMENT**, or **PAID**. Amber is used for pending/due; red is reserved for failed/cancelled.

### UPI workflow
Customer taps **Pay UPI** → external UPI app opens → customer returns → enters UPI reference/UTR → taps **Place Order** → order enters Kitchen as NEW + UPI verification pending. It is never auto-marked paid from the app return. Staff verifies the UTR and uses checkout; only checkout sets paymentStatus=paid.

### Important limitation
There is no bank/PSP API or webhook in this repository, so true automatic bank verification cannot be claimed. This build intentionally uses a human-verifiable UTR/reference at checkout rather than falsely treating a UPI deep-link return as proof of payment.
