#!/usr/bin/env bash
###############################################################################
# reimport.sh — Reconstruir el state de aws-email/ vía terraform import
#
# Contexto: el state local original se perdió cuando se eliminó con --force el
# git worktree donde se ejecutó el primer `terraform apply`. La infra AWS está
# 100% viva. Este script importa cada recurso al nuevo backend S3 vacío.
#
# Es idempotente: si un recurso ya está en el state, terraform import devuelve
# error que el script ignora ("Resource already managed by Terraform").
#
# Requisitos: AWS CLI logueado como adianny en account 372370374261.
###############################################################################

set -uo pipefail

cd "$(dirname "$0")"

VARS=(-var='admin_cognito_users=["adianny@me.com"]' -var='budget_alert_email=adianny@me.com')

LOG="reimport.log"
: > "$LOG"

PASS=0
FAIL=0
SKIP=0

import() {
  local addr="$1"
  local id="$2"
  echo "----- $addr  <-  $id" | tee -a "$LOG"
  if terraform state show "$addr" >/dev/null 2>&1; then
    echo "  [SKIP] ya en state" | tee -a "$LOG"
    SKIP=$((SKIP+1))
    return 0
  fi
  if terraform import "${VARS[@]}" "$addr" "$id" >>"$LOG" 2>&1; then
    echo "  [OK]" | tee -a "$LOG"
    PASS=$((PASS+1))
  else
    echo "  [FAIL]" | tee -a "$LOG"
    FAIL=$((FAIL+1))
  fi
}

###############################################################################
# IDs estáticos / descubiertos
###############################################################################

ACCT=372370374261
REGION=eu-west-1
ZONE=Z06668016LU3R26NZSQH
ROOT=bubabeautystudio.com
ADMIN_FQDN=admin.bubabeautystudio.com
MAIL_FROM=mail.bubabeautystudio.com
API_ID=81mmdkibg8

# Discover dynamic IDs (some AWS-side, fail loudly if missing)
KMS_KEY_ID=$(aws kms list-aliases --region "$REGION" \
  --query 'Aliases[?AliasName==`alias/buba-prod`].TargetKeyId' --output text)
ACM_ARN=$(aws acm list-certificates --region us-east-1 \
  --query 'CertificateSummaryList[?DomainName==`'"$ADMIN_FQDN"'`].CertificateArn' --output text)
RHP_ID=$(aws cloudfront list-response-headers-policies --type custom \
  --query 'ResponseHeadersPolicyList.Items[?ResponseHeadersPolicy.ResponseHeadersPolicyConfig.Name==`buba-prod-admin-security`].ResponseHeadersPolicy.Id' \
  --output text)
COGNITO_USER_SUB=$(aws cognito-idp list-users --user-pool-id eu-west-1_SHRKcryaZ \
  --region "$REGION" --query 'Users[0].Username' --output text)

# IAM Role names (mapped via Lambda → role)
ROLE_SUBSCRIBE=buba-prod-sub-20260419031537167600000004
ROLE_CONFIRM=buba-prod-cnf-20260419031537167700000005
ROLE_UNSUBSCRIBE=buba-prod-uns-20260419031537721900000006
ROLE_BOUNCE=buba-prod-bnc-20260419031537167500000001
ROLE_CAMPAIGN=buba-prod-cmp-20260419031537167600000003
ROLE_ADMIN_READ=buba-prod-adr-20260419031537167500000002

# Inline policy names (autoincremented por TF, descubiertos vía AWS CLI)
POLICY_SUBSCRIBE=terraform-20260419031604012700000010
POLICY_CONFIRM=terraform-2026041903160352710000000f
POLICY_UNSUBSCRIBE=terraform-20260419031550746000000007
POLICY_BOUNCE=terraform-2026041903160305360000000e
POLICY_CAMPAIGN=terraform-20260419031625927900000012
POLICY_ADMIN_READ=terraform-20260419031625927900000013

# APIGW children
ROUTE_SUBSCRIBE=hwrgj0d
ROUTE_CONFIRM=u5mqpdt
ROUTE_UNSUBSCRIBE=ki5jiyu
ROUTE_SEND_CAMPAIGN=cn0r5ei
ROUTE_ADMIN_CAMPAIGNS_LIST=oy4lkc9
ROUTE_ADMIN_AUDIENCE_COUNT=91785qg
INT_SUBSCRIBE=s56moi6
INT_CONFIRM=i55m4cp
INT_UNSUBSCRIBE=wjhjayf
INT_SEND_CAMPAIGN=iu99czs
INT_ADMIN_READ=crq8ndt
AUTHZ_COGNITO=47mrot

