provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "zgaming" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.zgaming.id
  cidr_block = "10.0.1.0/24"
}

resource "aws_subnet" "private" {
  vpc_id     = aws_vpc.zgaming.id
  cidr_block = "10.0.2.0/24"
}

resource "aws_db_instance" "mysql" {
  engine               = "mysql"
  instance_class       = "db.t3.micro"
  allocated_storage    = 20
  username             = var.db_user
  password             = var.db_password
  skip_final_snapshot  = true
}

resource "aws_ecs_cluster" "zgaming" {
  name = "zgaming-cluster"
}

resource "aws_kms_key" "wallet" {
  description = "Wallet signing key"
}

resource "aws_secretsmanager_secret" "db" {
  name = "zgaming-db"
}

resource "aws_cloudwatch_log_group" "app" {
  name = "/zgaming/app"
}

output "db_endpoint" {
  value = aws_db_instance.mysql.endpoint
}
