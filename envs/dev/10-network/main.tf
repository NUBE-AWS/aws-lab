# 10-network — 작업 뒤 삭제: VPC · 서브넷 · NAT · 엔드포인트 (설계 3.1)
# 공식 커뮤니티 모듈 terraform-aws-modules/vpc 를 쓴다(#10).

locals {
  name = "aws-lab-dev"
  azs  = ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c"]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.9"

  name = local.name
  cidr = "10.40.0.0/16"
  azs  = local.azs

  # 서브넷 순서는 azs 순서(2a · 2b · 2c)와 같다.
  public_subnets   = ["10.40.0.0/24", "10.40.1.0/24", "10.40.2.0/24"]       # ALB, NAT
  private_subnets  = ["10.40.16.0/20", "10.40.32.0/20", "10.40.48.0/20"]    # 노드, 파드(VPC CNI)
  database_subnets = ["10.40.100.0/24", "10.40.101.0/24", "10.40.102.0/24"] # RDS

  # DB 서브넷은 전용 라우팅 테이블을 쓰고, 인터넷 · NAT 경로를 두지 않는다.
  # (끄면 DB 서브넷이 사설 라우팅 테이블을 함께 써서 NAT 경로가 생긴다)
  create_database_subnet_route_table     = true
  create_database_internet_gateway_route = false
  create_database_nat_gateway_route      = false

  # NAT 는 1개(첫 공개 서브넷 = 2a). 켜면 시간당 약 0.064달러(NAT 0.059 + 공인 IPv4 0.005)와 GB당 0.059.
  # var.enable_nat_gateway 로 켜고 끈다. 사설 라우팅 테이블 수는 NAT를 켜고 꺼도 1개로 같아 교체가 생기지 않는다.
  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = true

  # AWS Load Balancer Controller 와 Karpenter 가 서브넷을 찾는 태그
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery"          = var.cluster_name
  }
}

# S3 게이트웨이 엔드포인트(무료). ECR 이미지 계층 등 S3 트래픽이 NAT 를 거치지 않는다.
# 인터페이스 엔드포인트는 시간당 과금이라 두지 않는다(설계 3.1).
module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 6.9"

  vpc_id = module.vpc.vpc_id

  endpoints = {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = concat(module.vpc.private_route_table_ids, module.vpc.database_route_table_ids)
      tags            = { Name = "${local.name}-s3" }
    }
  }
}
