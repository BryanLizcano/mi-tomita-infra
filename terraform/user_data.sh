#!/bin/bash
set -ex

# ── Variables inyectadas por Terraform templatefile ──────────────────────────
DB_HOST="${db_host}"
DB_USER="${db_user}"
DB_PASSWORD="${db_password}"
DB_NAME="${db_name}"
REGION="${region}"

# ── 1. Actualizar sistema e instalar utilidades (Amazon Linux 2023 / AL2) ────
yum update -y
yum install -y curl git

# ── 2. Instalar Node.js 18 via NodeSource (nativo para ecosistema RPM) ────────
curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
yum install -y nodejs

# Verificar instalación
node --version
npm --version

# ── 3. Crear directorio de aplicación ─────────────────────────────────────────
mkdir -p /opt/tomita-api
cd /opt/tomita-api

# ── 4. package.json (heredoc con comillas para evitar expansión de shell) ─────
cat > package.json << 'PKGJSON'
{
  "name": "tomita-api",
  "version": "1.0.0",
  "description": "API REST - Empresa Tomita S.A.S",
  "main": "app.js",
  "scripts": {
    "start": "node app.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "mysql2": "^3.6.0"
  }
}
PKGJSON

npm install

# ── 5. Escribir archivo de configuración de entorno ───────────────────────────
# NOTA: No usar heredoc con 'EOF' aqui para que bash expanda las variables
cat > /opt/tomita-api/.env << ENVEOF
NODE_ENV=production
PORT=3000
DB_HOST=$DB_HOST
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_NAME=$DB_NAME
AWS_REGION=$REGION
ENVEOF

# ── 6. Crear app.js principal ─────────────────────────────────────────────────
# CRITICO: usar $${VAR} para que Terraform no interpole variables de bash.
cat > app.js << 'APPEOF'
const express = require('express');
const mysql   = require('mysql2/promise');
const os      = require('os');

const app  = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());

// Pool de conexión a RDS (graceful: funciona sin DB)
let pool = null;
if (process.env.DB_HOST) {
  pool = mysql.createPool({
    host:            process.env.DB_HOST,
    user:            process.env.DB_USER    || 'admin',
    password:        process.env.DB_PASSWORD,
    database:        process.env.DB_NAME    || 'tomitadb',
    waitForConnections: true,
    connectionLimit: 10,
    connectTimeout:  5000,
  });
}

// GET /health
app.get('/health', (req, res) => {
  res.status(200).json({
    status:    'ok',
    timestamp: new Date().toISOString(),
    hostname:  os.hostname(),
  });
});

// GET /status
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

// GET /api/test
app.get('/api/test', (req, res) => {
  res.json({
    message: 'API Tomita funcionando correctamente',
    version: '1.0.0',
    server:  os.hostname(),
  });
});

// GET /api/productos
app.get('/api/productos', async (req, res) => {
  if (!pool) {
    return res.json({
      productos: [
        { id: 1, nombre: 'Pintura Blanco Hueso', precio: 2500 },
        { id: 2, nombre: 'Pintura Azul Celeste',  precio: 3200 },
        { id: 3, nombre: 'Pintura Blanco Mate',   precio: 2800 },
        { id: 4, nombre: 'Pintura Verde',          precio: 3120 },
        { id: 5, nombre: 'Pintura Lila',           precio: 2800 },
      ],
    });
  }
  const [rows] = await pool.query('SELECT * FROM productos LIMIT 20');
  res.json({ productos: rows });
});

// POST /api/productos
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
  console.log(`Servidor en puerto $${PORT} | host: $${os.hostname()}`);
});

module.exports = app;
APPEOF

# ── 7. Inicializar base de datos (esperar que RDS esté disponible) ─────────────
sleep 40
node -e "
const mysql = require('mysql2/promise');
async function init() {
  try {
    const conn = await mysql.createConnection({
      host: '$DB_HOST', user: '$DB_USER', password: '$DB_PASSWORD', connectTimeout: 10000
    });
    await conn.query('CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`');
    await conn.query('USE \`$DB_NAME\`');
    await conn.query(\`
      CREATE TABLE IF NOT EXISTS productos (
        id         INT AUTO_INCREMENT PRIMARY KEY,
        nombre     VARCHAR(100) NOT NULL,
        precio     DECIMAL(10,2) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    \`);
    await conn.query(\`
      INSERT IGNORE INTO productos (id, nombre, precio) VALUES
        (1,'Pintura Blanco Hueso',2500),
        (2,'Pintura Azul Celeste',3200),
        (3,'Pintura Blanco Mate',2800),
        (4,'Pintura Verde',3120),
        (5,'Pintura Lila',2800)
    \`);
    console.log('DB inicializada correctamente');
    await conn.end();
  } catch(err) {
    console.error('DB init error (no critico):', err.message);
  }
}
init();
" || true

# ── 8. Cargar variables de entorno e iniciar la aplicación ────────────────────
export $(grep -v '^#' /opt/tomita-api/.env | xargs)
nohup node /opt/tomita-api/app.js > /var/log/tomita-api.log 2>&1 &
APP_PID=$!
echo "Aplicacion iniciada con PID: $APP_PID"

# ── 9. Configurar inicio automático con systemd ───────────────────────────────
cat > /etc/systemd/system/tomita-api.service << SVCEOF
[Unit]
Description=Tomita API Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/tomita-api
EnvironmentFile=/opt/tomita-api/.env
ExecStart=/usr/bin/node /opt/tomita-api/app.js
Restart=always
RestartSec=10
StandardOutput=append:/var/log/tomita-api.log
StandardError=append:/var/log/tomita-api.log

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable tomita-api
systemctl start tomita-api

# ── 10. CloudWatch Agent ──────────────────────────────────────────────────────
yum install -y amazon-cloudwatch-agent

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWCONF'
{
  "agent": { "metrics_collection_interval": 60 },
  "metrics": {
    "metrics_collected": {
      "cpu":  { "measurement": ["cpu_usage_active"],   "metrics_collection_interval": 60 },
      "mem":  { "measurement": ["mem_used_percent"],   "metrics_collection_interval": 60 },
      "disk": { "measurement": ["disk_used_percent"],  "resources": ["/"], "metrics_collection_interval": 60 }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/tomita-api.log",
            "log_group_name": "/tomita/api",
            "log_stream_name": "{instance_id}",
            "timestamp_format": "%Y-%m-%dT%H:%M:%S"
          }
        ]
      }
    }
  }
}
CWCONF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

echo "Bootstrap completado exitosamente - $(date)"