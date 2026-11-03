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

// Every bill touches the same counter documents, so transactions on one
// outlet that overlap conflict and retry each other: under load the retries
// pile up until bills take minutes. Running them one at a time per outlet
// keeps a queue of short waits instead. MongoDB's own retry stays in place
// for anything this process cannot see, such as a second server instance.
const transactionQueues = new WeakMap();

function runInTurn(db, task) {
  const tail = transactionQueues.get(db) || Promise.resolve();
  const run = tail.then(task, task);
  transactionQueues.set(db, run.catch(() => {}));
  return run;
}

/** Starts a transaction session on the current outlet's database. */
async function startSession() {
  const db = currentOutletDb();
  const session = await db.startSession();
  const withTransaction = session.withTransaction.bind(session);
  session.withTransaction = (fn, options) => runInTurn(db, () => withTransaction(fn, options));
  return session;
}

module.exports = {
  runWithContext,
  currentContext,
  currentOutletDb,
  currentCoreDb,
  startSession,
};
