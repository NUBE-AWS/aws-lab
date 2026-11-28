# CI 역할의 명시적 거부(설계 7.4 · 가이드 6.7, #40). 명시적 거부는 같은 역할의 관리형 정책 허용보다 우선한다.
#
# 이 파일이 들어간 뒤 CI(apply 역할)로는 적용되지 않아 「사람이 로컬에서 apply」해야 하는 변경(README):
# - github-oidc.tf 의 plan · apply 역할(신뢰 정책 · 인라인 정책 · 정책 연결 · 삭제), OIDC 공급자
# - 이 파일 자체
# - CloudTrail 추적의 중지 · 삭제 · 설정 변경(cloudtrail.tf), GuardDuty 탐지기 · 기능 변경(guardduty.tf)
# - aws-lab-admins 그룹에 사용자 추가(원래 사람이 콘솔에서 한다, #50)
# 처음 넣는 적용은 아직 거부가 없으므로 CI 에서도 성공한다.
#
# 닫지 못하는 것: 거부 목록 밖의 호출은 apply 역할(AdministratorAccess)에 그대로 열려 있다. 완화일 뿐 사라지지 않는다.

# ── plan 역할: 비밀 값 읽기 거부 ─────────────────────────────────
# PR 에서 도는 역할이다. ReadOnlyAccess 에 SSM 파라미터 값 · Secrets Manager 값 읽기가 들어 있어 막는다.
# - SSM: 값을 돌려주는 호출 네 가지를 모두 거부한다(하나라도 빠지면 그 호출로 읽힌다).
#   대상은 이 계정의 파라미터만. AWS 공개 파라미터(EKS AMI 등)는 ARN 의 계정 칸이 비어(…::parameter/aws/service/…)
#   이 패턴에 걸리지 않는다 — 20-cluster plan 에서 확인(#40).
# - Secrets Manager: ecr-pullthroughcache/ghcr(#27) 같은 비밀 값을 PR plan 이 읽지 못하게 한다.
#   Terraform plan 은 비밀의 메타데이터(DescribeSecret)만 읽으므로 이 거부로 실패하지 않는다(비밀 값 자원을 두지 않음).
data "aws_iam_policy_document" "plan_deny" {
  statement {
    sid    = "DenySsmParameterValueRead"
    effect = "Deny"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
      "ssm:GetParameterHistory",
    ]
    resources = ["arn:aws:ssm:${var.region}:${local.account_id}:parameter/*"]
  }

  statement {
    sid       = "DenySecretValueRead"
    effect    = "Deny"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:BatchGetSecretValue"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "plan_deny" {
  name   = "ci-secret-read-deny"
  role   = aws_iam_role.github_plan.name
  policy = data.aws_iam_policy_document.plan_deny.json
}

# ── apply 역할: 통제 장치를 끄거나 우회하는 호출 거부 ────────────────
data "aws_iam_policy_document" "apply_deny" {
  # 사람 주체(사용자 · 장기 키 · 콘솔 비밀번호)를 CI 가 만들지 못하게 한다.
  statement {
    sid       = "DenyPrincipalCreation"
    effect    = "Deny"
    actions   = ["iam:CreateUser", "iam:CreateAccessKey", "iam:CreateLoginProfile"]
    resources = ["*"]
  }

  # CI 역할 세 개만. apply 역할이 자기 거부 문장을 지우거나, PR 에서 도는 plan 역할 · 조회 전용 야간 점검 역할의
  # 신뢰 조건 · 권한을 넓히지 못하게 한다(야간 점검 역할을 PR 실행까지 열고 관리자 정책을 붙이는 경로를 막음).
  # "*" 로 두면 20-cluster 의 노드 · Pod Identity 역할 정책 연결까지 거부되어 적용이 실패한다.
  statement {
    sid    = "DenyCiRoleChange"
    effect = "Deny"
    actions = [
      "iam:UpdateAssumeRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePermissionsBoundary",
      "iam:DeleteRole",
    ]
    resources = [aws_iam_role.github_plan.arn, aws_iam_role.github_apply.arn, aws_iam_role.github_nightly.arn]
  }

  statement {
    sid    = "DenyOidcProviderChange"
    effect = "Deny"
    actions = [
      "iam:DeleteOpenIDConnectProvider",
      "iam:AddClientIDToOpenIDConnectProvider",
      "iam:RemoveClientIDFromOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
    ]
    resources = [aws_iam_openid_connect_provider.github.arn]
  }

  # 중지 · 삭제만 막으면 기록 대상에서 관리 이벤트를 빼거나(PutEventSelectors) 버킷 · 검증 설정을 바꿔(UpdateTrail)
  # 같은 결과를 낼 수 있어 둘 다 거부한다.
  statement {
    sid       = "DenyCloudTrailStopOrDelete"
    effect    = "Deny"
    actions   = ["cloudtrail:StopLogging", "cloudtrail:DeleteTrail", "cloudtrail:UpdateTrail", "cloudtrail:PutEventSelectors"]
    resources = ["*"]
  }

  # 기능 켜고 끄기(aws_guardduty_detector_feature)도 UpdateDetector 를 부른다 → 기능 변경은 사람이 적용.
  statement {
    sid       = "DenyGuardDutyDisable"
    effect    = "Deny"
    actions   = ["guardduty:DeleteDetector", "guardduty:UpdateDetector"]
    resources = ["*"]
  }

  # 그룹 멤버 = EKS 클러스터 관리자(20-cluster 가 멤버로 액세스 항목을 만든다, #50).
  # CI 가 그룹에 사용자를 넣으면 PR 하나로 클러스터 관리자를 만들 수 있게 되므로 막는다.
  statement {
    sid       = "DenyClusterAdminsGroupMembership"
    effect    = "Deny"
    actions   = ["iam:AddUserToGroup"]
    resources = [aws_iam_group.cluster_admins.arn]
  }
}

resource "aws_iam_role_policy" "apply_deny" {
  name   = "ci-control-deny"
  role   = aws_iam_role.github_apply.name
  policy = data.aws_iam_policy_document.apply_deny.json
}
