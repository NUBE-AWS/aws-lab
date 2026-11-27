# 야간 점검 역할(#28) — 매일 23시(KST) 예약 워크플로가 과금 자원이 남았는지 조회만 한다(설계 7.4 · 8.3).
#
# 누가 받을 수 있나: 이 저장소의 main 브랜치에서 도는 실행(예약 실행의 sub 는 ref:refs/heads/main).
# - 적용 역할(GitHubActionsApply)과 신뢰 조건이 같다. 신뢰 조건은 워크플로 파일을 구분하지 못하므로
#   main 에서 도는 워크플로는 두 역할을 모두 받을 수 있다. main 은 승인된 PR 만 들어가 당장 위험은 작다.
#   관리자 역할을 GitHub Environment 에 묶는 보완은 #28 밖(문진중 의견).
# - 그래도 역할을 따로 두는 이유: 점검은 조회만 하면 되므로 관리자 권한으로 돌 이유가 없다(최소 권한).

data "aws_iam_policy_document" "github_nightly_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${var.github_sub_prefix}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_nightly" {
  name = "GitHubActionsNightlyCheck"
  # IAM description 은 한글을 받지 않는다(#18).
  description          = "GitHub Actions nightly cost check: list billable resources only (read)."
  assume_role_policy   = data.aws_iam_policy_document.github_nightly_trust.json
  max_session_duration = 3600
}

# 조회 액션 일곱 개만. 이 List · Describe 액션들은 리소스 단위 제한을 받지 않아 Resource 는 "*" 다.
# 점검 대상: EKS · NAT · 실행 중 EC2 · 연결 안 된 EBS · 탄력적 IP · ALB · RDS(#28 결정 2).
data "aws_iam_policy_document" "github_nightly" {
  statement {
    sid = "ListBillableResources"
    actions = [
      "eks:ListClusters",
      "ec2:DescribeNatGateways",
      "ec2:DescribeInstances",
      "ec2:DescribeVolumes",
      "ec2:DescribeAddresses",
      "elasticloadbalancing:DescribeLoadBalancers",
      "rds:DescribeDBInstances",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_nightly" {
  name   = "list-billable-resources"
  role   = aws_iam_role.github_nightly.id
  policy = data.aws_iam_policy_document.github_nightly.json
}
