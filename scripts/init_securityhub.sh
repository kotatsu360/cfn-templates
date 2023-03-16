#!/bin/bash

set -e

export AWS_PAGER=''

parser_definition() {
  setup   REST help:usage -- "Usage: $0 [options]... [arguments]..." ''
  msg -- 'Options:'
  param   AUDIT_ACCOUNT --audit-account                   -- "[required] The Amazon Web Services account identifier of the account to designate as the Security Hub administrator account."
  # param   MGMT_ACCOUNT  --mgmt-account                    -- ""
  param   PROFILE       -p --profile                      -- "Use a specific profile from your credential file."
  param   REGION        -r --region init:="ap-northeast-1" -- "The region to use. Overrides config/env settings."
  disp    :usage        -h --help
}

eval "$(getoptions parser_definition) exit 1"

if [ -z "${AUDIT_ACCOUNT}" ]; then
    usage
fi

if [ ! -z "${PROFILE}" ]; then
    PROFILE="--profile ${PROFILE}"
fi

REGIONS=($(aws account list-regions --output text --query 'Regions|[?RegionOptStatus!=`DISABLED`].RegionName' --region ${REGION} ${PROFILE}))

for r in ${REGIONS[*]}; do
    echo "========== ${r} =========="
    admin=$(aws securityhub list-organization-admin-accounts \
                --output text \
                --query "AdminAccounts[0].AccountId" \
                --region ${r} ${PROFILE})

    if [ "None" = "${admin}" ]; then
        echo 'enable organization admin now'
        aws securityhub enable-organization-admin-account \
            --admin-account-id ${AUDIT_ACCOUNT} \
            --region ${r} ${PROFILE}
    else
        echo 'already enabled organization admin'
        echo "admin: ${admin}"
    fi
    echo ''


    # example: セキュリティ基準を有効化する場合
    # echo 'enable standards'
    # cis="arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.2.0"
    # best_practice="arn:aws:securityhub:${r}::standards/aws-foundational-security-best-practices/v/1.0.0"
    # aws securityhub batch-enable-standards \
    #     --standards-subscription-requests "[{\"StandardsArn\":\"${cis}\"},{\"StandardsArn\":\"${best_practice}\"}]" \
    #     --region ${r} ${profile}


    # example: セキュリティ基準を無効化する場合
    # echo 'disable standards'
    # standards=("arn:aws:securityhub:${r}:${MGMT_ACCOUNT}:subscription/cis-aws-foundations-benchmark/v/1.2.0"
    #            "arn:aws:securityhub:${r}:${MGMT_ACCOUNT}:subscription/aws-foundational-security-best-practices/v/1.0.0")
    # aws securityhub batch-disable-standards --standards-subscription-arns ${standards[*]} --region ${r} ${profile}

done
