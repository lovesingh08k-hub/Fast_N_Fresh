const { AsyncLocalStorage } = require('async_hooks');
const mongoose = require('mongoose');

// Which client (tenant) and outlet the current request works on.
//
// Every request that belongs to a client runs inside `runWithContext`, and
// the models exported from ../models resolve to that client's databases:
//   - coreDb:   the client's users (shared by all its outlets)
//   - outletDb: everything else (orders, customers, menu, tables, ...),
//               one database per outlet, so outlets never see each
//               other's customers or bills.
// Code that runs outside a request (scripts, legacy single-cafe setup)
// has no context and uses the default mongoose connection, exactly as
// before multi-tenancy.
const storage = new AsyncLocalStorage();

/**
 * @typedef {object} TenantContext
 * @property {object} tenant            Tenant document (platform registry)
 * @property {object} outlet            Outlet sub-document of the tenant
 * @property {mongoose.Connection} coreDb
 * @property {mongoose.Connection} outletDb
 */

function runWithContext(ctx, fn) {
  return storage.run(ctx, fn);
}

/** @returns {TenantContext|undefined} */
function currentContext() {
  return storage.getStore();
}

function currentOutletDb() {
  return currentContext()?.outletDb || mongoose.connection;
}

function currentCoreDb() {
  return currentContext()?.coreDb || mongoose.connection;
}

/** Starts a transaction session on the current outlet's database. */
function startSession() {
  return currentOutletDb().startSession();
}

module.exports = {
  runWithContext,
  currentContext,
  currentOutletDb,
  currentCoreDb,
  startSession,
};
