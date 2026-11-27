# EKS 클러스터 관리자 그룹(#50, 설계 4.1) — 20-cluster 가 이 그룹의 멤버를 조회해 사람의 액세스 항목을 만든다.
#
# - IAM 「사용자 그룹」이다. IAM Identity Center · Organizations 와 무관하고 요금 · 계정 상태 변화가 없다.
# - 허용 정책은 붙이지 않는다. 그룹에 든다고 AWS 권한이 늘지 않는다 — EKS 액세스 항목의 대상 목록으로 쓴다.
#   붙이는 것은 아래 MFA 거부 정책 하나뿐이다(권한을 줄이기만 함).
# - 멤버는 Terraform 으로 관리하지 않는다(사용자 이름 · ARN 을 공개 저장소에 적지 않기 위해).
#   각자 콘솔(IAM → 사용자 그룹 → aws-lab-admins → 사용자 추가)에서 넣는다.
# - 멤버를 바꾼 뒤에는 20-cluster 를 다시 apply 해야 액세스 항목에 반영된다(클러스터를 새로 만들 때 자동 반영).
# - CI apply 역할이 이 그룹에 사용자를 넣지 못하게 하는 거부 문장은 #40 에서 더한다.
resource "aws_iam_group" "cluster_admins" {
  name = "aws-lab-admins"
}

# 그룹 멤버는 MFA 로 인증한 세션에서만 AWS 작업을 할 수 있다(Trivy AWS-0123).
# - 콘솔 · aws login 세션은 mfaAuthenticated=true(2026-11-27 CloudTrail 확인) → 지금 작업에 영향 없음.
# - 장기 액세스 키로 MFA 없이 호출하면 거부 → 키가 유출돼도 쓰지 못한다.
# - BoolIfExists: 장기 키 호출에는 aws:MultiFactorAuthPresent 키가 아예 없으므로, 없을 때도 거부되게 한다.
# - MFA 등록 · 자기 비밀번호 변경은 MFA 전에도 허용한다(새 사용자가 처음 MFA 를 등록할 수 있게).
# - EKS 접속(kubectl)은 sts:GetCallerIdentity 서명이라 이 정책과 무관하다 — 클러스터 접속은 액세스 항목이 정한다.
# - 이 정책 때문에 자기 CLI 가 막히면: 콘솔(MFA 로그인)에서 자기 사용자를 그룹에서 빼면 바로 풀린다.
data "aws_iam_policy_document" "cluster_admins_require_mfa" {
  statement {
    sid    = "DenyWithoutMFA"
    effect = "Deny"
    not_actions = [
      "iam:CreateVirtualMFADevice",
      "iam:EnableMFADevice",
      "iam:ListMFADevices",
      "iam:ResyncMFADevice",
      "iam:GetUser",
      "iam:ChangePassword",
      "sts:GetSessionToken",
    ]
    resources = ["*"]

    condition {
      test     = "BoolIfExists"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["false"]
    }
  }
}

resource "aws_iam_group_policy" "cluster_admins_require_mfa" {
  name   = "require-mfa"
  group  = aws_iam_group.cluster_admins.name
  policy = data.aws_iam_policy_document.cluster_admins_require_mfa.json
}
