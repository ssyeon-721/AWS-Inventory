#!/bin/bash

MY_AWS_ACCOUNT_ID="계정 number" ## 메인 계정 숫자를 넣어주세요

AWS_CLI=`which aws`

if [ $? -ne 0 ]; then
  echo "AWS CLI is not installed; exiting"
  exit 1
else
  echo "Using AWS CLI found at $AWS_CLI"
fi

if [ $# -ne 2 ]; then
  echo "Usage: $0  <Your_email_nickname> <MFA_TOKEN_CODE>"
  echo "Where:"
  echo "   <Your_email_nickname>  = 이메일 주소 중 @ 앞 부분을 입력해주세요."
  echo "   <MFA_TOKEN_CODE>       = Code from virtual MFA device"
  exit 2
fi

AWS_USER_PROFILE=mzc_solutions_architect
AWS_2AUTH_PROFILE=mine
ARN_OF_MFA=arn:aws:iam::$MY_AWS_ACCOUNT_ID:mfa/$1"@megazone.com"
MFA_TOKEN_CODE=$2
DURATION=28800 #8시간 기준으로 설정하였음 #최대 값 36시간 129600 

echo "AWS-CLI Profile: $AWS_2AUTH_PROFILE"
echo "MFA ARN: $ARN_OF_MFA"
echo "MFA Token Code: $MFA_TOKEN_CODE"
# set -x

read AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN <<< \
$( aws --profile $AWS_USER_PROFILE sts get-session-token \
  --duration $DURATION  \
  --serial-number $ARN_OF_MFA \
  --token-code $MFA_TOKEN_CODE \
  --output text  | awk '{ print $2, $4, $5 }')

if [ -z "$AWS_ACCESS_KEY_ID" ]
then
  exit 1
fi

`aws --profile $AWS_2AUTH_PROFILE configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"`
`aws --profile $AWS_2AUTH_PROFILE configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"`
`aws --profile $AWS_2AUTH_PROFILE configure set aws_session_token "$AWS_SESSION_TOKEN"`

echo ""
echo "You can check which account has been accessed with the command below."
echo "$ aws sts get-caller-identity --profile mine --query Account --output text"
