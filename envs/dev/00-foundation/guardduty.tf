# GuardDuty(설계 5.4, #26 결정 1) — 위협 탐지. 계정 30일 무료 뒤 사용량 과금.
#
# | 기능                                  | 상태 | 이유 |
# | 기본 탐지(CloudTrail · VPC 흐름 · DNS)  | 켬  | 탐지기를 켜면 항상 돈다. VPC Flow Logs 없이 자체 흐름을 분석 → #22 예외 근거 |
# | EKS 감사 로그(EKS_AUDIT_LOGS)          | 켬  | 에이전트 없음. 클러스터를 매일 지워 이벤트도 적다 |
# | 런타임 모니터링(RUNTIME_MONITORING)     | 끔  | 자동 에이전트가 VPC 에 GuardDutyManaged 엔드포인트 · 보안 그룹을 만들어 |
# |                                       |     | 매일 하는 10-network destroy 를 막는다 |
# | S3 · EBS 악성코드 · RDS 로그인 · Lambda | 끔  | #26 범위 밖(기본 탐지 + EKS 감사만 결정). 켜는 만큼 과금 → 필요하면 따로 정한다 |
#
# 기능은 하나씩 명시한다. 적지 않으면 AWS 기본값을 따라 켜질 수 있어 비용이 코드에 드러나지 않는다.
# EKS_RUNTIME_MONITORING(옛 이름)은 RUNTIME_MONITORING 과 함께 적으면 오류라 적지 않는다.

resource "aws_guardduty_detector" "main" {
  enable = true
}

locals {
  guardduty_features = {
    EKS_AUDIT_LOGS         = "ENABLED"
    RUNTIME_MONITORING     = "DISABLED"
    S3_DATA_EVENTS         = "DISABLED"
    EBS_MALWARE_PROTECTION = "DISABLED"
    RDS_LOGIN_EVENTS       = "DISABLED"
    LAMBDA_NETWORK_LOGS    = "DISABLED"
  }
}

resource "aws_guardduty_detector_feature" "main" {
  for_each = local.guardduty_features

  detector_id = aws_guardduty_detector.main.id
  name        = each.key
  status      = each.value
}
