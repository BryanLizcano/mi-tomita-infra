#!/bin/bash
set -ex

# 1. Actualizar sistema e instalar utilidades en Amazon Linux 2
yum update -y
yum install -y curl git

# 2. Instalar Node.js de forma directa y nativa para Amazon Linux
curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
yum install -y nodejs

# 3. Crear directorio de la aplicación
mkdir -p /opt/tomita-api
cd /opt/tomita-api

# 4. Crear el package.json
cat > package.json << 'EOF'
{
  "name": "tomita-api",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF

# 5. Instalar express
npm install

# 6. Crear el servidor API (Código limpio sin variables problemáticas)
cat > app.js << 'EOF'
const express = require('express');
const app = express();

app.use(express.json());

app.get('/health', (req, res) => {
    res.json({ status: 'ok', server: 'EC2-Activa-Balanceada' });
});

app.get('/api/productos', (req, res) => {
    res.json({
        productos: [
            { id: 1, nombre: 'Pintura Blanco Hueso', precio: 2500 },
            { id: 2, nombre: 'Pintura Azul Celeste', precio: 3200 },
            { id: 3, nombre: 'Pintura Blanco Mate', precio: 2800 },
            { id: 4, nombre: 'Pintura Verde', precio: 3120 },
            { id: 5, nombre: 'Pintura Lila', precio: 2800 }
        ]
    });
});

app.listen(3000, () => {
    console.log('App iniciada en el puerto 3000');
});
EOF

# 7. Iniciar la aplicación para que persista
nohup node app.js > /var/log/tomita-api.log 2>&1 &