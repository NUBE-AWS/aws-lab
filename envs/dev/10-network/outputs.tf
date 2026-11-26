# 20-cluster · 30-data 가 terraform_remote_state 로 읽는 값

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "VPC CIDR"
  value       = module.vpc.vpc_cidr_block
}

output "azs" {
  description = "가용 영역(서브넷 순서와 같음)"
  value       = module.vpc.azs
}

output "public_subnet_ids" {
  description = "공개 서브넷(ALB, NAT)"
  value       = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "사설 서브넷(노드, 파드)"
  value       = module.vpc.private_subnets
}

output "database_subnet_ids" {
  description = "DB 서브넷(인터넷 경로 없음)"
  value       = module.vpc.database_subnets
}

output "database_subnet_group_name" {
  description = "RDS 서브넷 그룹 이름"
  value       = module.vpc.database_subnet_group_name
}

output "nat_gateway_ids" {
  description = "NAT 게이트웨이(enable_nat_gateway = false 면 빈 목록)"
  value       = module.vpc.natgw_ids
}
