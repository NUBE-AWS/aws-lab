# 리전 하나에 콘솔 로그인 감시 규칙을 만들고, 맞는 이벤트를 서울 기본 이벤트 버스로 넘긴다(#44 PR 4).
# 부르는 쪽이 providers = { aws = aws.<별칭> } 로 리전을 정한다. 알림 주제 · 구독은 서울 한 곳에만 있다.

resource "aws_cloudwatch_event_rule" "login" {
  for_each = var.rules

  name          = "aws-lab-${each.key}"
  description   = "Console sign-in alert rule (this Region). Forwards matching events to the Seoul default event bus."
  state         = "ENABLED_WITH_ALL_CLOUDTRAIL_MANAGEMENT_EVENTS"
  event_pattern = jsonencode(each.value)
}

# 다른 리전의 버스로 보낼 때는 실행 역할이 필요하다(서울 버스 PutEvents 만 가진 역할).
resource "aws_cloudwatch_event_target" "login" {
  for_each = var.rules

  rule      = aws_cloudwatch_event_rule.login[each.key].name
  target_id = "seoul-bus"
  arn       = var.target_bus_arn
  role_arn  = var.forward_role_arn
}
