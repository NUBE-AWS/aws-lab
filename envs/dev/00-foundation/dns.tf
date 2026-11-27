# AWS 쪽 공개 DNS 영역(설계 3.5, #44 결정 1) — aws.nube.it.kr
#
# - nube.it.kr 전체가 아니라 하위 도메인 aws.nube.it.kr 만 Route 53 이 맡는다.
#   nube.it.kr 의 네임서버는 팀 온프레미스 DNS(ns1.nube.it.kr)이고, 그대로 둔다(팀 공개 레코드에 영향 없음).
# - 위임: apply 뒤 출력 name_servers 4개를 ns1 의 nube.it.kr 영역에 「aws NS ...」 4줄로 넣는다(사람이 하는 일, 문진중).
#   값은 공개 DNS 정보지만 이슈 · PR 에 붙이지 않고 직접 전달한다.
#   반영 확인: Resolve-DnsName aws.nube.it.kr -Type NS -Server 8.8.8.8 → Route 53 네임서버 4개.
# - ACM 인증서(*.aws.nube.it.kr, DNS 검증)는 위임이 반영된 뒤 다음 PR 에서 만든다 — 먼저 만들면 검증이 75분 기다리다 실패.
# - 호스트 이름은 <서비스>.aws.nube.it.kr(온프레미스 <서비스>.k8s.nube.it.kr 에 대응). external-dns 는 이 영역만 다룬다.
# - 00-foundation(상시)에 두는 이유: 영역을 지우고 다시 만들면 네임서버 4개가 바뀌어 ns1 위임을 매번 고쳐야 한다.
# - 비용: 영역 하나 월 0.50달러 + 질의 요금(소액).

variable "dns_zone_name" {
  description = "Public hosted zone for AWS-side host names (<service>.aws.nube.it.kr). Delegated from the team DNS (ns1.nube.it.kr)."
  type        = string
  default     = "aws.nube.it.kr"
}

resource "aws_route53_zone" "aws" {
  name    = var.dns_zone_name
  comment = "aws-lab public zone, delegated from ns1.nube.it.kr (#44)"
}
