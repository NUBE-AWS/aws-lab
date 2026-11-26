# 경보를 한곳에 모으는 SNS 주제(설계 8.1, #26). CloudWatch 경보 · Budgets 가 여기로 보내고,
# 두 사람이 메일로 받는다. 메일 월 1,000건까지 무료.
#
# 메일 구독은 Terraform 밖에서 각자 만든다(#26 결정 2, A안).
# - 메일 주소는 개인 정보라 공개 저장소에 커밋하지 않는다.
# - *.auto.tfvars 로 두면 CI(자동 apply)에는 그 값이 없어 구독을 실제로 지운다.
# - 절차는 README 「경보 메일 구독」.
#
# 주제 암호화(AWS-0095)는 하지 않는다 — CMK 로 암호화하면 CloudWatch · Budgets 에 키 사용 권한을
# 따로 열어야 하고, AWS 관리형 키(alias/aws/sns)는 이 서비스들이 쓸 수 없다. 내용은 경보 문구뿐이다.
#trivy:ignore:AWS-0095
resource "aws_sns_topic" "alerts" {
  name = "aws-lab-alerts"
}

data "aws_iam_policy_document" "alerts" {
  # 계정 안에서의 관리(구독 · 발행 등) — 주제 정책을 직접 쓰면 AWS 기본 정책을 대신하므로 다시 적는다.
  statement {
    sid = "AccountOwner"
    actions = [
      "SNS:GetTopicAttributes",
      "SNS:SetTopicAttributes",
      "SNS:AddPermission",
      "SNS:RemovePermission",
      "SNS:DeleteTopic",
      "SNS:Subscribe",
      "SNS:ListSubscriptionsByTopic",
      "SNS:Publish",
    ]
    resources = [aws_sns_topic.alerts.arn]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"
      values   = [local.account_id]
    }
  }

  # CloudWatch 경보 · Budgets 가 발행할 수 있게. 다른 계정의 경보가 쓰지 못하도록 이 계정으로 제한.
  statement {
    sid       = "AllowAlarmAndBudgetPublish"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.alerts.arn]
    principals {
      type = "Service"
      identifiers = [
        "cloudwatch.amazonaws.com",
        "budgets.amazonaws.com",
      ]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts.json
}
