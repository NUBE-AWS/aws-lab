# EBS CSI 드라이버의 Pod Identity 역할(#50, 설계 4.2 · 가이드 10장 4단계)
#
# - 권한은 노드 역할이 아니라 컨트롤러 파드(kube-system/ebs-csi-controller-sa)에만 준다.
# - 애드온 자체와 연결(pod_identity_association)은 main.tf 의 addons 에 있다.
# - 신뢰 정책은 karpenter.tf 와 같은 방식: 이 클러스터 · 네임스페이스 · ServiceAccount 만 역할을 맡는다.
# - 테인트: 컨트롤러 기본 tolerations 에 CriticalAddonsOnly 가 있고 노드 DaemonSet 은 tolerateAllTaints 기본 true
#   (v1.68.1-eksbuild.1 설정 스키마, 2026-11-27 조회). tolerations 를 직접 적으면 기본값을 덮어쓰므로 적지 않는다.
# - ⚠️ 이 드라이버가 PVC 로 만드는 EBS 볼륨은 Terraform 상태 밖이다. 클러스터를 지우기 전에 PVC 를 지운다(README).

locals {
  ebs_csi_namespace       = "kube-system"
  ebs_csi_service_account = "ebs-csi-controller-sa"
}

data "aws_iam_policy_document" "ebs_csi_trust" {
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
      values   = [local.ebs_csi_namespace]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes-service-account"
      values   = [local.ebs_csi_service_account]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.cluster_name}-ebs-csi"
  description        = "EBS CSI controller (Pod Identity, kube-system/ebs-csi-controller-sa only)"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_trust.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
