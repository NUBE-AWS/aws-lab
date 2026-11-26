# EKS Secret 봉투 암호화용 KMS 키(설계 3.2, #26). 온프레미스 etcd 암호화에 대응한다.
# - 00-foundation 에 두는 이유: 클러스터(20-cluster)를 매일 지워도 키는 남아,
#   삭제 대기(7~30일) 키가 날마다 쌓이지 않는다. 키 하나에 월 1달러.
# - 20-cluster 는 EKS 모듈의 키 생성을 끄고(create_kms_key = false) 출력 eks_kms_key_arn 을
#   terraform_remote_state 로 받는다. 클러스터 역할의 키 권한은 20-cluster 작성 때 정한다.
# - 키 정책은 적지 않는다 → AWS 기본 정책(계정 루트에 전체 권한 = IAM 정책으로 권한을 준다).

resource "aws_kms_key" "eks" {
  # KMS description 도 AWS 로 보내므로 영문으로 쓴다(#18).
  description             = "aws-lab EKS secrets envelope encryption"
  enable_key_rotation     = true # 1년마다 자동 회전
  deletion_window_in_days = 7    # 실수로 지웠을 때 되돌릴 수 있는 기간(최소값)
}

resource "aws_kms_alias" "eks" {
  name          = "alias/aws-lab-eks"
  target_key_id = aws_kms_key.eks.key_id
}
