# GitHub Actions → AWS 인증(OIDC). 저장소에 접근 키를 두지 않는다(설계 7.4, #13).
# CI 역할은 plan 전용이다 — apply 는 사람이 병합 뒤 main 에서 한다.

data "aws_caller_identity" "current" {}

locals {
  # bootstrap 이 만든 상태 버킷(이름 규칙이 같다). 계정 ID 를 코드에 적지 않으려고 조회로 만든다.
  state_bucket = "aws-lab-tfstate-${data.aws_caller_identity.current.account_id}"
}

# GitHub 의 OIDC 토큰을 믿는 제공자. 계정에 하나만 둘 수 있다.
# thumbprint 는 적지 않는다 — AWS 가 GitHub 의 인증서를 자체 신뢰 저장소로 검증한다.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

# 누가 이 역할을 받을 수 있나: 이 저장소의 pull_request 실행만.
# - sub 가 <sub 접두어>:pull_request 일 때만 허용한다(접두어 형식은 variables.tf 참고). 다른 저장소, 브랜치 push,
#   workflow_dispatch 로는 받을 수 없다.
# - 포크에서 온 PR 은 GitHub 가 id-token 을 주지 않으므로 이 역할에 닿지 못한다.
data "aws_iam_policy_document" "github_plan_trust" {
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
      values   = ["${var.github_sub_prefix}:pull_request"]
    }
  }
}

resource "aws_iam_role" "github_plan" {
  name = "GitHubActionsPlan"
  # GitHub Actions PR plan 전용(읽기 + 상태 잠금 파일). apply 권한 없음.
  # IAM description 은 한글을 받지 않는다(허용 문자: 탭 · 줄바꿈 · ASCII · U+00A1~U+00FF, #18).
  description          = "GitHub Actions PR plan only (read-only + state lock file). No apply permission."
  assume_role_policy   = data.aws_iam_policy_document.github_plan_trust.json
  max_session_duration = 3600
}

# 읽기 — plan 이 자원의 현재 모습을 조회하고 상태 파일을 읽는 데 쓴다.
resource "aws_iam_role_policy_attachment" "github_plan_readonly" {
  role       = aws_iam_role.github_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# 쓰기는 상태 잠금 파일만 — use_lockfile 은 plan 때도 <key>.tflock 을 만들고 지운다.
# 상태 파일(.tfstate) 자체에는 쓰지 못한다.
data "aws_iam_policy_document" "github_plan_state_lock" {
  statement {
    sid       = "StateLockFileOnly"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${local.state_bucket}/*.tflock"]
  }
}

resource "aws_iam_role_policy" "github_plan_state_lock" {
  name   = "state-lock-file"
  role   = aws_iam_role.github_plan.id
  policy = data.aws_iam_policy_document.github_plan_state_lock.json
}
