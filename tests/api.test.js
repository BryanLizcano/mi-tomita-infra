const request = require('supertest');
const app     = require('../src/app');

describe('GET /health', () => {
  it('debe retornar status 200 y campo status=ok', async () => {
    const res = await request(app).get('/health');
    expect(res.statusCode).toBe(200);
    expect(res.body.status).toBe('ok');
    expect(res.body).toHaveProperty('timestamp');
    expect(res.body).toHaveProperty('hostname');
  });
});

describe('GET /status', () => {
  it('debe retornar status 200 con campos de uptime y db', async () => {
    const res = await request(app).get('/status');
    expect(res.statusCode).toBe(200);
    expect(res.body).toHaveProperty('uptime');
    expect(res.body).toHaveProperty('db');
    expect(res.body.status).toBe('running');
  });
});

describe('GET /api/test', () => {
  it('debe retornar mensaje y version', async () => {
    const res = await request(app).get('/api/test');
    expect(res.statusCode).toBe(200);
    expect(res.body).toHaveProperty('message');
    expect(res.body).toHaveProperty('version');
    expect(res.body.version).toBe('1.0.0');
  });
});

describe('GET /api/productos', () => {
  it('debe retornar lista de productos (mock sin DB)', async () => {
    const res = await request(app).get('/api/productos');
    expect(res.statusCode).toBe(200);
    expect(res.body).toHaveProperty('productos');
    expect(Array.isArray(res.body.productos)).toBe(true);
    expect(res.body.productos.length).toBeGreaterThan(0);
  });
});

describe('POST /api/productos', () => {
  it('debe retornar 400 si faltan campos', async () => {
    const res = await request(app).post('/api/productos').send({ nombre: 'test' });
    expect(res.statusCode).toBe(400);
    expect(res.body).toHaveProperty('error');
  });

  it('debe crear producto correctamente (mock sin DB)', async () => {
    const res = await request(app)
      .post('/api/productos')
      .send({ nombre: 'Pintura Rosa', precio: 2760 });
    expect(res.statusCode).toBe(201);
    expect(res.body.nombre).toBe('Pintura Rosa');
    expect(res.body.precio).toBe(2760);
  });
});
