const mongoose = require('mongoose');
const dns = require('dns');

async function connectDB() {
  const uri = process.env.MONGODB_URI;

  if (!uri) {
    throw new Error('MONGODB_URI is not set in environment variables.');
  }

  // MongoDB Atlas SRV records can fail with some ISP DNS resolvers.
  // Keep the explicit resolver used by this deployment.
  dns.setServers(['8.8.8.8', '8.8.4.4']);

  mongoose.set('strictQuery', true);

  try {
    await mongoose.connect(uri);
    console.log(`MongoDB connected: ${mongoose.connection.host}/${mongoose.connection.name}`);
  } catch (err) {
    console.error('MongoDB connection error:', err.message);
    throw err;
  }

  mongoose.connection.on('disconnected', () => {
    console.warn('MongoDB disconnected');
  });
}

module.exports = connectDB;
