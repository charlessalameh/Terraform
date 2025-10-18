############################################
# EC2 module: instance + optional SG
############################################

# Latest Amazon Linux 2023 AMI
data "aws_ami" "al2023" {
  owners      = ["137112412989"] # Amazon
  most_recent = true

  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-6.1*"]
  }

  filter {
    name   = "architecture"
    values = [var.arch]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Auto-create a minimal SG (SSH) if caller didn't pass any SG IDs
resource "aws_security_group" "auto" {
  count  = length(var.security_group_ids) == 0 ? 1 : 0
  name   = "${var.name}-sg"
  vpc_id = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allow_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-sg" })
}

locals {
  sg_ids = length(var.security_group_ids) > 0 ? var.security_group_ids : [aws_security_group.auto[0].id]
}

resource "aws_instance" "this" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = local.sg_ids
  key_name                    = var.key_name
  user_data                   = var.user_data
  iam_instance_profile        = var.iam_instance_profile
  associate_public_ip_address = true

  root_block_device {
    volume_type           = var.root_volume_type
    volume_size           = var.root_volume_size
    delete_on_termination = true
  }

  tags = merge(var.tags, { Name = var.name })
}