#!/bin/bash

set -e

export AWS_PAGER=''

parser_definition() {
  setup   REST help:usage -- "Usage: $0 [options]... [arguments]..." ''
  msg -- 'Options:'
  param   AUDIT_ACCOUNT --audit-account                    -- "[required] The Amazon Web Services account identifier of the account to designate as the Security Hub administrator account."
  # param   MGMT_ACCOUNT  --mgmt-account                    -- ""
  param   MGMT_PROFILE   --mgmt-profile                    -- "[required] A profile for Your Management Account."
  param   AUDIT_PROFILE  --audit-profile                   -- "[required] A profile for Your Audit Account."
  param   ENABLED_REGIONS --enabled-regions                -- "[required] The Region(s) allowed by Control Tower."
  param   REGION        -r --region init:="ap-northeast-1" -- "The region to use. Overrides config/env settings."
  disp    :usage        -h --help
}

eval "$(getoptions parser_definition) exit 1"

if [ -z ${AUDIT_ACCOUNT} ] || [ -z ${MGMT_PROFILE} ] || [ -z ${AUDIT_PROFILE} ] || [ -z ${ENABLED_REGIONS} ]; then
    usage
    exit 1
fi

MGMT_PROFILE="--profile ${MGMT_PROFILE}"
AUDIT_PROFILE="--profile ${AUDIT_PROFILE}"

# [NOTE] マネージメントアカウントの有効なリージョン全てから、監査アカウントへSecurityHubの管理を移譲する
REGIONS=($(aws account list-regions --output text --query 'Regions|[?RegionOptStatus!=`DISABLED`].RegionName' --region ${REGION} ${MGMT_PROFILE}))
for r in ${REGIONS[*]}; do
    echo "========== ${r} =========="
    admin=$(aws securityhub list-organization-admin-accounts \
                --output text \
                --query "AdminAccounts[0].AccountId" \
                --region ${r} ${MGMT_PROFILE})

    if [ "None" = "${admin}" ]; then
        echo 'enable organization admin now'
        aws securityhub enable-organization-admin-account \
            --admin-account-id ${AUDIT_ACCOUNT} \
            --region ${r} ${MGMT_PROFILE}
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

# [NOTE] 監査アカウントにて、マネージメントアカウントを含む組織内の有効なAWSアカウント x 有効なリージョン（ユーザー入力に依存）全てでSecurityHubを有効化する
ACCOUNT_LIST=$(aws organizations list-accounts \
               --output json \
               --query 'Accounts|[?(Status==`ACTIVE`&&Id!=`"'${AUDIT_ACCOUNT}'"`)].{AccountId: Id}' \
               --region ${REGION} ${MGMT_PROFILE})

# [NOTE] 検出結果の集約を設定する
result=$(aws securityhub list-finding-aggregators \
             --output text \
             --query 'FindingAggregators[0]' \
             --region ${REGION} ${MGMT_PROFILE})

if [ "${result}" = "None" ]; then
    echo "create finding aggregator: ${REGION}"
    aws securityhub create-finding-aggregator \
        --region-linking-mode ALL_REGIONS \
        --region ${REGION} ${AUDIT_PROFILE} > /dev/null
else
    echo 'finding aggregator already exists.'
fi
echo ''

for r in ${ENABLED_REGIONS//,/ }; do
    echo "========== ${r} =========="
    # 追加アカウントのauto-enable / auto-enable-standards
    aws securityhub update-organization-configuration \
        --auto-enable \
        --auto-enable-standards DEFAULT \
        --region ${r} ${AUDIT_PROFILE} > /dev/null

    # 既存アカウントの追加
    aws securityhub create-members \
        --account-details "${ACCOUNT_LIST}" \
        --region ${r} ${AUDIT_PROFILE} > /dev/null

    # [NOTE] 統合されたコントロールの検出結果を有効化するWebAPIは公開されていない
    echo "NEST STEP: 監査アカウントのWebコンソールから、[統合されたコントロールの検出結果]を有効にする"
    echo "https://${r}.console.aws.amazon.com/securityhub/home?region=${r}#/settings/general"

    echo ''
done

echo 'done'