# SNS subscription ARNs
SUB_BOUNCES=arn:aws:sns:$REGION:$ACCT:buba-prod-ses-bounces:c700624f-d3ce-42a9-8949-6ed77cef4fd8
SUB_COMPLAINTS=arn:aws:sns:$REGION:$ACCT:buba-prod-ses-complaints:ab36c4c7-49b4-4e41-987e-ace0bfdc7ee7

# DKIM tokens (en el orden retornado por SES, mismo orden que count.index)
DKIM_T0=ddoms5vzjtfktksd235fbqsgc3zsjlan
DKIM_T1=tjrztxndw5yio6aqds2hwoeucgtfwrqf
DKIM_T2=trfjxu2cj2dqz2l4g4t27wlpjysdpdkq

# ACM validation CNAME (single domain)
ACM_VAL_NAME=_9b345b44701dd34eb303b750254ca863.admin.bubabeautystudio.com

###############################################################################
# IMPORTS
###############################################################################

# random_string
import 'random_string.cognito_domain_suffix' '0nry6h'

# KMS
import 'aws_kms_key.main' "$KMS_KEY_ID"
import 'aws_kms_alias.main' 'alias/buba-prod'

# SES
import 'aws_sesv2_email_identity.domain' "$ROOT"
import 'aws_sesv2_email_identity_mail_from_attributes.domain' "$ROOT"
import 'aws_sesv2_configuration_set.main' 'buba-prod-main'
import 'aws_sesv2_configuration_set_event_destination.sns_bounces'    'buba-prod-main|sns-bounces'
import 'aws_sesv2_configuration_set_event_destination.sns_complaints' 'buba-prod-main|sns-complaints'
import 'aws_sesv2_configuration_set_event_destination.cw_metrics'     'buba-prod-main|cw-metrics'
import 'aws_sesv2_contact_list.main' 'buba-prod-marketing'

# SNS
import 'aws_sns_topic.ses_bounces'         "arn:aws:sns:$REGION:$ACCT:buba-prod-ses-bounces"
import 'aws_sns_topic.ses_complaints'      "arn:aws:sns:$REGION:$ACCT:buba-prod-ses-complaints"
import 'aws_sns_topic_policy.ses_bounces'  "arn:aws:sns:$REGION:$ACCT:buba-prod-ses-bounces"
import 'aws_sns_topic_policy.ses_complaints' "arn:aws:sns:$REGION:$ACCT:buba-prod-ses-complaints"
import 'aws_sns_topic_subscription.bounces'    "$SUB_BOUNCES"
import 'aws_sns_topic_subscription.complaints' "$SUB_COMPLAINTS"

# DynamoDB
import 'aws_dynamodb_table.subscribe_tokens' 'buba-prod-subscribe-tokens'
import 'aws_dynamodb_table.campaigns'        'buba-prod-campaigns'
import 'aws_dynamodb_table.sends_log'        'buba-prod-sends-log'

# IAM Roles
import 'aws_iam_role.lambda_subscribe'   "$ROLE_SUBSCRIBE"
import 'aws_iam_role.lambda_confirm'     "$ROLE_CONFIRM"
import 'aws_iam_role.lambda_unsubscribe' "$ROLE_UNSUBSCRIBE"
import 'aws_iam_role.lambda_bounce'      "$ROLE_BOUNCE"
import 'aws_iam_role.lambda_campaign'    "$ROLE_CAMPAIGN"
import 'aws_iam_role.lambda_admin_read'  "$ROLE_ADMIN_READ"

# IAM Inline Policies (format role:policy)
import 'aws_iam_role_policy.subscribe'   "$ROLE_SUBSCRIBE:$POLICY_SUBSCRIBE"
import 'aws_iam_role_policy.confirm'     "$ROLE_CONFIRM:$POLICY_CONFIRM"
import 'aws_iam_role_policy.unsubscribe' "$ROLE_UNSUBSCRIBE:$POLICY_UNSUBSCRIBE"
import 'aws_iam_role_policy.bounce'      "$ROLE_BOUNCE:$POLICY_BOUNCE"
import 'aws_iam_role_policy.campaign'    "$ROLE_CAMPAIGN:$POLICY_CAMPAIGN"
import 'aws_iam_role_policy.admin_read'  "$ROLE_ADMIN_READ:$POLICY_ADMIN_READ"

