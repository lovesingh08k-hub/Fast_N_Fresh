const mongoose = require('mongoose');

// One MongoDB client per cluster URI. A client whose data lives on the main
// cluster (no dbUri of its own) shares the default connection; a client on
// its own Atlas cluster (e.g. a separate free 512 MB cluster, to keep
// storage apart) gets one extra pooled connection. Databases on a cluster
// are opened with useDb, which reuses that cluster's pool.
const clusters = new Map();

function clusterFor(uri) {
  if (!uri || uri === process.env.MONGODB_URI) return mongoose.connection;
  let conn = clusters.get(uri);
  if (!conn) {
    conn = mongoose.createConnection(uri, { maxPoolSize: 5 });
    conn.on('error', (err) => console.error('Tenant cluster connection error:', err.message));
    clusters.set(uri, conn);
  }
  return conn;
}

/** The named database on the given cluster (default: main cluster). */
function databaseFor(uri, dbName) {
  return clusterFor(uri).useDb(dbName, { useCache: true });
}

/** Database holding the platform registry (clients, licences, vendor logins). */
function platformDb() {
  return mongoose.connection.useDb(process.env.PLATFORM_DB_NAME || 'pwp_platform', { useCache: true });
}

async function closeAll() {
  await Promise.all([...clusters.values()].map((c) => c.close().catch(() => {})));
  clusters.clear();
}

module.exports = { databaseFor, platformDb, closeAll };
