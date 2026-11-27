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
  description = "NAT 게이트웨이를 켤지. 스택을 매일 만들고 지우므로 기본으로 켠다(끄는 것은 emergency-down 이 10-network 를 지울 때, #54). 클러스터 없이 네트워크만 오래 둘 때만 false"
  type        = bool
  default     = true
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
