const express = require('express');
const mysql = require('mysql2/promise');
const os = require('os');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());

// Pool de conexión a RDS (graceful: funciona sin DB)
let pool = null;
if (process.env.DB_HOST) {
  pool = mysql.createPool({
    host:            process.env.DB_HOST,
    user:            process.env.DB_USER  || 'admin',
    password:        process.env.DB_PASSWORD,
    database:        process.env.DB_NAME  || 'tomitadb',
    waitForConnections: true,
    connectionLimit: 10,
    connectTimeout:  5000,
  });
}

// ── GET /health ──────────────────────────────
app.get('/health', (req, res) => {
  res.status(200).json({
    status:    'ok',
    timestamp: new Date().toISOString(),
    hostname:  os.hostname(),
  });
});

// ── GET /status ──────────────────────────────
app.get('/status', async (req, res) => {
  let dbStatus = 'not_configured';
  if (pool) {
    try {
      await pool.query('SELECT 1');
      dbStatus = 'connected';
    } catch {
      dbStatus = 'error';
    }
  }
  res.json({
    status:   'running',
    uptime:   Math.floor(process.uptime()),
    hostname: os.hostname(),
    db:       dbStatus,
    env:      process.env.NODE_ENV || 'production',
  });
});

// ── GET /api/test ─────────────────────────────
app.get('/api/test', (req, res) => {
  res.json({
    message: 'API Tomita funcionando correctamente',
    version: '1.0.0',
    server:  os.hostname(),
  });
});

// ── GET /api/productos ───────────────────────
app.get('/api/productos', async (req, res) => {
  if (!pool) {
    return res.json({
      productos: [
        { id: 1, nombre: 'Pintura Blanco Hueso', precio: 2500 },
        { id: 2, nombre: 'Pintura Azul Celeste',  precio: 3200 },
        { id: 3, nombre: 'Pintura Verde',          precio: 3120 },
      ],
    });
  }
  const [rows] = await pool.query('SELECT * FROM productos LIMIT 20');
  res.json({ productos: rows });
});

// ── POST /api/productos ──────────────────────
app.post('/api/productos', async (req, res) => {
  const { nombre, precio } = req.body;
  if (!nombre || !precio) {
    return res.status(400).json({ error: 'nombre y precio son requeridos' });
  }
  if (!pool) {
    return res.status(201).json({ id: Date.now(), nombre, precio });
  }
  const [result] = await pool.query(
    'INSERT INTO productos (nombre, precio) VALUES (?, ?)',
    [nombre, precio]
  );
  res.status(201).json({ id: result.insertId, nombre, precio });
});

app.listen(PORT, () => {
  console.log(`Servidor iniciado en puerto ${PORT} | host: ${os.hostname()}`);
});

module.exports = app;
