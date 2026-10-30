// Users live in the client's core database while orders, expenses, etc.
// live in each outlet's database. Schemas point their user references here
// (instead of the plain name 'User') so populate() always reads users from
// the right database. Outside a client request it is the default User model.
module.exports = function userRef() {
  // Lazy require: models/index requires the schema files that use this.
  return require('./index').resolveModel('User');
};
