# EKS 클러스터 관리자 그룹(#50, 설계 4.1) — 20-cluster 가 이 그룹의 멤버를 조회해 사람의 액세스 항목을 만든다.
#
# - IAM 「사용자 그룹」이다. IAM Identity Center · Organizations 와 무관하고 요금 · 계정 상태 변화가 없다.
# - 정책을 붙이지 않는다. 그룹에 든다고 AWS 권한이 늘지 않는다 — EKS 액세스 항목의 대상 목록으로만 쓴다.
# - 멤버는 Terraform 으로 관리하지 않는다(사용자 이름 · ARN 을 공개 저장소에 적지 않기 위해).
#   각자 콘솔(IAM → 사용자 그룹 → aws-lab-admins → 사용자 추가)에서 넣는다.
# - 멤버를 바꾼 뒤에는 20-cluster 를 다시 apply 해야 액세스 항목에 반영된다(클러스터를 새로 만들 때 자동 반영).
# - CI apply 역할이 이 그룹에 사용자를 넣지 못하게 하는 거부 문장은 #40 에서 더한다.
resource "aws_iam_group" "cluster_admins" {
  name = "aws-lab-admins"
}
