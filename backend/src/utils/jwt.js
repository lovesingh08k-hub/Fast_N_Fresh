const jwt = require('jsonwebtoken');

// `tenant` is the client the user belongs to (absent in a single-cafe
// setup without a platform registry).
function signToken(user, tenant) {
  return jwt.sign(
    {
      sub: user._id.toString(),
      role: user.role,
      tokenVersion: user.tokenVersion,
      ...(tenant ? { tid: tenant._id.toString() } : {}),
    },
    process.env.JWT_SECRET,
    { expiresIn: process.env.JWT_EXPIRES_IN || '7d' }
  );
}

function verifyToken(token) {
  return jwt.verify(token, process.env.JWT_SECRET);
}

module.exports = { signToken, verifyToken };
