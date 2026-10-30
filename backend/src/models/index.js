const mongoose = require('mongoose');
const { currentCoreDb, currentOutletDb } = require('../tenancy/context');

// Each model file registers its model on the default connection. The models
// exported here are thin proxies that, on every use, resolve to the same
// model on the current client's database (see tenancy/context): User on the
// client's core database, everything else on the current outlet's
// database. Outside a client request they are the default models, so
// scripts and the original single-cafe setup behave exactly as before.
// Controllers keep using `const { Order } = require('../models')` unchanged.
const defaults = {
  User: require('./User'),
  Customer: require('./Customer'),
  Category: require('./Category'),
  Product: require('./Product'),
  Order: require('./Order'),
  PaymentTransaction: require('./PaymentTransaction'),
  Counter: require('./Counter'),
  CreditTransaction: require('./CreditTransaction'),
  InventoryTransaction: require('./InventoryTransaction'),
  Expense: require('./Expense'),
  BusinessSettings: require('./BusinessSettings'),
  Table: require('./Table'),
  AuditLog: require('./AuditLog'),
  Feedback: require('./Feedback'),
  ImageAsset: require('./ImageAsset'),
  CashMovement: require('./CashMovement'),
  DayClose: require('./DayClose'),
  RefundTransaction: require('./RefundTransaction'),
  DailySummary: require('./DailySummary'),
  ArchiveRun: require('./ArchiveRun'),
};

const CORE_MODELS = new Set(['User']);

/** The real model `name` for the current client/outlet (or the default). */
function resolveModel(name) {
  const DefaultModel = defaults[name];
  const db = CORE_MODELS.has(name) ? currentCoreDb() : currentOutletDb();
  if (db === mongoose.connection) return DefaultModel;
  return modelOn(db, name);
}

/** Model `name` on an explicit database (used before a request context exists). */
function modelOn(db, name) {
  return db.models[name] || db.model(name, defaults[name].schema);
}

function tenantAware(name) {
  // A plain function target keeps Proxy invariants simple (its own
  // properties are all configurable/writable).
  return new Proxy(function TenantModel() {}, {
    get(_target, prop) {
      const Model = resolveModel(name);
      const value = Reflect.get(Model, prop, Model);
      return typeof value === 'function' && prop !== 'prototype' ? value.bind(Model) : value;
    },
    construct(_target, args) {
      return Reflect.construct(resolveModel(name), args);
    },
    has(_target, prop) {
      return prop in resolveModel(name);
    },
  });
}

/**
 * Creates every collection and index of a new outlet (or core) database up
 * front. Without it the first bill in a fresh database creates collections
 * inside its transaction, which retries and skips bill numbers.
 */
async function prepareDatabase(db, { core = false } = {}) {
  const names = Object.keys(defaults).filter((n) => CORE_MODELS.has(n) === core);
  for (const name of names) {
    const Model = modelOn(db, name);
    await Model.createCollection().catch((err) => {
      if (err.codeName !== 'NamespaceExists') throw err;
    });
    await Model.init();
  }
}

const models = {};
for (const name of Object.keys(defaults)) models[name] = tenantAware(name);

module.exports = { ...models, resolveModel, modelOn, prepareDatabase };
