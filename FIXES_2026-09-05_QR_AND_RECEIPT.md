# Fast N Fresh - QR Menu & Receipt Fixes (2026-09-05)

## QR customer menu
- Restored the complete production `web/menu/app.js` runtime. The previous packaged file was truncated and contained only the UPI function, so `init()` never ran and the page remained on "Loading menu".
- Added a 15-second API timeout with a clear error message instead of an endless spinner.
- Menu/table/payment requests now load before attempting to restore an old pending order, so stale order tracking cannot block the menu.
- Added versioned script URLs in `web/menu/index.html` to reduce stale browser/CDN caching after deployment.

## APK bill printing
- Reworked `mobile/lib/services/receipt_service.dart` into a formal thermal-style invoice layout.
- Uses fixed-width Courier font for receipt alignment.
- Header, TAX INVOICE, date/bill number, counter/staff, table, item/Qty/Rate/Amount columns, subtotal, discount, CGST/SGST, grand total, GST number, time and footer are included.
- Numeric amounts are printer-safe (no unsupported rupee glyph in the standard Courier font).
- Supports 58 mm and 80 mm receipt widths; existing print/share call sites remain compatible.

## Validation
- JavaScript syntax checked with `node --check web/menu/app.js`.
- Flutter SDK was not available in the execution environment, so `flutter analyze` / APK compilation could not be run here. Run `flutter clean && flutter pub get && flutter analyze` and then build the APK in the Flutter environment.

## UPI checkout button fix
- Selecting **Pay Online via UPI** and tapping the primary **Place Order** button now launches the device UPI app chooser directly.
- After returning from the UPI app, the customer can enter UTR/reference and tap **Place Order** to submit the order.
- Cash checkout remains unchanged.
