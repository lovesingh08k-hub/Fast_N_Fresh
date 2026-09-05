# Fast N Fresh — notification setup

The app now has two notification paths:

1. **Live/in-app alert:** OrdersScreen polls for new QR orders every 8 seconds and shows a system notification even when another tab is open.
2. **Background/closed-app push:** Firebase Cloud Messaging (FCM) is wired in code, but it cannot work until the Android app has Firebase configuration and the backend has Firebase Admin credentials.

## Required for closed-app notifications

### Mobile
- Create/add the Android app with package ID `com.fastnfresh.cafe` in Firebase.
- Run `flutterfire configure` from `mobile/`, or provide the generated Android Firebase configuration (`google-services.json`) and corresponding Flutter Firebase options.

### Backend
Set one of these environment variables on the deployed backend:
- `FIREBASE_SERVICE_ACCOUNT_JSON` — complete Firebase service-account JSON
- `FIREBASE_SERVICE_ACCOUNT_PATH` — path to the service-account JSON on the server

Do not commit the service-account JSON or any private key.

## Why it was not working before

The repository did not contain Firebase Android configuration, so `Firebase.initializeApp()` failed and the push-token registration became a silent no-op. The backend also intentionally no-ops when Firebase Admin credentials are absent. That means there was no device token registered and therefore nothing for FCM to deliver.
