# Fast N Fresh — FCM production setup

The Android app is registered in Firebase as `com.fastnfresh.cafe` and the Google Services Gradle plugin is enabled.

## Backend push credential

The backend already uses `firebase-admin` and sends new-order notifications to active admin/manager/staff FCM tokens. For real push delivery while the app is closed, the deployed backend must have Firebase Admin credentials. Firebase documents service-account credentials for Admin SDK server environments.

Use one of these server-side methods (never commit the private key):

1. `FIREBASE_SERVICE_ACCOUNT_JSON` — the complete service-account JSON as a secret environment variable.
2. `FIREBASE_SERVICE_ACCOUNT_PATH` — path to a securely mounted JSON secret file.
3. `GOOGLE_APPLICATION_CREDENTIALS` — standard Application Default Credentials path to the mounted JSON file.

For Render, the safest approach is to add the service-account JSON as a Secret File and point `GOOGLE_APPLICATION_CREDENTIALS` at that mounted path, or use a protected environment variable.

## Important

Do NOT put the service-account private key into the Flutter APK or `google-services.json`. The Android `google-services.json` is client configuration; the Admin service-account key is server-only.

## Final test

After deploying the backend with the credential:

1. Install the release APK.
2. Log in as Admin/Manager/Staff.
3. Allow notifications.
4. Confirm the device registers its FCM token.
5. Place a QR order from the public menu.
6. Verify the staff device receives `New order #...` even when the app is closed.
