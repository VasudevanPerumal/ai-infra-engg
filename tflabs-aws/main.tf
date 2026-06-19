terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

locals {
  name_prefix = "ailab-${var.participant_name}"

  common_tags = {
    owner       = var.participant_name
    environment = "lab"
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_ami" "windows" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_vpc" "lab" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "vpc-${local.name_prefix}"
  })
}

resource "aws_subnet" "app" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "snet-app-${local.name_prefix}"
  })
}

resource "aws_subnet" "db" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "snet-db-${local.name_prefix}"
  })
}

resource "aws_subnet" "access" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = "10.0.3.0/27"
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "snet-access-${local.name_prefix}"
  })
}

resource "aws_security_group" "app" {
  name        = "sg-app-${var.participant_name}"
  description = "Allow SSH and RDP from the EC2 Instance Connect Endpoint subnet"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description = "SSH from access subnet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.access.cidr_block]
  }

  ingress {
    description = "RDP from access subnet"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.access.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "sg-app-${local.name_prefix}"
  })
}

resource "aws_security_group" "db" {
  name        = "sg-db-${var.participant_name}"
  description = "Allow PostgreSQL from the app subnet"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description = "PostgreSQL from app subnet"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.app.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "sg-db-${local.name_prefix}"
  })
}

resource "aws_security_group" "access" {
  name        = "sg-access-${var.participant_name}"
  description = "Outbound access from the EC2 Instance Connect Endpoint to managed instances"
  vpc_id      = aws_vpc.lab.id

  egress {
    description = "SSH to app subnet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.app.cidr_block]
  }

  egress {
    description = "RDP to app subnet"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.app.cidr_block]
  }

  tags = merge(local.common_tags, {
    Name = "sg-access-${local.name_prefix}"
  })
}

resource "aws_ec2_instance_connect_endpoint" "lab" {
  subnet_id          = aws_subnet.access.id
  security_group_ids = [aws_security_group.access.id]
  preserve_client_ip = false

  tags = merge(local.common_tags, {
    Name = "eice-${local.name_prefix}"
  })
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.app_instance_type
  subnet_id              = aws_subnet.app.id
  vpc_security_group_ids = [aws_security_group.app.id]
  private_ip             = "10.0.1.10"
  user_data              = templatefile("${path.module}/cloud-init-app.yaml", { admin_password = var.admin_password })

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(local.common_tags, {
    Name = "vm-app-${local.name_prefix}"
  })
}

resource "aws_instance" "db" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.db_instance_type
  subnet_id              = aws_subnet.db.id
  vpc_security_group_ids = [aws_security_group.db.id]
  private_ip             = "10.0.2.10"
  user_data = templatefile("${path.module}/cloud-init-db.yaml", {
    admin_password = var.admin_password
  })

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(local.common_tags, {
    Name = "vm-db-${local.name_prefix}"
  })
}

resource "aws_instance" "win" {
  ami                    = data.aws_ami.windows.id
  instance_type          = var.win_instance_type
  subnet_id              = aws_subnet.app.id
  vpc_security_group_ids = [aws_security_group.app.id]
  private_ip             = "10.0.1.20"
  user_data              = templatefile("${path.module}/windows-user-data.ps1", { admin_password = var.admin_password })

  root_block_device {
    volume_size = 128
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(local.common_tags, {
    Name = "vm-win-${local.name_prefix}"
  })
}