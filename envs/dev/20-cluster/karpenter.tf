# Karpenter 의 AWS 쪽 자원 (설계 3.3, 가이드 11장 4~6단계, #35)
# - 컨트롤러 역할 + Pod Identity 연결(kube-system/karpenter)
# - 노드 역할 + 액세스 항목(EC2_LINUX). 인스턴스 프로파일은 만들지 않는다 — Karpenter 가 노드 역할로 만들고 지운다.
# - 스팟 중단 알림 대기열(SQS) + EventBridge 규칙 5개
# Karpenter 자체(Helm 차트 · NodePool · EC2NodeClass)는 gitops 단계(가이드 16장).

# 컨트롤러 역할의 신뢰 정책 — 모듈 기본 문장(sid PodIdentity)을 같은 sid 로 덮어써서
# 이 클러스터의 kube-system/karpenter 만 역할을 맡게 한다(설계 4.2).
data "aws_iam_policy_document" "karpenter_controller_trust" {
  statement {
    sid     = "PodIdentity"
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks-cluster-name"
      values   = [var.cluster_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes-namespace"
      values   = [local.karpenter_namespace]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes-service-account"
      values   = [local.karpenter_service_account]
    }
  }
}

locals {
  # Helm 차트의 serviceAccount.name · 설치 네임스페이스와 같아야 한다(가이드 16장).
  karpenter_namespace       = "kube-system"
  karpenter_service_account = "karpenter"
}

# Trivy 예외(오탐): AWS-0342 iam:PassRole — 모듈 정책 AllowPassingInstanceRole 은 대상이 노드 역할 하나이고
# iam:PassedToService = ec2.amazonaws.com 조건이 있다. 정적 검사가 대상 ARN 을 풀지 못해 경고한다.
#trivy:ignore:AWS-0342
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.30.2"

  cluster_name = module.eks.cluster_name

  # 컨트롤러 역할 — 이름을 고정해 찾기 쉽게 한다(모듈 기본값은 무작위 접미사).
  iam_role_name                             = "${var.cluster_name}-karpenter"
  iam_role_use_name_prefix                  = false
  iam_role_override_assume_policy_documents = [data.aws_iam_policy_document.karpenter_controller_trust.json]

  # 컨트롤러 정책이 관리형 정책 한도(6,144자)를 넘어 CreatePolicy 가 LimitExceeded 로 실패한다(#59).
  # 역할의 인라인 정책(한도 10,240자)으로 만든다 — 모듈 변수 설명이 이 오류에 권하는 방법.
  enable_inline_policy = true

  namespace       = local.karpenter_namespace
  service_account = local.karpenter_service_account

  # 노드 역할 — EC2NodeClass 의 spec.role 에 이 이름을 적는다.
  node_iam_role_name            = "KarpenterNodeRole-${var.cluster_name}"
  node_iam_role_use_name_prefix = false
  node_iam_role_additional_policies = {
    ecr_pull_through_first_pull = aws_iam_policy.ecr_pull_through_first_pull.arn
  }

  # 스팟을 쓰므로 중단 알림 대기열은 반드시 둔다(회수 2분 전에 파드를 옮기는 수단, 설계 3.3).
  enable_spot_termination   = true
  queue_name                = "${var.cluster_name}-karpenter"
  queue_managed_sse_enabled = true
  rule_name_prefix          = "${var.cluster_name}-"
}