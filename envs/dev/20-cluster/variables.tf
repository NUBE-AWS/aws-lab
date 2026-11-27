variable "region" {
  description = "자원을 만들 리전"
  type        = string
  default     = "ap-northeast-2"
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

variable "cluster_name" {
  description = "EKS 클러스터 이름. 10-network 의 cluster_name(서브넷 karpenter.sh/discovery 태그 값)과 같아야 한다"
  type        = string
  default     = "aws-lab-dev"
}

variable "kubernetes_version" {
  description = "EKS 판(설계 3.2). 표준 지원이 끝나기 전에 올린다"
  type        = string
  default     = "1.37"
}

# 기본값 없음 — 빠뜨리면 plan 이 멈춘다. 로컬은 Git 제외 *.auto.tfvars, CI 는 Secret(#36).
variable "cluster_endpoint_public_access_cidrs" {
  description = "EKS 공개 엔드포인트에 접속을 허용할 주소(두 사람의 /32)"
  type        = list(string)

  validation {
    condition     = length(var.cluster_endpoint_public_access_cidrs) > 0 && !contains(var.cluster_endpoint_public_access_cidrs, "0.0.0.0/0")
    error_message = "공개 엔드포인트 허용 주소에 0.0.0.0/0 을 넣지 않습니다. 두 사람의 주소(/32)만 적습니다."
  }
}

variable "addon_versions" {
  description = "관리형 애드온 판(설계 3.2: 판은 코드에 고정). 2026-11-27 서울 리전 EKS 1.37 기본 판"
  type        = map(string)
  default = {
    vpc-cni                = "v1.22.4-eksbuild.14"
    coredns                = "v1.14.7-eksbuild.35"
    kube-proxy             = "v1.37.0-eksbuild.39"
    eks-pod-identity-agent = "v1.4.1-eksbuild.3"
  }
}
