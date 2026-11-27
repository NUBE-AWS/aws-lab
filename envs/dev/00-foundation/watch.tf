# 관리자 권한 감시 규칙 + GuardDuty 결과 알림 → SNS aws-lab-alerts (설계 5.5 · 가이드 9.7 1단계, #44 PR 4)
#
# CloudTrail 은 기록만 한다. 이 규칙들이 「위험한 일이 일어나면 바로 메일」을 더한다. 막지는 않고 알린다.
#
# 규칙을 두는 리전이 이벤트마다 다르다.
# | 리전                         | 규칙                                              | 이유 |
# | us-east-1                    | api_rules(루트 API · IAM 자격 증명 · CI 역할 · OIDC) | IAM 같은 전역 서비스의 API 이벤트는 us-east-1 에만 온다 |
# | us-east-1 · us-east-2 · us-west-2 · eu-north-1 · ap-southeast-2 | login_rules(모듈) | 콘솔 로그인은 주체 · 경로에 따라 이 중 한 곳에 기록된다 |
# | 서울                         | received(위 두 묶음의 패턴) · seoul_rules · GuardDuty | 넘어온 이벤트 + 서울 자체 이벤트, 알림 주제는 서울에만 |
#
# 서울 밖 규칙은 서울 기본 버스로 넘기고(전달 역할), 서울 규칙이 SNS 로 보낸다(발행 역할).
# 발행은 주제 정책에 events.amazonaws.com 을 열지 않고 규칙 대상의 실행 역할로 한다(설계 5.5).
# 역할만으로 발행되는지는 확정하지 못해(가이드 9.7) 적용 뒤 경보 시험으로 확인하고,
# 오지 않으면 주제 정책에 조건(aws:SourceArn · aws:SourceAccount)을 붙인 허용을 더한다(설계 10장).
#
# state: CloudTrail 관리 이벤트(API 호출 · 콘솔 로그인)를 받는 규칙은 ENABLED_WITH_ALL_CLOUDTRAIL_MANAGEMENT_EVENTS
# (읽기 전용 이벤트까지 받음 — 루트의 조회 호출도 알림). GuardDuty 결과는 CloudTrail 이벤트가 아니라 ENABLED.
#
# 요금: AWS 서비스 이벤트를 규칙이 받는 것은 무료. 리전 간 전달은 맞는 이벤트만 넘어가 건수가 적고,
# SNS 메일은 월 1,000건 무료 → 사실상 0.
#
# 한계(가이드 9.7):
# - 패턴 필드 이름이 틀려도 validate 는 통과하고 그 규칙은 조용히 아무것에도 맞지 않는다 → 규칙마다 한 번씩 울려 확인.
# - guardduty-disable 의 UpdateDetector 는 기능을 켜는 호출에도 맞는다. kms-key-disable 은 계정의 모든 키에 맞는다.
# - 루트가 MFA 없이 로그인하면 root-console-login · console-login-no-mfa 두 통이 온다.

