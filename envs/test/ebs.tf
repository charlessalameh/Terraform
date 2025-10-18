############################################
# Extra EBS volume attached to the EC2
############################################

module "web_data_disk" {
  source            = "../../modules/storage/ebs-volume"
  name              = "web-data-${var.env}"
  availability_zone = "us-east-1a" # keep simple; can derive from subnet later
  size_gb           = 10
  type              = "gp3"

  # IMPORTANT: use the output name from the EC2 module (no "this_" prefix)
  instance_id = module.web.instance_id
  device_name = "/dev/xvdf"

  tags = {
    Project     = var.project
    Environment = var.env
    Owner       = var.owner
  }
}