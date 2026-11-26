# GitHub Actions → AWS 인증(OIDC). 저장소에 접근 키를 두지 않는다(설계 7.4, #13).
# 역할 둘: PR 의 plan 전용(GitHubActionsPlan) · main 병합 뒤 apply · 비상 끄기용(GitHubActionsApply, #16).

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

# ── apply 역할(#16) ─────────────────────────────────────────────
# 누가 받을 수 있나: 이 저장소의 main 브랜치에서 도는 실행만(push 뒤 자동 apply · 비상 끄기 버튼).
# - sub 가 <sub 접두어>:ref:refs/heads/main 일 때만 허용한다. PR 실행 · 다른 브랜치는 받을 수 없다.
# - main 은 룰셋으로 보호된다(PR 필수 · 다른 사람 승인). 그래서 「main 에 들어온 코드 = 두 사람이 본 코드」다.
# 이 역할은 CI 가 스스로 만들 수 없으므로 처음 한 번은 사람이 로컬에서 apply 한다.
data "aws_iam_policy_document" "github_apply_trust" {
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

resource "aws_iam_role" "github_apply" {
  name = "GitHubActionsApply"
  # IAM description 은 한글을 받지 않는다(#18).
  description          = "GitHub Actions apply/destroy from main branch only (00-30 stacks)."
  assume_role_policy   = data.aws_iam_policy_document.github_apply_trust.json
  max_session_duration = 7200 # 10 → 20 → 30 전체 생성 · 삭제(EKS · RDS)를 덮는다. 워크플로 job 제한(100분)보다 길게
}

# 권한은 AdministratorAccess — 스택들이 VPC · EKS · IAM 역할 · RDS 를 만들고 지운다.
# 범위를 좁히는 대신 「누가 이 역할을 받나」(위 신뢰 정책 + main 보호)로 막는다.
resource "aws_iam_role_policy_attachment" "github_apply_admin" {
  role       = aws_iam_role.github_apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