locals {
  seoul_bus_arn = "arn:aws:events:${var.region}:${local.account_id}:event-bus/default"

  api_rules = {
    root-activity = {
      "detail-type" = ["AWS API Call via CloudTrail"]
      detail        = { userIdentity = { type = ["Root"] } }
    }
    iam-credential-create = {
      source        = ["aws.iam"]
      "detail-type" = ["AWS API Call via CloudTrail"]
      detail        = { eventName = ["CreateUser", "CreateAccessKey", "CreateLoginProfile"] }
    }
    # GitHubActionsPlan · GitHubActionsApply · GitHubActionsNightlyCheck
    ci-role-change = {
      source        = ["aws.iam"]
      "detail-type" = ["AWS API Call via CloudTrail"]
      detail = {
        eventName         = ["UpdateAssumeRolePolicy", "PutRolePolicy", "AttachRolePolicy", "DetachRolePolicy", "DeleteRolePolicy", "DeleteRole"]
        requestParameters = { roleName = [{ prefix = "GitHubActions" }] }
      }
    }
    oidc-provider-change = {
      source        = ["aws.iam"]
      "detail-type" = ["AWS API Call via CloudTrail"]
      detail = {
        eventName = [
          "CreateOpenIDConnectProvider",
          "DeleteOpenIDConnectProvider",
          "UpdateOpenIDConnectProviderThumbprint",
          "AddClientIDToOpenIDConnectProvider",
          "RemoveClientIDFromOpenIDConnectProvider",
        ]
      }
    }
  }

  login_rules = {
    root-console-login = {
      "detail-type" = ["AWS Console Signin via CloudTrail"]
      detail        = { userIdentity = { type = ["Root"] } }
    }
    console-login-no-mfa = {
      "detail-type" = ["AWS Console Signin via CloudTrail"]
      detail        = { additionalEventData = { MFAUsed = ["No"] } }
    }
  }

  # 서울 수신 규칙: 넘어온 이벤트와 서울 자체 이벤트를 같은 패턴으로 받는다.
  # 리전 조건은 두지 않는다(넘어온 이벤트의 region 필드 값을 확인하지 못함).
  received_rules = merge(local.api_rules, local.login_rules)

  seoul_rules = {
    cloudtrail-stop-delete = {
      source        = ["aws.cloudtrail"]
      "detail-type" = ["AWS API Call via CloudTrail"]
      detail        = { eventName = ["StopLogging", "DeleteTrail", "UpdateTrail", "PutEventSelectors"] }
    }
    log-bucket-policy = {
      source        = ["aws.s3"]
      "detail-type" = ["AWS API Call via CloudTrail"]
      detail = {
        eventName         = ["PutBucketPolicy", "DeleteBucketPolicy"]
        requestParameters = { bucketName = [local.cloudtrail_bucket] }
      }
    }
    guardduty-disable = {
      source        = ["aws.guardduty"]
      "detail-type" = ["AWS API Call via CloudTrail"]
      detail        = { eventName = ["DeleteDetector", "UpdateDetector"] }
    }
    kms-key-disable = {
      source        = ["aws.kms"]
      "detail-type" = ["AWS API Call via CloudTrail"]
      detail        = { eventName = ["ScheduleKeyDeletion", "DisableKey"] }
    }
  }
}

# ── us-east-1: 전역 API 규칙 → 서울 버스 ─────────────────────────

resource "aws_cloudwatch_event_rule" "api" {
  for_each = local.api_rules
  provider = aws.us_east_1

  name          = "aws-lab-${each.key}"
  description   = "Admin-activity alert rule (global API calls, us-east-1). Forwards to the Seoul default event bus."
  state         = "ENABLED_WITH_ALL_CLOUDTRAIL_MANAGEMENT_EVENTS"
  event_pattern = jsonencode(each.value)
}

resource "aws_cloudwatch_event_target" "api_forward" {
  for_each = local.api_rules
  provider = aws.us_east_1

  rule      = aws_cloudwatch_event_rule.api[each.key].name
  target_id = "seoul-bus"
  arn       = local.seoul_bus_arn
  role_arn  = aws_iam_role.eventbridge_forward.arn
}

# ── 서울 밖 다섯 리전: 콘솔 로그인 규칙 → 서울 버스 ─────────────────

module "login_us_east_1" {
  source    = "./modules/regional-login-rules"
  providers = { aws = aws.us_east_1 }

  rules            = local.login_rules
  target_bus_arn   = local.seoul_bus_arn
  forward_role_arn = aws_iam_role.eventbridge_forward.arn
}

module "login_us_east_2" {
  source    = "./modules/regional-login-rules"
  providers = { aws = aws.us_east_2 }

  rules            = local.login_rules
  target_bus_arn   = local.seoul_bus_arn
  forward_role_arn = aws_iam_role.eventbridge_forward.arn
}

module "login_us_west_2" {
  source    = "./modules/regional-login-rules"
  providers = { aws = aws.us_west_2 }

  rules            = local.login_rules
  target_bus_arn   = local.seoul_bus_arn
  forward_role_arn = aws_iam_role.eventbridge_forward.arn
}

module "login_eu_north_1" {
  source    = "./modules/regional-login-rules"
  providers = { aws = aws.eu_north_1 }

  rules            = local.login_rules
  target_bus_arn   = local.seoul_bus_arn
  forward_role_arn = aws_iam_role.eventbridge_forward.arn
}

module "login_ap_southeast_2" {
  source    = "./modules/regional-login-rules"
  providers = { aws = aws.ap_southeast_2 }

  rules            = local.login_rules
  target_bus_arn   = local.seoul_bus_arn
  forward_role_arn = aws_iam_role.eventbridge_forward.arn
}

# ── 전달 역할: 서울 기본 버스 PutEvents 하나만 ─────────────────────
# 신뢰는 위 전달 규칙들의 ARN + 이 계정으로 제한(혼동된 대리인 방지).

