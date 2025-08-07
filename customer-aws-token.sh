#!/bin/bash

if [ $# -ne 2 ]; then
  echo "Usage: $0  <Account ID> <Customer's_nickname>"
  echo "Where:"
  echo "   <Customer's_Account_ID>               = Customer's AWS Account ID(12-digit)"
  echo "   <Customer's_nickname>      = Nickname to identify customer's AWS ID"
  exit 2
fi

ACCOUNT_ID=$1
PROFILE=$2

REGISTRATION_CHECK_ACCOUNT=$(cat ~/.aws/config | grep "arn:aws:iam::"$ACCOUNT_ID":role/mzc_solutions_architect" | wc -l)
REGISTRATION_CHECK_NICKNAME=$(cat ~/.aws/config | grep $PROFILE | wc -l)

if [[ $REGISTRATION_CHECK_ACCOUNT -ge 1 ]]; then
  echo "The customer's role is already registered in the ~/.aws/config file."
else
  if [[ $REGISTRATION_CHECK_NICKNAME -ge 1 ]]; then
    echo "The nickname is already registered in ~/.aws/config file."
  else
    echo "[profile "$PROFILE"]" >> ~/.aws/config
    echo "role_arn = arn:aws:iam::"$ACCOUNT_ID":role/mzc_solutions_architect" >> ~/.aws/config
    echo "source_profile = mine" >> ~/.aws/config

    echo -e "\n""A# " $ACCOUNT_ID ": Define the credential setting as" $PROFILE "profile(~/.aws/config)."
    echo "You can check which account has been accessed with the command below."
    echo "$ aws-token.sh <Your_email_nickname> <MFA_TOKEN_CODE>"
    echo "$ aws sts get-caller-identity --query Account --output text --profile " $PROFILE
  fi
fi
