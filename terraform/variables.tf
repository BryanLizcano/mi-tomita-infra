variable "aws_region" {
  description = "Region de AWS"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Ambiente de despliegue"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Prefijo de nombre para todos los recursos"
  type        = string
  default     = "tomita"
}

# ── Red ─────────────────────────────────────
variable "vpc_cidr" {
  description = "CIDR del VPC principal"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_1_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "public_subnet_2_cidr" {
  type    = string
  default = "10.0.2.0/24"
}

variable "private_subnet_1_cidr" {
  type    = string
  default = "10.0.3.0/24"
}

variable "private_subnet_2_cidr" {
  type    = string
  default = "10.0.4.0/24"
}

# ── EC2 ──────────────────────────────────────
variable "ami_id" {
  description = "AMI Amazon Linux 2023 en us-east-1"
  type        = string
  default     = "ami-0f9fc25dd2506cf6d"
}

variable "instance_type" {
  description = "Tipo de instancia EC2"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Nombre del Key Pair en AWS (crear en consola)"
  type        = string
  default     = "tomita-key"
}

variable "asg_min_size" {
  type    = number
  default = 2
}

variable "asg_max_size" {
  type    = number
  default = 4
}

variable "asg_desired" {
  type    = number
  default = 2
}

# ── RDS ──────────────────────────────────────
variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_name" {
  description = "Nombre de la base de datos"
  type        = string
  default     = "tomitadb"
}

variable "db_username" {
  description = "Usuario administrador de RDS"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "db_password" {
  description = "Contraseña de RDS — definir en tfvars o variable de entorno"
  type        = string
  sensitive   = true
}
