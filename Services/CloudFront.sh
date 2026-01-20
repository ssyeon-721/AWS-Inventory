#!/bin/bash
set -euo pipefail

profile="프로파일"  #프로파일 이름을 넣어줍니다. 
outfile="cloudfront_full_inventory.csv"  #파일 이름을 변경하고 싶으면 여기서 변경해줍니다

command -v aws >/dev/null 2>&1 || { echo "ERROR: aws cli not found"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 not found"; exit 1; }

# backup
[[ -f "$outfile" ]] && cp "$outfile" "${outfile}.bak.$(date +%Y%m%d%H%M%S)"

account_id=$(aws sts get-caller-identity --profile "$profile" --query 'Account' --output text)

echo "CloudFront Distribution Information" > "$outfile"
echo "AccountID,Service,DistributionId,ARN,DomainName,Status,Enabled,Comment,PriceClass,HTTPVersion,IsIPV6Enabled,WebACLId,LastModifiedTime,Origins,OriginGroups,DefaultCacheBehavior,CacheBehaviors,Aliases,ViewerCertificate,Logging,Restrictions,CustomErrorResponses" >> "$outfile"

py_parse='
import sys, json

account_id = sys.argv[1]
outfile = sys.argv[2]

def esc(s):
    if s is None:
        s = ""
    s = str(s).replace("\r","").replace("\n"," ").replace("\"","\"\"")
    return s

def join_list(items):
    return ";".join([str(x) for x in items if x])

def origin_summary(o):
    oid = o.get("Id","")
    dn  = o.get("DomainName","")
    op  = o.get("OriginPath","")
    oai = ""
    proto = ""

    if isinstance(o.get("S3OriginConfig"), dict):
        oai = o["S3OriginConfig"].get("OriginAccessIdentity","")
        typ = "S3"
    elif isinstance(o.get("CustomOriginConfig"), dict):
        proto = o["CustomOriginConfig"].get("OriginProtocolPolicy","")
        typ = "Custom"
    else:
        typ = "Unknown"

    if not oai:
        oai = o.get("OriginAccessControlId","")

    return "|".join(map(esc,[oid,dn,op,typ,oai,proto]))

def behavior_summary(b):
    lambdas = []
    la = b.get("LambdaFunctionAssociations",{})
    for it in la.get("Items",[]) or []:
        lambdas.append("{}:{}".format(
            it.get("EventType",""),
            it.get("LambdaFunctionARN","")
        ))

    funcs = []
    fa = b.get("FunctionAssociations",{})
    for it in fa.get("Items",[]) or []:
        funcs.append("{}:{}".format(
            it.get("EventType",""),
            it.get("FunctionARN","")
        ))

    allowed = b.get("AllowedMethods",{})
    am = allowed.get("Items",[]) if isinstance(allowed,dict) else []
    cm = allowed.get("CachedMethods",{}).get("Items",[]) if isinstance(allowed,dict) else []

    return "|".join(map(esc,[
        b.get("TargetOriginId",""),
        b.get("ViewerProtocolPolicy",""),
        join_list(am),
        join_list(cm),
        b.get("CachePolicyId",""),
        b.get("OriginRequestPolicyId",""),
        b.get("ResponseHeadersPolicyId",""),
        b.get("Compress",""),
        b.get("SmoothStreaming",""),
        join_list(lambdas),
        join_list(funcs),
    ]))

data = json.load(sys.stdin)
items = data.get("DistributionList",{}).get("Items",[]) or []

with open(outfile,"a",encoding="utf-8") as f:
    for d in items:
        row = [
            account_id,
            "cloudfront",
            d.get("Id",""),
            d.get("ARN",""),
            d.get("DomainName",""),
            d.get("Status",""),
            d.get("Enabled",""),
            d.get("Comment",""),
            d.get("PriceClass",""),
            d.get("HttpVersion",""),
            d.get("IsIPV6Enabled",""),
            d.get("WebACLId",""),
            d.get("LastModifiedTime",""),
            ";".join([origin_summary(x) for x in d.get("Origins",{}).get("Items",[]) or []]),
            "",
            behavior_summary(d.get("DefaultCacheBehavior",{})),
            "",
            join_list(d.get("Aliases",{}).get("Items",[]) or []),
            "",
            "",
            "",
            ""
        ]
        f.write(",".join(["\"{}\"".format(esc(x)) for x in row]) + "\n")
'

aws cloudfront list-distributions \
  --profile "$profile" \
  --output json \
| python3 -c "$py_parse" "$account_id" "$outfile"

echo "made $outfile"

