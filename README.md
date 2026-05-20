# Tomita S.A.S. — Infraestructura AWS | Examen Final

**Estudiante:** Bryan Gonzalo Lizcano Duran  
**Curso:** Diseño y Gestión de Infraestructura Tecnológica — UPB  
**Docente:** Omar Pinzón Ardila

---

## Arquitectura

```
Internet
    │
    ▼
[Internet Gateway]
    │
    ▼
[ALB — tomita-alb]  ← SG-ALB: puerto 80 público
    │
    ├──────────────────┐
    ▼                  ▼
[EC2 app_1]       [EC2 app_2]   ← SG-EC2: puerto 3000 (solo desde ALB)
 us-east-1a        us-east-1b       puerto 22 (SSH admin)
    │                  │
    └──────┬───────────┘
           ▼
    [RDS Primary]     ← SG-RDS: puerto 3306 (solo desde SG-EC2)
    [RDS Replica]       (subredes privadas)
```

**Decisiones técnicas:**
- **ALB** distribuye tráfico round-robin → alta disponibilidad ante fallo de una instancia
- **2 AZs** (us-east-1a, us-east-1b) → resistencia a fallo de zona
- **RDS Primary + Read Replica** → redundancia de datos
- **Subredes privadas para RDS** → nunca expuesto a internet
- **Security Groups en cascada** → defensa en profundidad

---

## Secrets requeridos en GitHub

Ir a: **Settings → Secrets and variables → Actions → New repository secret**

| Secret                  | Valor                                              |
|-------------------------|----------------------------------------------------|
| `AWS_ACCESS_KEY_ID`     | Desde AWS Academy → AWS Details → CLI              |
| `AWS_SECRET_ACCESS_KEY` | Desde AWS Academy → AWS Details → CLI              |
| `AWS_SESSION_TOKEN`     | Desde AWS Academy → AWS Details → CLI (largo)      |
| `DB_PASSWORD`           | `TomitaPass2024!`                                  |

> ⚠️ El `AWS_SESSION_TOKEN` va **como secret**, nunca en `aws configure`

---

## Despliegue manual (si el pipeline no aplica)

```powershell
# 1. Limpiar estado anterior
Remove-Item -Recurse -Force .terraform -ErrorAction SilentlyContinue
Remove-Item -Force terraform.tfstate, terraform.tfstate.backup, .terraform.lock.hcl -ErrorAction SilentlyContinue

# 2. Configurar credenciales
aws configure set aws_access_key_id     TU_ACCESS_KEY
aws configure set aws_secret_access_key TU_SECRET_KEY
aws configure set region us-east-1
# El token va como variable de entorno (NO en aws configure):
$env:AWS_SESSION_TOKEN = "TU_TOKEN_LARGO_AQUI"

# 3. Crear Key Pair si no existe
aws ec2 create-key-pair --key-name tomita-key --query 'KeyMaterial' --output text > tomita-key.pem

# 4. Inicializar y aplicar
cd terraform
terraform init
terraform plan -var="db_password=TomitaPass2024!"
terraform apply -var="db_password=TomitaPass2024!" -auto-approve
terraform output

# 5. Esperar 3 minutos para que EC2 arranque la app
Start-Sleep -Seconds 180

# 6. Verificar
$DNS = terraform output -raw alb_dns_name
curl "http://$DNS/health"
curl "http://$DNS/api/productos"
```

---

## Prueba de desempeño

### Con k6 (recomendado para el video)
```bash
# Instalar k6 en Amazon Linux / EC2
sudo dnf install https://dl.k6.io/rpm/repo.rpm
sudo dnf install k6

# Ejecutar prueba
k6 run --env ALB_URL=http://TU_ALB_DNS tests/load-test.js
```

### Con Apache Benchmark (más simple)
```bash
# Instalar
sudo yum install -y httpd-tools   # Amazon Linux
sudo apt-get install -y apache2-utils   # Ubuntu

# Ejecutar
chmod +x tests/load-test.sh
./tests/load-test.sh http://TU_ALB_DNS
```

---

## Validación de endpoints (para el video)

```bash
ALB="http://tomita-alb-1141831403.us-east-1.elb.amazonaws.com"

# Health check
curl -s $ALB/health | python3 -m json.tool

# Status con DB
curl -s $ALB/status | python3 -m json.tool

# API test
curl -s $ALB/api/test | python3 -m json.tool

# Listar productos
curl -s $ALB/api/productos | python3 -m json.tool

# Crear producto
curl -s -X POST $ALB/api/productos \
  -H "Content-Type: application/json" \
  -d '{"nombre":"Pintura Roja","precio":2900}' | python3 -m json.tool

# Evidencia del balanceador (hostname debe alternar)
for i in 1 2 3 4 5 6; do
  echo "Request $i: $(curl -s $ALB/health | grep -o '"hostname":"[^"]*"')"
done
```

---

## Checklist rúbrica

- [ ] **Arquitectura (10%)**: Diagrama con VPC, subredes, ALB, EC2, RDS, SGs, CI/CD, flujo de tráfico
- [ ] **Terraform (25%)**: `terraform init` ✅ `terraform plan` ✅ `terraform apply` ✅ `terraform output` ✅
- [ ] **Servicio (10%)**: Endpoints `/health`, `/status`, `/api/test`, `/api/productos` respondiendo
- [ ] **CI/CD (25%)**: GitHub Actions ejecutando tests + validate + apply, con secrets configurados
- [ ] **Desempeño (30%)**: k6 o ab ejecutado, hostname alternando en ALB, métricas en CloudWatch
