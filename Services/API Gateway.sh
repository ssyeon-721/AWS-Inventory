#!/bin/bash
set -euo pipefail

profile="프로파일"  #프로파일 이름을 넣어줍니다
outfile="APIgateway_inventory.csv"  #파일명 변경을 원하면 여기서 변경해줍니다 
regions=("ap-northeast-2" "us-east-1")  # 리전은 서울리전으로 설정되어 있습니다

command -v aws >/dev/null 2>&1 || { echo "ERROR: aws cli not found"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 not found (required for jq-less json parsing)"; exit 1; }

# backup
[[ -f "$outfile" ]] && cp "$outfile" "${outfile}.bak.$(date +%Y%m%d%H%M%S)"

account_id=$(aws sts get-caller-identity --profile "$profile" --query 'Account' --output text)

# CSV Header
echo "API Gateway Inventory (REST v1 + HTTP/WS v2)" > "$outfile"
echo "AccountID,Region,APIType,ApiId,Name,ProtocolType,EndpointType,ApiKeySource,DisableExecuteApiEndpoint,CreatedDate,Version,Tags,Description" >> "$outfile"

# python: write rows
py_v1='
import sys, json

account_id = sys.argv[1]
region = sys.argv[2]
outfile = sys.argv[3]

def esc(s):
    if s is None:
        s = ""
    s = str(s).replace("\r","").replace("\n"," ").replace("\"","\"\"")
    return s

def tags_to_str(tags):
    if not isinstance(tags, dict) or not tags:
        return ""
    # k=v; join
    items = []
    for k in sorted(tags.keys()):
        items.append("{}={}".format(k, tags.get(k)))
    return ";".join(items)

data = json.load(sys.stdin)
items = data.get("items") or []
with open(outfile, "a", encoding="utf-8") as f:
    for a in items:
        if not isinstance(a, dict):
            continue

        api_id = a.get("id","")
        name = a.get("name","")
        desc = a.get("description","") or ""
        created = a.get("createdDate","") or ""
        version = a.get("version","") or ""
        api_key_source = a.get("apiKeySource","") or ""
        endpoint_cfg = a.get("endpointConfiguration") or {}
        endpoint_types = ""
        if isinstance(endpoint_cfg, dict):
            endpoint_types = ";".join(endpoint_cfg.get("types") or [])
        disable_exec = a.get("disableExecuteApiEndpoint","")
        tags = tags_to_str(a.get("tags"))

        row = [
            account_id,
            region,
            "REST",              # APIType
            api_id,
            name,
            "",                  # ProtocolType (v1 없음)
            endpoint_types,      # EndpointType (EDGE/REGIONAL/PRIVATE)
            api_key_source,
            disable_exec,
            created,
            version,
            tags,
            desc,
        ]
        f.write(",".join(["\"{}\"".format(esc(x)) for x in row]) + "\n")
'

py_v2='
import sys, json

account_id = sys.argv[1]
region = sys.argv[2]
outfile = sys.argv[3]

def esc(s):
    if s is None:
        s = ""
    s = str(s).replace("\r","").replace("\n"," ").replace("\"","\"\"")
    return s

def tags_to_str(tags):
    if not isinstance(tags, dict) or not tags:
        return ""
    items = []
    for k in sorted(tags.keys()):
        items.append("{}={}".format(k, tags.get(k)))
    return ";".join(items)

data = json.load(sys.stdin)
items = data.get("Items") or []
with open(outfile, "a", encoding="utf-8") as f:
    for a in items:
        if not isinstance(a, dict):
            continue

        api_id = a.get("ApiId","")
        name = a.get("Name","")
        proto = a.get("ProtocolType","") or ""   # HTTP / WEBSOCKET
        desc = a.get("Description","") or ""
        created = a.get("CreatedDate","") or ""
        version = a.get("Version","") or ""
        disable_exec = a.get("DisableExecuteApiEndpoint","")
        tags = tags_to_str(a.get("Tags"))

        # v2는 endpoint type 개념을 get-apis에서 직접 주지 않음. (추가 호출 필요)
        row = [
            account_id,
            region,
            "V2",                # APIType
            api_id,
            name,
            proto,               # ProtocolType
            "",                  # EndpointType
            "",                  # ApiKeySource
            disable_exec,
            created,
            version,
            tags,
            desc,
        ]
        f.write(",".join(["\"{}\"".format(esc(x)) for x in row]) + "\n")
'

for region in "${regions[@]}"; do
  # REST API (v1)
  aws apigateway get-rest-apis \
    --profile "$profile" --region "$region" \
    --output json \
  | python3 -c "$py_v1" "$account_id" "$region" "$outfile" || true

  # HTTP/WebSocket API (v2)
  aws apigatewayv2 get-apis \
    --profile "$profile" --region "$region" \
    --output json \
  | python3 -c "$py_v2" "$account_id" "$region" "$outfile" || true
done

echo "made $outfile"

