variable "region" {
  description = "자원을 만들 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "cluster_name" {
  description = "EKS 클러스터 이름. 사설 서브넷의 karpenter.sh/discovery 태그 값이며, 20-cluster 와 같아야 한다"
  type        = string
  default     = "aws-lab-dev"
}

variable "enable_nat_gateway" {
  description = "NAT 게이트웨이를 켤지. 켜 두면 시간당 요금이 나가므로 클러스터 작업할 때만 true 로 apply 하고, 끝나면 false 로 되돌린다"
  type        = bool
  default     = false
}

variable "tags" {
  description = "모든 자원에 붙일 공통 태그(비용을 프로젝트·스택별로 보기 위함)"
  type        = map(string)
  default = {
    Project     = "aws-lab"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
