# Fast N Fresh v1.1.0+2 — Fixes

Applied to the complete `Fast_N_Fresh_fcm_production_ready.zip` source:

- Dashboard/recent-order lifecycle: QR orders now have a final `completed` kitchen state and the Kitchen Display can explicitly complete a ready order.
- QR customer checkout: added Pay at Counter and Pay Online via UPI. The public API exposes only the cafe UPI ID/configuration needed by the customer menu. The UPI option is shown only when a UPI ID is configured in Business Settings.
- Broken print/X icon rendering: replaced the three print SVG widgets with native Flutter `Icons.print_outlined`.
- App version remains `1.1.0+2`.
- Existing product images and the rest of the source tree are preserved.
- No live environment secrets are added to this package.


Additional production fixes: QR payment method is now persisted, dashboard no longer mislabels legacy QR orders as PENDING, QR web checkout selection is fixed, and Kitchen Display shows red NEW-order alerts while allowing READY -> COMPLETED and hiding actions for completed orders.
