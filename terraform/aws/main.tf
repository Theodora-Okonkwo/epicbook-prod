terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws   = { source = "hashicorp/aws",   version = "~> 5.0" }
    tls   = { source = "hashicorp/tls",   version = "~> 4.0" }
    local = { source = "hashicorp/local", version = "~> 2.0" }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "aws_vpc" "epicbook_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "epicbook-vpc", Project = "EpicBook" }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.epicbook_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags = { Name = "epicbook-public-subnet", Project = "EpicBook" }
}

resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.epicbook_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}b"
  tags = { Name = "epicbook-private-subnet-a", Project = "EpicBook" }
}

resource "aws_subnet" "private_subnet_b" {
  vpc_id            = aws_vpc.epicbook_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "${var.aws_region}c"
  tags = { Name = "epicbook-private-subnet-b", Project = "EpicBook" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.epicbook_vpc.id
  tags   = { Name = "epicbook-igw", Project = "EpicBook" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.epicbook_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "epicbook-public-rt", Project = "EpicBook" }
}

resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_security_group" "ec2_sg" {
  name        = "epicbook-ec2-sg"
  description = "Allow SSH and HTTP"
  vpc_id      = aws_vpc.epicbook_vpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "epicbook-ec2-sg", Project = "EpicBook" }
}

resource "aws_security_group" "rds_sg" {
  name        = "epicbook-rds-sg"
  description = "MySQL from EC2 only"
  vpc_id      = aws_vpc.epicbook_vpc.id

  ingress {
    description     = "MySQL from EC2"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "epicbook-rds-sg", Project = "EpicBook" }
}

resource "tls_private_key" "epicbook_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "epicbook_key" {
  key_name   = "epicbook-key"
  public_key = tls_private_key.epicbook_key.public_key_openssh
}

resource "local_file" "epicbook_pem" {
  content         = tls_private_key.epicbook_key.private_key_pem
  filename        = "${path.module}/epicbook-key.pem"
  file_permission = "0400"
}

data "aws_ami" "ubuntu_22" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "epicbook_ec2" {
  ami                         = data.aws_ami.ubuntu_22.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_subnet.id
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  key_name                    = aws_key_pair.epicbook_key.key_name
  associate_public_ip_address = true
  tags = { Name = "epicbook-ec2", Project = "EpicBook" }
}

resource "aws_eip" "epicbook_eip" {
  instance = aws_instance.epicbook_ec2.id
  domain   = "vpc"
  tags     = { Name = "epicbook-eip", Project = "EpicBook" }
}

resource "aws_db_subnet_group" "epicbook_db_subnet_group" {
  name       = "epicbook-db-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
  tags       = { Name = "epicbook-db-subnet-group", Project = "EpicBook" }
}

resource "aws_db_instance" "epicbook_rds" {
  identifier             = "epicbook-rds"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  storage_type           = "gp2"
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.epicbook_db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
  multi_az               = false
  tags                   = { Name = "epicbook-rds", Project = "EpicBook" }
}