# IAM Role Policy Attachments (format role/policy_arn)
BASIC_EXEC_ARN=arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
import 'aws_iam_role_policy_attachment.basic_exec["subscribe"]'   "$ROLE_SUBSCRIBE/$BASIC_EXEC_ARN"
import 'aws_iam_role_policy_attachment.basic_exec["confirm"]'     "$ROLE_CONFIRM/$BASIC_EXEC_ARN"
import 'aws_iam_role_policy_attachment.basic_exec["unsubscribe"]' "$ROLE_UNSUBSCRIBE/$BASIC_EXEC_ARN"
import 'aws_iam_role_policy_attachment.basic_exec["bounce"]'      "$ROLE_BOUNCE/$BASIC_EXEC_ARN"
import 'aws_iam_role_policy_attachment.basic_exec["campaign"]'    "$ROLE_CAMPAIGN/$BASIC_EXEC_ARN"
import 'aws_iam_role_policy_attachment.admin_read_basic_exec'     "$ROLE_ADMIN_READ/$BASIC_EXEC_ARN"

# Lambda Functions
import 'aws_lambda_function.subscribe'                'buba-prod-subscribe'
import 'aws_lambda_function.confirm'                  'buba-prod-confirm'
import 'aws_lambda_function.unsubscribe'              'buba-prod-unsubscribe'
import 'aws_lambda_function.bounce_complaint_handler' 'buba-prod-bounce-complaint'
import 'aws_lambda_function.send_campaign'            'buba-prod-send-campaign'
import 'aws_lambda_function.admin_read'               'buba-prod-admin-read'

# Lambda Permissions (format function-name/statement-id)
import 'aws_lambda_permission.api_subscribe'   'buba-prod-subscribe/AllowAPIInvokeSubscribe'
import 'aws_lambda_permission.api_confirm'     'buba-prod-confirm/AllowAPIInvokeConfirm'
import 'aws_lambda_permission.api_unsubscribe' 'buba-prod-unsubscribe/AllowAPIInvokeUnsubscribe'
import 'aws_lambda_permission.api_campaign'    'buba-prod-send-campaign/AllowAPIInvokeCampaign'
import 'aws_lambda_permission.api_admin_read'  'buba-prod-admin-read/AllowAPIInvokeAdminRead'
import 'aws_lambda_permission.sns_bounces'     'buba-prod-bounce-complaint/AllowSNSInvokeBounces'
import 'aws_lambda_permission.sns_complaints'  'buba-prod-bounce-complaint/AllowSNSInvokeComplaints'

# CloudWatch Log Groups
import 'aws_cloudwatch_log_group.subscribe'   '/aws/lambda/buba-prod-subscribe'
import 'aws_cloudwatch_log_group.confirm'     '/aws/lambda/buba-prod-confirm'
import 'aws_cloudwatch_log_group.unsubscribe' '/aws/lambda/buba-prod-unsubscribe'
import 'aws_cloudwatch_log_group.bounce'      '/aws/lambda/buba-prod-bounce-complaint'
import 'aws_cloudwatch_log_group.campaign'    '/aws/lambda/buba-prod-send-campaign'
import 'aws_cloudwatch_log_group.admin_read'  '/aws/lambda/buba-prod-admin-read'
import 'aws_cloudwatch_log_group.api'         '/aws/apigateway/buba-prod-api'

# Cognito
import 'aws_cognito_user_pool.admin'        'eu-west-1_SHRKcryaZ'
import 'aws_cognito_user_pool_client.admin' 'eu-west-1_SHRKcryaZ/7344v1aa2bi9vvjldqtu650g6j'
import 'aws_cognito_user_pool_domain.admin' 'buba-prod-admin-0nry6h'
import 'aws_cognito_user.admin["adianny@me.com"]' "eu-west-1_SHRKcryaZ/$COGNITO_USER_SUB"