data "aws_iam_policy_document" "eventbridge_forward_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values = concat(
        [for r in aws_cloudwatch_event_rule.api : r.arn],
        module.login_us_east_1.rule_arns,
        module.login_us_east_2.rule_arns,
        module.login_us_west_2.rule_arns,
        module.login_eu_north_1.rule_arns,
        module.login_ap_southeast_2.rule_arns,
      )
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "eventbridge_forward" {
  name               = "aws-lab-eventbridge-forward"
  assume_role_policy = data.aws_iam_policy_document.eventbridge_forward_assume.json
}

data "aws_iam_policy_document" "eventbridge_forward" {
  statement {
    actions   = ["events:PutEvents"]
    resources = [local.seoul_bus_arn]
  }
}

resource "aws_iam_role_policy" "eventbridge_forward" {
  name   = "put-events-seoul-bus"
  role   = aws_iam_role.eventbridge_forward.id
  policy = data.aws_iam_policy_document.eventbridge_forward.json
}

# ── 발행 역할: 알림 주제 sns:Publish 하나만 ──────────────────────
# 신뢰는 서울의 SNS 대상 규칙 ARN + 이 계정으로 제한.

data "aws_iam_policy_document" "eventbridge_sns_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values = concat(
        [for r in aws_cloudwatch_event_rule.received : r.arn],
        [for r in aws_cloudwatch_event_rule.seoul : r.arn],
        [aws_cloudwatch_event_rule.guardduty_finding.arn],
      )
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "eventbridge_sns" {
  name               = "aws-lab-eventbridge-sns"
  assume_role_policy = data.aws_iam_policy_document.eventbridge_sns_assume.json
}

data "aws_iam_policy_document" "eventbridge_sns" {
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }
}

resource "aws_iam_role_policy" "eventbridge_sns" {
  name   = "publish-alerts-topic"
  role   = aws_iam_role.eventbridge_sns.id
  policy = data.aws_iam_policy_document.eventbridge_sns.json
}

# ── 서울: 수신 규칙 · 서울 규칙 → SNS ──────────────────────────────

resource "aws_cloudwatch_event_rule" "received" {
  for_each = local.received_rules

  name          = "aws-lab-${each.key}"
  description   = "Admin-activity alert rule (Seoul). Receives events forwarded from other Regions and Seoul-native events."
  state         = "ENABLED_WITH_ALL_CLOUDTRAIL_MANAGEMENT_EVENTS"
  event_pattern = jsonencode(each.value)
}

resource "aws_cloudwatch_event_target" "received" {
  for_each = local.received_rules

  rule      = aws_cloudwatch_event_rule.received[each.key].name
  target_id = "alerts-topic"
  arn       = aws_sns_topic.alerts.arn
  role_arn  = aws_iam_role.eventbridge_sns.arn
}

resource "aws_cloudwatch_event_rule" "seoul" {
  for_each = local.seoul_rules

  name          = "aws-lab-${each.key}"
  description   = "Admin-activity alert rule (Seoul Region)"
  state         = "ENABLED_WITH_ALL_CLOUDTRAIL_MANAGEMENT_EVENTS"
  event_pattern = jsonencode(each.value)
}

resource "aws_cloudwatch_event_target" "seoul" {
  for_each = local.seoul_rules

  rule      = aws_cloudwatch_event_rule.seoul[each.key].name
  target_id = "alerts-topic"
  arn       = aws_sns_topic.alerts.arn
  role_arn  = aws_iam_role.eventbridge_sns.arn
}

# ── 서울: GuardDuty 결과(심각도 4 이상 = Medium · High · Critical) → SNS (#44 문진중 님 추가 요청) ──
# 탐지기가 서울에만 있어 서울에만 둔다. 새 결과는 몇 분 안에 오고, 같은 결과의 반복 발생분은
# 탐지기의 finding_publishing_frequency(기본 SIX_HOURS) 주기로 다시 온다 — 탐지기 설정을 바꾸면
# #40 거부(UpdateDetector)에 걸려 사람 apply 가 되므로 기본값을 둔다.
resource "aws_cloudwatch_event_rule" "guardduty_finding" {
  name        = "aws-lab-guardduty-finding"
  description = "GuardDuty findings with severity 4 or higher (Medium and above)"
  state       = "ENABLED"
  event_pattern = jsonencode({
    source        = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
    detail        = { severity = [{ numeric = [">=", 4] }] }
  })
}

resource "aws_cloudwatch_event_target" "guardduty_finding" {
  rule      = aws_cloudwatch_event_rule.guardduty_finding.name
  target_id = "alerts-topic"
  arn       = aws_sns_topic.alerts.arn
  role_arn  = aws_iam_role.eventbridge_sns.arn
}
