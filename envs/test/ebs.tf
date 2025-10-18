data "aws_instance" "web" { instance_id = module.web.instance_id }

module "web_data_disk" {
  source            = "../../modules/storage/ebs-volume"
  name              = "web-data-${var.env}"
  availability_zone = data.aws_instance.web.availability_zone
  size_gb           = 10
  instance_id       = module.web.instance_id
  device_name       = "/dev/xvdf"
  tags              = local.common_tags
}