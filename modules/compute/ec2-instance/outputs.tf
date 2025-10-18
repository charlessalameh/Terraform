output "instance_id" { value = aws_instance.this.id }
output "public_ip"   { value = aws_instance.this.public_ip }
output "ami_id"      { value = data.aws_ami.al2023.id }