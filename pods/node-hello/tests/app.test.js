const request = require('supertest');
const app = require('../src/app');

describe('Node.js Hello World API', () => {
  
  describe('GET /', () => {
    it('should return service information', async () => {
      const response = await request(app)
        .get('/')
        .expect('Content-Type', /json/)
        .expect(200);

      expect(response.body).toHaveProperty('message', 'Hello from Node.js!');
      expect(response.body).toHaveProperty('service', 'node-hello');
      expect(response.body).toHaveProperty('version', '1.0.0');
      expect(response.body).toHaveProperty('timestamp');
    });
  });

  describe('GET /hello', () => {
    it('should return a simple greeting', async () => {
      const response = await request(app)
        .get('/hello')
        .expect('Content-Type', /text/)
        .expect(200);

      expect(response.text).toContain('Hello World from Node.js Express server!');
    });
  });

  describe('GET /hello/json', () => {
    it('should return detailed JSON response', async () => {
      const response = await request(app)
        .get('/hello/json')
        .expect('Content-Type', /json/)
        .expect(200);

      expect(response.body).toHaveProperty('greeting', 'Hello World!');
      expect(response.body).toHaveProperty('technology', 'Node.js + Express');
      expect(response.body).toHaveProperty('platform', 'Shadok');
      expect(response.body).toHaveProperty('features');
      expect(Array.isArray(response.body.features)).toBe(true);
      expect(response.body).toHaveProperty('uptime');
      expect(response.body).toHaveProperty('nodeVersion');
    });
  });

  describe('GET /health', () => {
    it('should return health status', async () => {
      const response = await request(app)
        .get('/health')
        .expect('Content-Type', /json/)
        .expect(200);

      expect(response.body).toHaveProperty('status', 'UP');
      expect(response.body).toHaveProperty('service', 'node-hello');
      expect(response.body).toHaveProperty('timestamp');
      expect(response.body).toHaveProperty('uptime');
      expect(response.body).toHaveProperty('memory');
    });
  });

  describe('GET /ready', () => {
    it('should return readiness status', async () => {
      const response = await request(app)
        .get('/ready')
        .expect('Content-Type', /json/)
        .expect(200);

      expect(response.body).toHaveProperty('status', 'READY');
      expect(response.body).toHaveProperty('service', 'node-hello');
      expect(response.body).toHaveProperty('timestamp');
    });
  });

  describe('GET /nonexistent', () => {
    it('should return 404 for unknown routes', async () => {
      const response = await request(app)
        .get('/nonexistent')
        .expect('Content-Type', /json/)
        .expect(404);

      expect(response.body).toHaveProperty('error', 'Not Found');
      expect(response.body).toHaveProperty('availableRoutes');
      expect(Array.isArray(response.body.availableRoutes)).toBe(true);
    });
  });
});