# API Gateway v2
import 'aws_apigatewayv2_api.main'   "$API_ID"
import 'aws_apigatewayv2_stage.api'  "$API_ID/prod"
import 'aws_apigatewayv2_authorizer.cognito' "$API_ID/$AUTHZ_COGNITO"

import 'aws_apigatewayv2_integration.subscribe'     "$API_ID/$INT_SUBSCRIBE"
import 'aws_apigatewayv2_integration.confirm'       "$API_ID/$INT_CONFIRM"
import 'aws_apigatewayv2_integration.unsubscribe'   "$API_ID/$INT_UNSUBSCRIBE"
import 'aws_apigatewayv2_integration.send_campaign' "$API_ID/$INT_SEND_CAMPAIGN"
import 'aws_apigatewayv2_integration.admin_read'    "$API_ID/$INT_ADMIN_READ"

import 'aws_apigatewayv2_route.subscribe'              "$API_ID/$ROUTE_SUBSCRIBE"
import 'aws_apigatewayv2_route.confirm'                "$API_ID/$ROUTE_CONFIRM"
import 'aws_apigatewayv2_route.unsubscribe'            "$API_ID/$ROUTE_UNSUBSCRIBE"
import 'aws_apigatewayv2_route.send_campaign'          "$API_ID/$ROUTE_SEND_CAMPAIGN"
import 'aws_apigatewayv2_route.admin_campaigns_list'   "$API_ID/$ROUTE_ADMIN_CAMPAIGNS_LIST"
import 'aws_apigatewayv2_route.admin_audience_count'   "$API_ID/$ROUTE_ADMIN_AUDIENCE_COUNT"

# S3 (admin bucket)
import 'aws_s3_bucket.admin'                                   'buba-prod-admin-372370374261'
import 'aws_s3_bucket_ownership_controls.admin'                'buba-prod-admin-372370374261'
import 'aws_s3_bucket_public_access_block.admin'               'buba-prod-admin-372370374261'
import 'aws_s3_bucket_server_side_encryption_configuration.admin' 'buba-prod-admin-372370374261'
import 'aws_s3_bucket_versioning.admin'                        'buba-prod-admin-372370374261'
import 'aws_s3_bucket_policy.admin'                            'buba-prod-admin-372370374261'

# ACM (us-east-1)
import 'aws_acm_certificate.admin'             "$ACM_ARN"
import 'aws_acm_certificate_validation.admin'  "$ACM_ARN"

# CloudFront
import 'aws_cloudfront_origin_access_control.admin'    'E39P63G9EWFPFX'
import 'aws_cloudfront_function.admin_rewrite'         'buba-prod-admin-rewrite'
import 'aws_cloudfront_distribution.admin'             'E2ZSGJELCJFZJI'
import 'aws_cloudfront_response_headers_policy.admin'  "$RHP_ID"

# Route53 records (zone_id_name_type)
import "aws_route53_record.admin"          "${ZONE}_${ADMIN_FQDN}_A"
import "aws_route53_record.admin_ipv6"     "${ZONE}_${ADMIN_FQDN}_AAAA"
import "aws_route53_record.spf"            "${ZONE}_${ROOT}_TXT"
import "aws_route53_record.dmarc"          "${ZONE}__dmarc.${ROOT}_TXT"
import "aws_route53_record.mail_from_mx"   "${ZONE}_${MAIL_FROM}_MX"
import "aws_route53_record.mail_from_spf"  "${ZONE}_${MAIL_FROM}_TXT"
import "aws_route53_record.dkim[0]"        "${ZONE}_${DKIM_T0}._domainkey.${ROOT}_CNAME"
import "aws_route53_record.dkim[1]"        "${ZONE}_${DKIM_T1}._domainkey.${ROOT}_CNAME"
import "aws_route53_record.dkim[2]"        "${ZONE}_${DKIM_T2}._domainkey.${ROOT}_CNAME"
import "aws_route53_record.acm_validation[\"$ADMIN_FQDN\"]" "${ZONE}_${ACM_VAL_NAME}_CNAME"

# Budget
import 'aws_budgets_budget.monthly[0]' "${ACCT}:buba-prod-monthly"

###############################################################################
echo
echo "============================="
echo " IMPORT SUMMARY"
echo " OK:   $PASS"
echo " SKIP: $SKIP"
echo " FAIL: $FAIL"
echo "============================="
