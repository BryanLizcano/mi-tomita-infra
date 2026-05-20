#!/bin/bash
set -ex

DB_HOST="${db_host}"
DB_USER="${db_user}"
DB_PASSWORD="${db_password}"
DB_NAME="${db_name}"
REGION="${region}"

# 1. Instalar Node.js (AL2023 lo tiene en repos nativos)
dnf install -y nodejs

# 2. Crear la app directamente (sin git clone)
mkdir -p /opt/tomita-api
cd /opt/tomita-api

cat > package.json <<'PKGJSON'
{
  "name": "tomita-api",
  "version": "1.0.0",
  "dependencies": { "express": "^4.18.2" }
}
PKGJSON

npm install

# 3. Crear el servidor
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")
HOSTNAME=$(hostname)

cat > app.js <<APPJS
const express = require('express');
const app = express();
app.use(express.json());

app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString(), hostname: '$HOSTNAME', instance: '$INSTANCE_ID' });
});

app.get('/status', (req, res) => {
  res.json({ status: 'running', uptime: Math.floor(process.uptime()), hostname: '$HOSTNAME', instance: '$INSTANCE_ID', db_host: '$DB_HOST' });
});

app.get('/api/test', (req, res) => {
  res.json({ message: 'API Tomita funcionando correctamente', version: '1.0.0', server: '$HOSTNAME' });
});

app.get('/api/productos', (req, res) => {
  res.json({ productos: [
    { id: 1, nombre: 'Pintura Blanco Hueso', precio: 2500 },
    { id: 2, nombre: 'Pintura Azul Celeste', precio: 3200 },
    { id: 3, nombre: 'Pintura Blanco Mate', precio: 2800 },
    { id: 4, nombre: 'Pintura Verde', precio: 3120 },
    { id: 5, nombre: 'Pintura Lila', precio: 2800 }
  ]});
});

app.post('/api/productos', (req, res) => {
  const { nombre, precio } = req.body;
  if (!nombre || !precio) return res.status(400).json({ error: 'nombre y precio requeridos' });
  res.status(201).json({ id: Date.now(), nombre, precio });
});

app.listen(3000, () => console.log('Tomita API en puerto 3000 | ' + '$HOSTNAME'));
APPJS

# 4. Iniciar la app (nohup para que persista)
nohup node app.js > /var/log/tomita-api.log 2>&1 &
sleep 2
curl -s http://localhost:3000/health && echo " -> App OK" || echo " -> App FALLO"

echo "Bootstrap completado - Tomita API iniciada en puerto 3000"