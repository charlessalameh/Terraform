output "vpc_id" {
  value       = aws_vpc.this.id
  description = "ID of the created VPC."
}

output "public_subnet_ids" {
  value       = [for s in aws_subnet.public : s.id]
  description = "IDs of the public subnets."
}