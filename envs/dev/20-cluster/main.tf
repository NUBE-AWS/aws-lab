# 20-cluster — 작업 뒤 삭제: EKS · 시스템 노드 그룹 · 애드온 (설계 3.2 · 3.3, #35)
# Karpenter(AWS 쪽)는 다음 PR, 사람의 액세스 항목 · Pod Identity(EBS CSI 역할 등)는 손두영 님(설계 7.5).

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  # bootstrap 이 정한 상태 버킷 이름(aws-lab-tfstate-<계정 ID>). 계정 ID 를 코드에 적지 않으려고 조회해서 만든다.
  state_bucket = "aws-lab-tfstate-${data.aws_caller_identity.current.account_id}"

  network    = data.terraform_remote_state.network.outputs
  foundation = data.terraform_remote_state.foundation.outputs
}

# 다른 스택의 출력 읽기 — 출력 이름이 스택 사이의 계약이다.
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = local.state_bucket
    key    = "dev/network/terraform.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "foundation" {
  backend = "s3"
  config = {
    bucket = local.state_bucket
    key    = "dev/foundation/terraform.tfstate"
    region = var.region
  }
}

# NAT 가 없으면 사설 서브넷의 노드가 EKS · ECR API 에 닿지 못한다 — plan 단계에서 멈춘다(설계 7.1).
resource "terraform_data" "nat_precondition" {
  lifecycle {
    precondition {
      condition     = length(local.network.nat_gateway_ids) > 0
      error_message = "NAT 게이트웨이가 꺼져 있습니다. 10-network 의 enable_nat_gateway 를 true 로 apply 한 뒤 다시 실행합니다."
    }
  }
}

# 노드(시스템 · Karpenter)가 pull-through cache 에서 처음 이미지를 받을 때 캐시 저장소를 만드는 권한(설계 6.4, #27).
# 접두어는 00-foundation 출력 cache_prefixes 를 그대로 쓴다 — 캐시 규칙을 더하면 이 권한도 함께 따라온다.
data "aws_iam_policy_document" "ecr_pull_through_first_pull" {
  statement {
    sid    = "CreateCacheRepositoryOnFirstPull"
    effect = "Allow"
    actions = [
      "ecr:CreateRepository",
      "ecr:BatchImportUpstreamImage",
    ]
    resources = [
      for p in local.foundation.cache_prefixes :
      "arn:${data.aws_partition.current.partition}:ecr:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:repository/${p}/*"
    ]
  }
}

resource "aws_iam_policy" "ecr_pull_through_first_pull" {
  name        = "${var.cluster_name}-ecr-pull-through-first-pull"
  description = "Node role: create ECR pull-through cache repositories on first pull, cache prefixes only (design 6.4, #35)"
  policy      = data.aws_iam_policy_document.ecr_pull_through_first_pull.json
}

# Trivy 예외(설계상 의도):
# - AWS-0040 공개 엔드포인트: 설계 3.2 — VPN 없이 접속하되 공개 쪽은 두 사람의 /32 만 허용(0.0.0.0/0 은 변수 검증이 거부)
# - AWS-0104 노드 보안 그룹 전체 egress: 노드가 NAT 로 EKS · ECR · STS 와 pull-through 원본에 나가야 한다. 파드 단위 제한은 네트워크 정책(설계 5.1)
#trivy:ignore:AWS-0040
#trivy:ignore:AWS-0104
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.30.2"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  # 사람 · 노드의 권한은 액세스 항목으로만 준다(aws-auth ConfigMap 안 씀, 되돌릴 수 없음).
  authentication_mode = "API"

  # 공개 + 사설. 공개는 두 사람의 주소만 — 모듈 기본값이 0.0.0.0/0 이라 반드시 넘긴다.
  endpoint_public_access       = true
  endpoint_private_access      = true
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # 이 스택은 CI 적용 역할이 만든다. 생성자를 클러스터 관리자로 두지 않는다(모듈 기본값도 false, 의도를 적음).
  enable_cluster_creator_admin_permissions = false

  # 워크로드 권한은 Pod Identity 로 준다(설계 4.2). IRSA 용 OIDC 공급자는 만들지 않는다(모듈 기본값 true).
  enable_irsa = false

  # Secret 봉투 암호화 — 00-foundation 의 키(매일 지우지 않음)를 쓴다.
  create_kms_key = false
  encryption_config = {
    provider_key_arn = local.foundation.eks_kms_key_arn
    resources        = ["secrets"]
  }

  # 감사에 필요한 두 종류만 7일(설계 3.2). 로그 그룹은 Terraform 이 만들고 지운다.
  enabled_log_types                      = ["audit", "authenticator"]
  cloudwatch_log_group_retention_in_days = 7

  vpc_id     = local.network.vpc_id
  subnet_ids = local.network.private_subnet_ids

  # Karpenter 의 EC2NodeClass 가 앱 노드에 붙일 보안 그룹을 이 태그로 찾는다(서브넷 태그는 10-network).
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }

  addons = {
    vpc-cni = {
      addon_version  = var.addon_versions["vpc-cni"]
      before_compute = true # 노드보다 먼저 — 노드가 처음부터 네트워크 정책 설정으로 뜬다
      configuration_values = jsonencode({
        enableNetworkPolicy = "true" # 없으면 NetworkPolicy 가 아무것도 막지 않는다(설계 5.1)
      })
    }
    eks-pod-identity-agent = {
      addon_version  = var.addon_versions["eks-pod-identity-agent"]
      before_compute = true
    }
    kube-proxy = {
      addon_version = var.addon_versions["kube-proxy"]
    }
    coredns = {
      addon_version = var.addon_versions["coredns"]
      # 시스템 노드의 테인트를 견디게 한다(설정 스키마에 tolerations 키 있음, 2026-11-27 조회).
      configuration_values = jsonencode({
        tolerations = [{ key = "CriticalAddonsOnly", operator = "Exists" }]
      })
    }
  }

  eks_managed_node_groups = {
    system = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.large"]

      min_size     = 2
      max_size     = 2
      desired_size = 2

      labels = {
        "node-role" = "system"
      }

      # 업무 앱이 올라오지 않게 한다. 이 노드에 둘 컨트롤러에만 toleration 을 준다(설계 3.3).
      taints = {
        critical_addons_only = {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }

      # IMDSv2 만, 홉 한도 1 — 파드가 노드 역할 자격 증명을 가져가지 못하게(하위 모듈 기본값과 같음, 의도를 적음).
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
      }

      iam_role_additional_policies = {
        ecr_pull_through_first_pull = aws_iam_policy.ecr_pull_through_first_pull.arn
      }
    }
  }
}
