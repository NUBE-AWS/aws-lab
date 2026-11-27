# 업무 화면 로그인용 Cognito 사용자 풀(설계 4.3, 가이드 9장 6단계, #44 결정 2)
#
# - ALB 가 이 풀로 사용자를 인증한다(NetBox 앞단). 25-addons 가 출력 3개를 원격 상태로 읽는다.
# - 00-foundation(상시)에 두는 이유: 매일 지우면 사용자 · MFA 등록을 매일 다시 해야 한다.
# - 등급 ESSENTIALS 명시: 월 활성 사용자 1만 명까지 무료. PLUS(위협 탐지)는 사용자당 요금이 붙어 쓰지 않는다.
# - 자가 가입 없음(관리자만 사용자 생성), MFA 필수(TOTP 앱만 — SMS 를 쓰지 않아 SMS 요금 · SNS 설정 없음).
# - 도메인 접두어 nube-lab-dev: 전 세계에서 고유해야 하고 aws · amazon · cognito 는 넣을 수 없다.
#   이미 쓰이고 있으면 apply 가 실패한다 → 다른 접두어로 바꾸는 PR.
# - 앱 클라이언트 비밀: ALB 가 Cognito 에서 직접 쓰므로 출력하지 않는다. 공급자 스키마상 상태 파일에는 저장된다
#   (sensitive 는 화면 출력만 가림 → 상태 버킷 보호가 맡는다).
# - 사용자 생성은 가이드 17장 1단계(사람이 함). 사용자 이름 · 메일은 코드에 적지 않는다.

resource "aws_cognito_user_pool" "apps" {
  name           = "aws-lab-apps"
  user_pool_tier = "ESSENTIALS"

  # 실수로 지우면 사용자 · MFA 등록이 모두 사라진다. 지우려면 먼저 이 값을 INACTIVE 로 바꾸는 PR.
  deletion_protection = "ACTIVE"

  mfa_configuration = "ON"
  software_token_mfa_configuration {
    enabled = true
  }

  admin_create_user_config {
    allow_admin_create_user_only = true
  }
}

resource "aws_cognito_user_pool_domain" "apps" {
  domain       = "nube-lab-dev"
  user_pool_id = aws_cognito_user_pool.apps.id
}

# ALB 인증용 앱 클라이언트(ALB 문서 요건: 클라이언트 비밀 · code 흐름 · openid · 콜백 /oauth2/idpresponse, 소문자).
resource "aws_cognito_user_pool_client" "alb" {
  name                                 = "alb"
  user_pool_id                         = aws_cognito_user_pool.apps.id
  generate_secret                      = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid"]
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = ["https://netbox.aws.nube.it.kr/oauth2/idpresponse"]

  # 없는 사용자와 틀린 비밀번호를 같은 오류로 돌려준다(사용자 존재 여부를 알려 주지 않음).
  prevent_user_existence_errors = "ENABLED"
}
