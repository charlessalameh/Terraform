module "web" {
  source         = "../../modules/compute/ec2-instance"
  name           = "web-${var.env}"
  vpc_id         = module.vpc.vpc_id
  subnet_id      = module.vpc.public_subnet_ids[0]
  instance_type  = "t3.micro"
  arch           = "x86_64"
  allow_ssh_cidr = "0.0.0.0/0" # tighten to YOUR_IP/32 later
  user_data      = <<-EOT
                      #!/bin/bash
                      dnf -y update
                      dnf -y install nginx
                      systemctl enable --now nginx
                      echo "Hello from ${var.env}" > /usr/share/nginx/html/index.html
                      EOT
  tags           = local.common_tags
}

output "test_instance_ip" { value = module.web.public_ip }