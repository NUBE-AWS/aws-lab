# 사람의 액세스 항목(#50, 설계 4.1 · 가이드 10장 5단계)
#
# - 클러스터는 authentication_mode = "API" 이고 생성자 관리자 권한을 끈다(main.tf). 그래서 이 항목이 없으면
#   클러스터가 생겨도 두 사람 모두 kubectl 을 쓸 수 없다.
# - 대상은 00-foundation 의 IAM 그룹 aws-lab-admins 멤버(#50 C안). 사용자 이름 · ARN 을 공개 저장소에 적지 않으려고
#   그룹을 조회한다. 멤버는 각자 콘솔에서 넣고, 바꾼 뒤에는 이 스택을 다시 apply 해야 반영된다.
# - 맵 키는 사용자 이름이 아니라 IAM 고유 ID(AIDA…)를 쓴다. 키는 자원 주소가 되어 plan · apply 로그와
#   PR plan 댓글(destroy · replace 목록)에 나오므로, 로그인에 쓰이는 이름을 드러내지 않는다.
# - CI 역할에는 액세스 항목을 만들지 않는다. Karpenter 노드 역할의 항목(EC2_LINUX)은 karpenter.tf 의 모듈이 만든다.

data "aws_iam_group" "cluster_admins" {
  group_name = local.foundation.cluster_admins_group_name
}

locals {
  cluster_admin_arns = { for u in data.aws_iam_group.cluster_admins.users : u.user_id => u.arn }
}

# 그룹이 비면 액세스 항목 0개로 조용히 통과한다 → 아무도 kubectl 을 못 쓰는 클러스터가 생긴다. plan 단계에서 멈춘다.
resource "terraform_data" "cluster_admins_precondition" {
  lifecycle {
    precondition {
      condition     = length(local.cluster_admin_arns) > 0
      error_message = "IAM 그룹 aws-lab-admins 에 사용자가 없습니다. 콘솔(IAM → 사용자 그룹)에서 자기 사용자를 넣은 뒤 다시 실행합니다(#50)."
    }
  }
}
