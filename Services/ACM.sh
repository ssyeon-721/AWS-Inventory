#!/bin/bash
set -euo pipefail

profile="2bytes"
outfile="acm_inventory.csv"
regions=("ap-northeast-2" "us-east-1")

# ---- precheck ----
command -v aws >/dev/null 2>&1 || { echo "ERROR: aws cli not found"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 not found (required for jq-less json parsing)"; exit 1; }

# ---- backup ----
if [[ -f "$outfile" ]]; then
  cp "$outfile" "${outfile}.bak.$(date +%Y%m%d%H%M%S)"
fi

# 계정 ID
account_id=$(aws sts get-caller-identity --profile "$profile" --query 'Account' --output text)

# CSV Header
echo "ACM Certificate Information" > "$outfile"
echo "AccountID,Region,CertificateArn,DomainName,SubjectAlternativeNames,Type,Status,InUseBy,IssuedAt,NotBefore,NotAfter,RenewalEligibility,KeyAlgorithm,SignatureAlgorithm,Serial,DomainValidationMethods" >> "$outfile"

# python3: JSON(Certificate) -> CSV row
# - 입력: stdin으로 Certificate JSON
# - 출력: CSV 값 13개(ARN 제외) 콤마로 연결된 "..." 형태
py_parse='
import sys, json

def esc(s: str) -> str:
    if s is None:
        s = ""
    s = str(s)
    s = s.replace("\r", "").replace("\n", " ")
    s = s.replace("\"", "\"\"")
    return s

try:
    cert = json.load(sys.stdin)
except Exception:
    sys.exit(2)

domain_name = cert.get("DomainName", "")
san = cert.get("SubjectAlternativeNames") or []
san_list = ";".join([x for x in san if isinstance(x, str)])

cert_type = cert.get("Type", "")
status = cert.get("Status", "")

in_use = cert.get("InUseBy") or []
in_use_by = ";".join([x for x in in_use if isinstance(x, str)])

issued_at = cert.get("IssuedAt", "")
not_before = cert.get("NotBefore", "")
not_after = cert.get("NotAfter", "")

renewal_elig = cert.get("RenewalEligibility", "")
key_algo = cert.get("KeyAlgorithm", "")
sig_algo = cert.get("SignatureAlgorithm", "")
serial = cert.get("Serial", "")

dvo = cert.get("DomainValidationOptions") or []
methods = []
for x in dvo:
    if isinstance(x, dict):
        m = x.get("ValidationMethod", "")
        if m:
            methods.append(m)
dv_methods = ";".join(methods)

fields = [
    domain_name,
    san_list,
    cert_type,
    status,
    in_use_by,
    issued_at,
    not_before,
    not_after,
    renewal_elig,
    key_algo,
    sig_algo,
    serial,
    dv_methods
]

# CSV는 bash에서 따로 묶지 않고 여기서 "..." 형태로 출력
out = ",".join([f"\"{esc(v)}\"" for v in fields])
sys.stdout.write(out)
'

for region in "${regions[@]}"; do
  aws acm list-certificates \
    --profile "$profile" --region "$region" \
    --includes keyTypes=RSA_1024,RSA_2048,RSA_3072,RSA_4096,EC_prime256v1,EC_secp384r1,EC_secp521r1 \
    --certificate-statuses PENDING_VALIDATION ISSUED INACTIVE EXPIRED VALIDATION_TIMED_OUT REVOKED FAILED \
    --query 'CertificateSummaryList[*].CertificateArn' \
    --output text | tr -d '\r' | tr '\t' '\n' |
  while IFS= read -r cert_arn; do
    [[ -z "$cert_arn" || "$cert_arn" == "None" ]] && continue

    # 인증서 1개당 describe 1회
    cert_json=$(
      aws acm describe-certificate \
        --profile "$profile" --region "$region" \
        --certificate-arn "$cert_arn" \
        --query 'Certificate' \
        --output json 2>/dev/null || true
    )
    [[ -z "$cert_json" || "$cert_json" == "null" ]] && continue

    # python으로 파싱 → CSV 컬럼 문자열 생성
    parsed=$(
      printf '%s' "$cert_json" | python3 -c "$py_parse" 2>/dev/null || true
    )
    [[ -z "$parsed" ]] && continue

    # 최종 CSV write
    # (AccountID,Region,Arn) + python이 만든 나머지 13개 컬럼
    printf '"%s","%s","%s",%s\n' \
      "$account_id" "$region" "$cert_arn" "$parsed" >> "$outfile"
  done
done

echo "made $outfile"
