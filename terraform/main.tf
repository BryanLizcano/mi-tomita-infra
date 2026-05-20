# ═══════════════════════════════════════════════════════════════
# VPC
# ═══════════════════════════════════════════════════════════════
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "${var.project_name}-vpc" }
}

# ── Internet Gateway ────────────────────────────────────────────
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

# ═══════════════════════════════════════════════════════════════
# SUBNETS  (2 públicas para ALB+EC2 | 2 privadas para RDS)
# ═══════════════════════════════════════════════════════════════
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_1_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags = { Name = "${var.project_name}-public-1a" }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_2_cidr
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true
  tags = { Name = "${var.project_name}-public-1b" }
}

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_1_cidr
  availability_zone = "${var.aws_region}a"
  tags = { Name = "${var.project_name}-private-1a" }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_2_cidr
  availability_zone = "${var.aws_region}b"
  tags = { Name = "${var.project_name}-private-1b" }
}

# ── Route Tables ────────────────────────────────────────────────
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.project_name}-rt-public" }
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# ═══════════════════════════════════════════════════════════════
# SECURITY GROUPS
# ═══════════════════════════════════════════════════════════════

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-sg-alb"
  description = "Permite HTTP desde Internet hacia el ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP publico"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-sg-alb" }
}

resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-sg-ec2"
  description = "Permite trafico del ALB al puerto 3000 de las instancias"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "App port desde ALB"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH administracion"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-sg-ec2" }
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-sg-rds"
  description = "Permite MySQL 3306 solo desde EC2 privado"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
    description     = "MySQL desde EC2 unicamente"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-sg-rds" }
}

# ═══════════════════════════════════════════════════════════════
# APPLICATION LOAD BALANCER
# ═══════════════════════════════════════════════════════════════
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  tags               = { Name = "${var.project_name}-alb" }
}

resource "aws_lb_target_group" "app" {
  name     = "${var.project_name}-tg"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200"
  }

  tags = { Name = "${var.project_name}-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ═══════════════════════════════════════════════════════════════
# EC2 INSTANCES (2 en AZs distintas → alta disponibilidad)
# ═══════════════════════════════════════════════════════════════
resource "aws_instance" "app_1" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.ec2.id]

  user_data = templatefile("${path.module}/user_data.sh", {
    db_host     = aws_db_instance.primary.address
    db_user     = var.db_username
    db_password = var.db_password
    db_name     = var.db_name
    region      = var.aws_region
  })

  tags = { Name = "${var.project_name}-ec2-1a" }

  root_block_device {
    volume_type = "gp2"
    volume_size = 8
    encrypted   = false
  }
}

resource "aws_instance" "app_2" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.public_2.id
  vpc_security_group_ids = [aws_security_group.ec2.id]

  user_data = templatefile("${path.module}/user_data.sh", {
    db_host     = aws_db_instance.primary.address
    db_user     = var.db_username
    db_password = var.db_password
    db_name     = var.db_name
    region      = var.aws_region
  })

  tags = { Name = "${var.project_name}-ec2-1b" }

  root_block_device {
    volume_type = "gp2"
    volume_size = 8
    encrypted   = false
  }
}

# Registrar instancias en el Target Group del ALB
resource "aws_lb_target_group_attachment" "app_1" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.app_1.id
  port             = 3000
}

resource "aws_lb_target_group_attachment" "app_2" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.app_2.id
  port             = 3000
}

# ═══════════════════════════════════════════════════════════════
# RDS MYSQL — Primary + Read Replica (red privada)
# ═══════════════════════════════════════════════════════════════
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]
  tags       = { Name = "${var.project_name}-db-subnet-group" }
}

resource "aws_db_instance" "primary" {
  identifier              = "${var.project_name}-db-primary"
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = var.db_instance_class
  allocated_storage       = 20
  storage_type            = "gp2"
  db_name                 = var.db_name
  username                = var.db_username
  password                = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  skip_final_snapshot     = true
  backup_retention_period = 1
  publicly_accessible     = false

  tags = { Name = "${var.project_name}-db-primary" }
}

resource "aws_db_instance" "replica" {
  identifier             = "${var.project_name}-db-replica"
  replicate_source_db    = aws_db_instance.primary.identifier
  instance_class         = var.db_instance_class
  skip_final_snapshot    = true
  publicly_accessible    = false
  vpc_security_group_ids = [aws_security_group.rds.id]

  tags = { Name = "${var.project_name}-db-replica" }
}

# ═══════════════════════════════════════════════════════════════
# CLOUDWATCH — Alarmas
# ═══════════════════════════════════════════════════════════════
resource "aws_cloudwatch_metric_alarm" "high_cpu_1" {
  alarm_name          = "${var.project_name}-high-cpu-1a"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "CPU supera 70% en instancia 1a"
  dimensions = {
    InstanceId = aws_instance.app_1.id
  }
}

resource "aws_cloudwatch_metric_alarm" "high_cpu_2" {
  alarm_name          = "${var.project_name}-high-cpu-1b"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "CPU supera 70% en instancia 1b"
  dimensions = {
    InstanceId = aws_instance.app_2.id
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.project_name}-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Errores 5xx en el ALB supera 10 por minuto"
  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }
}
