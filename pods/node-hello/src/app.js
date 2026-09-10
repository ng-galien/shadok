const express = require('express');
const helmet = require('helmet');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 3000;
const HOST = process.env.HOST || '0.0.0.0';

// Security middleware
app.use(helmet());
app.use(cors());
app.use(express.json());

// Root route
app.get('/', (req, res) => {
  res.json({
    message: 'Hello from Node.js!',
    service: 'node-hello',
    version: '1.0.0',
    timestamp: new Date().toISOString(),
    environment: process.env.NODE_ENV || 'development'
  });
});

// Plain-text greeting route
app.get('/hello', (req, res) => {
  res.send('Hello World from Node.js Express server! 🚀');
});

// JSON greeting route
app.get('/hello/json', (req, res) => {
  res.json({
    greeting: 'Hello World!',
    technology: 'Node.js + Express',
    platform: 'Shadok',
    features: [
      'Express.js web framework',
      'Live reload with nodemon',
      'Security with Helmet',
      'CORS support',
      'JSON responses',
      'Health checks'
    ],
    uptime: process.uptime(),
    memory: process.memoryUsage(),
    nodeVersion: process.version
  });
});

// Health route
app.get('/health', (req, res) => {
  res.json({
    status: 'UP',
    service: 'node-hello',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    memory: process.memoryUsage(),
    version: process.version
  });
});

// Kubernetes readiness route
app.get('/ready', (req, res) => {
  res.json({
    status: 'READY',
    service: 'node-hello',
    timestamp: new Date().toISOString()
  });
});

// Error-handling middleware
app.use((err, req, res, _next) => {
  console.error('Error:', err.message);
  res.status(500).json({
    error: 'Internal Server Error',
    message: process.env.NODE_ENV === 'development' ? err.message : 'Something went wrong!'
  });
});

// Not-found middleware
app.use('*', (req, res) => {
  res.status(404).json({
    error: 'Not Found',
    message: `Route ${req.originalUrl} not found`,
    availableRoutes: [
      'GET /',
      'GET /hello',
      'GET /hello/json',
      'GET /health',
      'GET /ready'
    ]
  });
});

// Export the application for tests
module.exports = app;

// Start the server only when this file is executed directly
if (require.main === module) {
  const server = app.listen(PORT, HOST, () => {
    console.log('🚀 Node.js Hello World server started');
    console.log(`🌐 Server running on http://${HOST}:${PORT}`);
    console.log(`📊 Environment: ${process.env.NODE_ENV || 'development'}`);
    console.log(`🔧 Node.js version: ${process.version}`);
    console.log('');
    console.log('Available endpoints:');
    console.log(`  GET http://localhost:${PORT}/          - Service info`);
    console.log(`  GET http://localhost:${PORT}/hello     - Simple greeting`);
    console.log(`  GET http://localhost:${PORT}/hello/json - Detailed JSON response`);
    console.log(`  GET http://localhost:${PORT}/health    - Health check`);
    console.log(`  GET http://localhost:${PORT}/ready     - Readiness check`);
  });

  // Graceful shutdown
  process.on('SIGTERM', () => {
    console.log('📱 SIGTERM received, shutting down gracefully...');
    server.close(() => {
      console.log('✅ Server closed');
      process.exit(0);
    });
  });

  process.on('SIGINT', () => {
    console.log('📱 SIGINT received, shutting down gracefully...');
    server.close(() => {
      console.log('✅ Server closed');
      process.exit(0);
    });
  });
}
