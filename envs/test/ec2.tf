############################################
# EC2 instance (Amazon Linux 2023 + nginx)
############################################

module "web" {
  source         = "../../modules/compute/ec2-instance"
  name           = "web-${var.env}"
  vpc_id         = module.vpc.vpc_id
  subnet_id      = module.vpc.public_subnet_ids[0]
  instance_type  = "t3.micro"
  allow_ssh_cidr = "0.0.0.0/0" # tighten to your IP/32 later

  user_data = <<-EOF
              #!/bin/bash
              yum install -y nginx
              systemctl enable nginx
              echo "<h1>Hello from ${var.env}!</h1>" > /usr/share/nginx/html/index.html
              systemctl start nginx
              EOF

  tags = {
    Project     = var.project
    Environment = var.env
    Owner       = var.owner
  }
}