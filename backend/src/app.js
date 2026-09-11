require('dotenv').config();

const dns = require('dns');
const mongoose = require('mongoose');

// Use reliable public DNS servers for MongoDB Atlas SRV resolution.
// This avoids the ECONNREFUSED issue from the ISP DNS resolver.
dns.setServers([
  '8.8.8.8',
  '8.8.4.4',
]);

const express = require('express');
const path = require('path');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');
const crypto = require('crypto');
const mongoSanitize = require('express-mongo-sanitize');

const connectDB = require('./config/db');
const routes = require('./routes');
const { notFound, errorHandler } = require('./middleware/errorHandler');
const { ImageAsset } = require('./models');

const app = express();

// Render/Reverse-proxy aware client IP handling. Keep this to one hop so
// rate limits use the real client IP without trusting an arbitrary chain.
app.set('trust proxy', 1);

// Every response gets a correlation id. Clients can quote this id when
// reporting a failed order/payment, while server logs can trace the request.
app.use((req, res, next) => {
  const incoming = String(req.get('X-Request-Id') || '').trim();
  const requestId = /^[A-Za-z0-9._:-]{8,80}$/.test(incoming) ? incoming : crypto.randomUUID();
  req.requestId = requestId;
  res.setHeader('X-Request-Id', requestId);
  next();
});

const apiLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: Number(process.env.API_RATE_LIMIT_MAX) || 240,
  standardHeaders: true,
  legacyHeaders: false,
  skip: (req) => req.path === '/health',
  message: { success: false, message: 'Too many requests. Please try again shortly.' },
});

// Security & parsing middleware
// crossOriginResourcePolicy relaxed so product images can be loaded by the
// Flutter app (a different origin) — everything else stays locked down.
app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
app.use(express.json({ limit: '2mb' }));
app.use(mongoSanitize());
app.use('/api', apiLimiter);

const configuredCorsOrigins = (process.env.CORS_ORIGIN || '')
  .split(',')
  .map((o) => o.trim())
  .filter(Boolean);
const isProduction = process.env.NODE_ENV === 'production';

const corsMiddleware = cors({
  origin(origin, callback) {
    // Native Flutter requests normally have no Origin header and remain
    // allowed. Cross-origin browser access is deny-by-default in production
    // unless explicitly listed in CORS_ORIGIN.
    if (!origin) return callback(null, true);
    if (configuredCorsOrigins.includes('*') || configuredCorsOrigins.includes(origin)) {
      return callback(null, true);
    }
    if (!isProduction && configuredCorsOrigins.length === 0) return callback(null, true);
    return callback(new Error('Origin not allowed by CORS'));
  },
  credentials: false,
});

app.use((req, res, next) => {
  const origin = req.get('Origin');
  const sameOrigin = origin && origin === `${req.protocol}://${req.get('host')}`;
  // Same-origin requests from the bundled /menu page do not need CORS at all.
  if (!origin || sameOrigin) return next();
  return corsMiddleware(req, res, next);
});

if (process.env.NODE_ENV !== 'test') {
  app.use(
    morgan(
      process.env.NODE_ENV === 'production'
        ? 'combined'
        : 'dev'
    )
  );
}

// Serves uploaded product photos at e.g. GET /uploads/products/xyz.jpg —
// the Flutter app stores/loads the relative URL returned at upload time and
// resolves it against ApiConfig.baseUrl, so no path is ever hard-coded.
app.get('/uploads/products/:assetId', async (req, res, next) => {
  try {
    if (!mongoose.Types.ObjectId.isValid(req.params.assetId)) return next();
    const asset = await ImageAsset.findById(req.params.assetId).select('data contentType');
    if (!asset) return next();
    res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
    res.type(asset.contentType);
    res.send(asset.data);
  } catch (err) {
    next(err);
  }
});

// Legacy disk-backed images remain supported for old products. New uploads
// use the Mongo-backed route above and therefore survive Render restarts.
app.use(
  '/uploads',
  express.static(path.join(__dirname, '..', 'uploads'))
);

// Customer-facing QR menu. Hosting it on the same Render service as the
// API removes the extra Static Site dependency and guarantees that QR codes
// always open a reachable HTTPS page. Query strings such as ?table=5 are
// handled by the menu JavaScript.
app.use('/menu', express.static(path.join(__dirname, '..', 'public', 'menu'), {
  index: 'index.html',
}));

app.get('/', (req, res) => {
  res.json({
    success: true,
    message: 'FAST N FRESH CAFE API',
    version: '1.1.0',
  });
});

// DB-aware health endpoint. Render/proxies can distinguish a running process
// from an API that is actually ready to authenticate users.
app.get('/health', (req, res) => {
  const ready = mongoose.connection.readyState === 1;
  res.status(ready ? 200 : 503).json({
    success: ready,
    status: ready ? 'ok' : 'starting',
    database: ready ? 'connected' : 'disconnected',
    requestId: req.requestId,
  });
});

app.use('/api', routes);

app.use(notFound);
app.use(errorHandler);

const PORT = process.env.PORT || 5000;

async function start() {
  // Bind the HTTP port before MongoDB connects so Render/load balancers can
  // reach /health and observe a truthful 503 while the database is starting.
  const server = app.listen(PORT, () => {
    console.log(
      `Fast N Fresh Cafe API listening on port ${PORT} [${process.env.NODE_ENV || 'development'}]`
    );
  });

  let stopping = false;

  const connectWithRetry = async () => {
    while (!stopping && mongoose.connection.readyState !== 1) {
      try {
        await connectDB();
        console.log('MongoDB is ready.');
      } catch (err) {
        if (stopping) return;
        console.error('[DB] Initial connection failed; retrying in 5 seconds.');
        await new Promise((resolve) => setTimeout(resolve, 5000));
      }
    }
  };

  void connectWithRetry();

  const shutdown = async (signal) => {
    stopping = true;
    console.log(`[SHUTDOWN] ${signal}`);
    server.close(async () => {
      try { await mongoose.connection.close(false); } catch (_) {}
      process.exit(0);
    });
    setTimeout(() => process.exit(1), 10000).unref();
  };
  process.once('SIGTERM', () => shutdown('SIGTERM'));
  process.once('SIGINT', () => shutdown('SIGINT'));
}

start();

module.exports = app;