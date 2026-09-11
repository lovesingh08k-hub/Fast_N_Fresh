# Fast N Fresh Cafe — Mobile App (Flutter)

Android POS + cafe management app. Material 3, clean architecture, Provider for
state management, Dio for networking.

## Requirements

- Flutter 3.27+ / Dart 3.6+ (uses the modern `Color.withValues` API — if you're on
  an older Flutter, run `flutter upgrade` first)
- Android Studio or VS Code with the Flutter extension
- An Android device or emulator (minSdk 23 / Android 6.0+)
- The backend running and reachable (see `../backend/README.md`)

## 1. Install dependencies

```bash
cd mobile
flutter pub get
```

## 2. Point the app at your backend

The API base URL is controlled by a single `--dart-define` — **never hardcode
`localhost`**, since on a real Android device or emulator that refers to the
device itself, not your development PC.

| Scenario | API_BASE_URL |
|---|---|
| Android Emulator, backend on your dev PC | `http://10.0.2.2:5000/api` (default, no flag needed) |
| Physical device on the same Wi-Fi | `http://<your-computer-LAN-IP>:5000/api` |
| Production | `https://fast-n-fresh-slh9.onrender.com/api` (built-in default; --dart-define can override it) |

```bash
# Emulator (uses the built-in default — no flag needed)
flutter run

# Physical device on your Wi-Fi
flutter run --dart-define=API_BASE_URL=http://192.168.1.42:5000/api

# Production release build
flutter build apk --release --dart-define=API_BASE_URL=https://api.fastnfreshcafe.com/api
```

## 3. Connect an Android device

```bash
# Confirm your device/emulator is detected
flutter devices

# Enable USB debugging on a physical phone: Settings > About Phone > tap
# "Build Number" 7 times > Developer Options > USB Debugging.
```

## 4. Run in development

```bash
flutter run
```

## 5. Build the release APK

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://your-api-domain.com/api
```

The APK is produced at:

```text
build/app/outputs/flutter-apk/app-release.apk
```

Copy this file to the cafe owner's phone (or any Android device), open it, and
install (they'll need to allow "Install from unknown sources" the first time).

### Release signing

> Local/test fallback: if `android/key.properties` is absent, the release variant uses the Android debug keystore so `flutter build apk --release` can complete. Do **not** use that APK for Play Store production distribution; configure the real upload keystore before publishing.
 (required — release build now fails without it)

`android/app/build.gradle` **refuses to build a release APK signed with the
debug key**. You must generate your own upload keystore once before the first
real release:

1. Generate an upload keystore (run from `mobile/android/`):
   ```bash
   keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. Create `android/key.properties` manually (this file is git-ignored — never
   commit it) and fill in your real values:
   ```properties
   storeFile=upload-keystore.jks
   storePassword=<your password>
   keyAlias=upload
   keyPassword=<your password>
   ```
3. Build as normal — `build.gradle` now reads `key.properties` automatically
   and signs the release build with your keystore.

**Back up `upload-keystore.jks` and its passwords somewhere safe outside
Git.** Every future update must be signed with the *same* keystore, or Android
will refuse to install the update over the existing app on cafe devices —
losing the keystore means you can never ship an update to that install again.

## 6. App icon & splash screen

Placeholder brand-green icons (a simple cup mark) are already in
`android/app/src/main/res/mipmap-*/ic_launcher.png` and the splash screen in
`android/app/src/main/res/drawable/launch_background.xml`. Swap in the cafe's
real logo by replacing those PNGs (keep the same file names/sizes), or use the
`flutter_launcher_icons` package for a one-command regeneration from a single
source image.

## 7. Login

Use the credentials created by the backend's `npm run seed` script (from your
`.env`): the default admin and manager land on the Dashboard, the default
staff account lands on the New Order / POS screen. Roles are `admin`,
`manager`, and `staff` — see the project root README for the full permission
matrix.

## 7b. New in this update: Order types, tables, roles, attendance, photos

- **Order types**: every new order is Dine-In, Takeaway, or Delivery, chosen
  from the "New Order" screen (the POS tab's entry point). Takeaway/Delivery
  reuse the original one-tap billing flow unchanged; Dine-In routes through
  table selection.
- **Tables & multiple customers per table**: `Tables` (in the More menu, or
  via New Order → Dine-In) shows live occupied/available status per table.
  Opening a table shows every currently unpaid customer/order on it
  separately — each with its own cart, bill, and payment, and a "+ Add
  Customer" action to start another.
- **Roles**: Admin, Manager, Staff. Admin gets `Users & Roles` and `Staff
  Performance` in the More menu; Manager gets a `Credit / UDHAR Report`
  entry instead; Staff has no More tab at all.
- **Credit/UDHAR**: Staff can give credit (via "Give Credit" on a customer's
  profile) but the transaction ledger and "Record Payment" action are only
  shown to Manager/Admin — enforced by the backend independently of this UI.
- **Staff attendance**: automatic — whichever employee is logged in when an
  order starts is recorded as the order's `staff`/attendee. No extra step
  for staff. Admin-only `Staff Performance` screen shows who handled which
  customers.
- **Product photos**: add/edit a product to pick or take a photo — it's
  compressed client-side before upload and shown in both the product list
  and the POS product grid.

## 8. Project structure

```text
lib/
├── core/            # theme, network (Dio client, API config, token storage), utils, shared widgets
├── models/           # data classes mirroring backend schemas
├── services/         # one class per API domain, wraps Dio
├── providers/        # ChangeNotifier state: auth, cart, catalog, connectivity
├── screens/
│   ├── auth/          # login
│   ├── main/           # bottom-nav shell (role-based: admin/manager/staff)
│   ├── dashboard/       # admin + manager home
│   ├── pos/              # New Order chooser, billing screen, cart, payment, receipt
│   ├── tables/             # table grid, table detail (multi-customer), table add/edit
│   ├── orders/              # sales history + detail/void
│   ├── customers/            # UDHAR / customer management (role-aware credit visibility)
│   ├── products/               # product CRUD incl. photo upload
│   ├── categories/               # category CRUD
│   ├── inventory/                  # stock levels + adjustments
│   ├── staff/                       # legacy per-staff detail (admin only)
│   ├── users/                        # admin: Users & Roles management
│   ├── attendance/                    # admin: Staff Performance / customer-attendance report
│   ├── reports/                        # sales/products/staff/credit reports
│   ├── expenses/                        # expense tracking
│   └── settings/                         # business profile, security, more menu, profile
└── widgets/           # shared reusable UI (stat cards, etc.)
```

## 9. Permissions required on device

Product photo capture/selection needs Camera and Photos/Media permissions,
already declared in `AndroidManifest.xml`. Android will prompt the user the
first time a staff/admin/manager picks or takes a product photo.

## 10. Receipts & printing

Receipts are generated as PDFs (`lib/services/receipt_service.dart`) sized for
58mm or 80mm thermal rolls, and use the Android print/share sheet — so "Print"
opens the system print dialog (works with any print-service-compatible
Bluetooth/Wi-Fi thermal printer), and "Share" lets staff send the PDF or a
plain-text summary via WhatsApp or any other installed app. The service is
structured so a direct ESC/POS Bluetooth printer integration can be added later
without changing any call sites in the UI.
