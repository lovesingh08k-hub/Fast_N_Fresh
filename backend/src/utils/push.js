// Sends push notifications via Firebase Cloud Messaging (FCM), so
// admin/manager/staff get a real notification even when the app is fully
// closed -- not just backgrounded. An in-app poll (what the app already
// had) can only alert someone while its process is alive; this is what
// reaches a device where the app isn't running at all.
//
// ---------------------------------------------------------------------
// ONE-TIME SETUP REQUIRED (not something code alone can do):
// 1. Create a Firebase project at https://console.firebase.google.com
//    and add the Android app (applicationId from
//    mobile/android/app/build.gradle) and, if used, the iOS app.
// 2. Run `flutterfire configure` from mobile/ (or manually download
//    google-services.json into mobile/android/app/ and
//    GoogleService-Info.plist into mobile/ios/Runner/).
// 3. Firebase Console -> Project settings -> Service accounts ->
//    "Generate new private key". Keep that JSON file OUT of git.
// 4. On the server, set ONE of:
//      FIREBASE_SERVICE_ACCOUNT_JSON = <paste the whole JSON as one line>
//      FIREBASE_SERVICE_ACCOUNT_PATH = /absolute/path/to/the-file.json
// 5. `npm install` in backend/ (firebase-admin is already in
//    package.json).
//
// Until that's done, every function below simply no-ops -- placing an
// order, logging in, etc. all keep working exactly as before either way.
// ---------------------------------------------------------------------

let cachedAdmin = null;
let attemptedInit = false;

function getAdmin() {
  if (attemptedInit) return cachedAdmin;
  attemptedInit = true;

  try {
    // eslint-disable-next-line global-require
    const admin = require('firebase-admin');

    if (!admin.apps.length) {
      const jsonEnv = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
      const pathEnv = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
      const adcEnv = process.env.GOOGLE_APPLICATION_CREDENTIALS;

      let credential;
      if (jsonEnv) {
        credential = admin.credential.cert(JSON.parse(jsonEnv));
      } else if (pathEnv) {
        // eslint-disable-next-line global-require, import/no-dynamic-require
        credential = admin.credential.cert(require(pathEnv));
      } else if (adcEnv) {
        // Standard Google Application Default Credentials path.
        credential = admin.credential.applicationDefault();
      } else {
        // Not configured yet -- stay a no-op rather than throwing, since
        // this must never block order creation or any other request.
        return null;
      }

      admin.initializeApp({ credential });
    }

    cachedAdmin = admin;
  } catch (err) {
    console.warn('[push] firebase-admin unavailable/misconfigured:', err.message);
    cachedAdmin = null;
  }

  return cachedAdmin;
}

/**
 * Sends a push notification to a list of FCM device tokens. Always
 * resolves (never throws) -- an expired token, a missing Firebase
 * config, or an FCM outage should never fail the request that triggered
 * the notification (e.g. placing an order).
 */
async function sendPushToTokens(tokens, { title, body, data } = {}) {
  const cleanTokens = [...new Set((tokens || []).filter(Boolean))];
  if (cleanTokens.length === 0) return;

  const admin = getAdmin();
  if (!admin) return;

  try {
    const stringData = {};
    for (const [key, value] of Object.entries(data || {})) {
      stringData[key] = String(value);
    }

    const response = await admin.messaging().sendEachForMulticast({
      tokens: cleanTokens,
      notification: { title, body },
      data: stringData,
      android: { priority: 'high' },
      apns: { payload: { aps: { sound: 'default' } } },
    });

    // Clean up tokens FCM says are dead (app uninstalled, token rotated,
    // etc.) so they stop being retried forever.
    const deadTokens = [];
    response.responses.forEach((r, i) => {
      if (!r.success && ['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(r.error?.code)) {
        deadTokens.push(cleanTokens[i]);
      }
    });
    if (deadTokens.length > 0) {
      // eslint-disable-next-line global-require
      const { User } = require('../models');
      await User.updateMany({}, { $pullAll: { fcmTokens: deadTokens } });
    }
  } catch (err) {
    console.warn('[push] send failed:', err.message);
  }
}

/**
 * Pushes a new-order alert to every active admin/manager/staff user's
 * registered devices.
 */
async function pushNewOrderAlert(order) {
  try {
    // eslint-disable-next-line global-require
    const { User } = require('../models');
    const staffUsers = await User.find({
      status: 'active',
      role: { $in: ['admin', 'manager', 'staff'] },
      fcmTokens: { $exists: true, $ne: [] },
    }).select('fcmTokens');

    const tokens = staffUsers.flatMap((u) => u.fcmTokens || []);
    if (tokens.length === 0) return;

    const itemsSummary = (order.items || []).map((i) => `${i.quantity}x ${i.name}`).join(', ');

    await sendPushToTokens(tokens, {
      title: `New order #${order.orderNumber}`,
      body: itemsSummary || 'A new order just came in.',
      data: { type: 'new_order', orderId: String(order._id) },
    });
  } catch (err) {
    console.warn('[push] pushNewOrderAlert failed:', err.message);
  }
}

module.exports = { sendPushToTokens, pushNewOrderAlert };
