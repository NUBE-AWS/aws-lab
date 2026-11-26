<!-- 항목에 해당이 없으면 지우지 말고 「없음」이라고 적습니다. -->

## 무엇을 · 왜

<!-- 한두 줄. 「왜」가 있어야 리뷰어가 맞는 변경인지 판단할 수 있습니다. -->

## 변경 범위

<!-- 건드린 스택에 표시합니다. 스택마다 상태 파일이 따로라 apply도 스택별로 합니다. -->

- [ ] `bootstrap/` (상태 버킷)
- [ ] `envs/dev/00-foundation/`
- [ ] `envs/dev/10-network/`
- [ ] `envs/dev/20-cluster/`
- [ ] `envs/dev/30-data/`
- [ ] Terraform 밖(문서 · `.github/` · 기타)

## `terraform plan` 요약

<!--
스택마다 마지막 줄을 붙입니다. 예) 10-network: Plan: 12 to add, 0 to change, 0 to destroy.
destroy 또는 replace(-/+)가 있으면 리소스 이름과 이유를 적습니다.
plan이 없는 변경(문서 등)은 「plan 없음」.
-->

| 스택 | add | change | destroy |
| :-- | --: | --: | --: |
|  |  |  |  |

**destroy · replace 이유:**

## 비용 영향

<!--
켜 두면 요금이 나가는 리소스(NAT 게이트웨이, EKS, ALB, RDS 등)가 생기거나 사라지는지,
Infracost에 표시된 월 예상 금액의 변화를 적습니다.
-->

- 월 예상 비용 변화(Infracost):
- 요금이 나가는 새 리소스:
- 끄는 계획(언제, 어떤 순서로 destroy):

## 확인

- [ ] `terraform fmt -check -recursive` 통과
- [ ] 바뀐 스택에서 `terraform validate` 통과
- [ ] `plan`을 직접 읽었고, 의도하지 않은 변경이 없다
- [ ] 키 · 비밀번호 · 계정 프로필 같은 비밀 값이 코드와 이 PR 본문에 없다
