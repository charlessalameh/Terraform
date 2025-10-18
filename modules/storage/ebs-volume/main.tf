resource "aws_ebs_volume" "this" {
  availability_zone = var.availability_zone
  size              = var.size_gb
  type              = var.type
  iops              = var.type == "gp3" ? var.iops : null
  throughput        = var.type == "gp3" ? var.throughput : null
  encrypted         = var.encrypted
  kms_key_id        = var.kms_key_id
  tags              = merge(var.tags, { Name = var.name })
}

resource "aws_volume_attachment" "att" {
  device_name = var.device_name
  volume_id   = aws_ebs_volume.this.id
  instance_id = var.instance_id
}