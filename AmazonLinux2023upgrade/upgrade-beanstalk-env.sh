#!/bin/bash

# Elastic Beanstalk Environment Upgrade Script
# This script captures configuration from an existing environment and creates a new one with upgraded platform

set -e

# Configuration
SOURCE_ENV_NAME="${1}"
NEW_ENV_NAME="${2}"
APP_BUNDLE="${3}"
PHP_VERSION="${4:-8.2}"

if [ -z "$SOURCE_ENV_NAME" ] || [ -z "$NEW_ENV_NAME" ] || [ -z "$APP_BUNDLE" ]; then
    echo "Usage: $0 <source-env-name> <new-env-name> <app-bundle-s3-path> [php-version]"
    echo "Example: $0 redcap-prod redcap-prod-al2023 s3://bucket/app.zip 8.3"
    echo "Supported PHP versions: 8.2, 8.3, 8.4, 8.5 (default: 8.2)"
    exit 1
fi

# Validate PHP version
if [[ ! "$PHP_VERSION" =~ ^8\.[2-5]$ ]]; then
    echo "Error: Invalid PHP version '$PHP_VERSION'. Supported: 8.2, 8.3, 8.4, 8.5"
    exit 1
fi

echo "=== Capturing configuration from: $SOURCE_ENV_NAME ==="

# Get environment details
ENV_INFO=$(aws elasticbeanstalk describe-environments --environment-names "$SOURCE_ENV_NAME" --query 'Environments[0]')
APP_NAME=$(echo "$ENV_INFO" | jq -r '.ApplicationName')

# Validate source environment exists
if [ "$APP_NAME" == "null" ] || [ -z "$APP_NAME" ]; then
    echo "Error: Environment '$SOURCE_ENV_NAME' not found"
    exit 1
fi

# Find matching solution stack for PHP version
SOLUTION_STACK=$(aws elasticbeanstalk list-available-solution-stacks \
    --query "SolutionStacks[?contains(@, 'Amazon Linux 2023') && contains(@, 'PHP $PHP_VERSION')] | [0]" --output text)

if [ "$SOLUTION_STACK" == "None" ] || [ -z "$SOLUTION_STACK" ]; then
    echo "Error: No solution stack found for PHP $PHP_VERSION on Amazon Linux 2023"
    echo "Available PHP versions:"
    aws elasticbeanstalk list-available-solution-stacks \
        --query "SolutionStacks[?contains(@, 'Amazon Linux 2023') && contains(@, 'PHP')]" --output text | grep -oP 'PHP \K[0-9.]+' | sort -u
    exit 1
fi

echo "Application: $APP_NAME"
echo "Target PHP Version: $PHP_VERSION"
echo "Solution Stack: $SOLUTION_STACK"

# Get configuration settings
CONFIG=$(aws elasticbeanstalk describe-configuration-settings \
    --application-name "$APP_NAME" \
    --environment-name "$SOURCE_ENV_NAME" \
    --query 'ConfigurationSettings[0].OptionSettings')

# Extract key settings
VPC_ID=$(echo "$CONFIG" | jq -r '.[] | select(.Namespace=="aws:ec2:vpc" and .OptionName=="VPCId") | .Value')
SUBNETS=$(echo "$CONFIG" | jq -r '.[] | select(.Namespace=="aws:ec2:vpc" and .OptionName=="Subnets") | .Value')
ELB_SUBNETS=$(echo "$CONFIG" | jq -r '.[] | select(.Namespace=="aws:ec2:vpc" and .OptionName=="ELBSubnets") | .Value')
SECURITY_GROUPS=$(echo "$CONFIG" | jq -r '.[] | select(.Namespace=="aws:autoscaling:launchconfiguration" and .OptionName=="SecurityGroups") | .Value')
IAM_INSTANCE_PROFILE=$(echo "$CONFIG" | jq -r '.[] | select(.Namespace=="aws:autoscaling:launchconfiguration" and .OptionName=="IamInstanceProfile") | .Value')
SERVICE_ROLE=$(echo "$CONFIG" | jq -r '.[] | select(.Namespace=="aws:elasticbeanstalk:environment" and .OptionName=="ServiceRole") | .Value')
INSTANCE_TYPE=$(echo "$CONFIG" | jq -r '.[] | select(.Namespace=="aws:autoscaling:launchconfiguration" and .OptionName=="InstanceType") | .Value')
KEY_NAME=$(echo "$CONFIG" | jq -r '.[] | select(.Namespace=="aws:autoscaling:launchconfiguration" and .OptionName=="EC2KeyName") | .Value')

echo ""
echo "=== Captured Configuration ==="
echo "VPC: $VPC_ID"
echo "Subnets: $SUBNETS"
echo "ELB Subnets: $ELB_SUBNETS"
echo "Security Groups: $SECURITY_GROUPS"
echo "IAM Instance Profile: $IAM_INSTANCE_PROFILE"
echo "Service Role: $SERVICE_ROLE"
echo "Instance Type: $INSTANCE_TYPE"
echo "Key Name: $KEY_NAME"

# Save full config to file
echo "$CONFIG" > "${SOURCE_ENV_NAME}-config.json"
echo "Full configuration saved to: ${SOURCE_ENV_NAME}-config.json"

# Download and modify application bundle
echo ""
echo "=== Modifying application bundle ==="
WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

if [[ "$APP_BUNDLE" =~ ^s3:// ]]; then
    BUNDLE_FILE="$WORK_DIR/original.zip"
    aws s3 cp "$APP_BUNDLE" "$BUNDLE_FILE"
else
    BUNDLE_FILE="$APP_BUNDLE"
fi

cd "$WORK_DIR"
unzip -q "$BUNDLE_FILE" -d extracted
cd extracted

# Find and modify 99redcap_config.sh
CONFIG_SCRIPT=$(find . -name "99redcap_config.sh" -type f)
if [ -n "$CONFIG_SCRIPT" ]; then
    echo "Found: $CONFIG_SCRIPT"
    sed -i.bak 's/yum install -y php-ldap sendmail-cf/dnf install -y php-ldap sendmail-cf postfix/' "$CONFIG_SCRIPT"
    echo "Updated yum to dnf and added postfix package"
    rm -f "${CONFIG_SCRIPT}.bak"
else
    echo "Warning: 99redcap_config.sh not found in bundle"
fi

# Repackage bundle
MODIFIED_BUNDLE="$WORK_DIR/modified.zip"
cd "$WORK_DIR/extracted"
zip -qr "$MODIFIED_BUNDLE" .
echo "Modified bundle created"

# Upload modified bundle
BUCKET=$(aws elasticbeanstalk describe-application-versions \
    --application-name "$APP_NAME" \
    --query 'ApplicationVersions[0].SourceBundle.S3Bucket' --output text)
VERSION_LABEL="${NEW_ENV_NAME}-$(date +%Y%m%d-%H%M%S)"
aws s3 cp "$MODIFIED_BUNDLE" "s3://${BUCKET}/${VERSION_LABEL}.zip"
echo "Uploaded modified bundle to s3://${BUCKET}/${VERSION_LABEL}.zip"

# Create application version
echo ""
echo "=== Creating application version: $VERSION_LABEL ==="
aws elasticbeanstalk create-application-version \
    --application-name "$APP_NAME" \
    --version-label "$VERSION_LABEL" \
    --source-bundle S3Bucket="$BUCKET",S3Key="${VERSION_LABEL}.zip"

# Build option settings
OPTION_SETTINGS="[
    {\"Namespace\":\"aws:ec2:vpc\",\"OptionName\":\"VPCId\",\"Value\":\"$VPC_ID\"},
    {\"Namespace\":\"aws:ec2:vpc\",\"OptionName\":\"Subnets\",\"Value\":\"$SUBNETS\"},
    {\"Namespace\":\"aws:ec2:vpc\",\"OptionName\":\"ELBSubnets\",\"Value\":\"$ELB_SUBNETS\"},
    {\"Namespace\":\"aws:autoscaling:launchconfiguration\",\"OptionName\":\"SecurityGroups\",\"Value\":\"$SECURITY_GROUPS\"},
    {\"Namespace\":\"aws:autoscaling:launchconfiguration\",\"OptionName\":\"IamInstanceProfile\",\"Value\":\"$IAM_INSTANCE_PROFILE\"},
    {\"Namespace\":\"aws:elasticbeanstalk:environment\",\"OptionName\":\"ServiceRole\",\"Value\":\"$SERVICE_ROLE\"},
    {\"Namespace\":\"aws:autoscaling:launchconfiguration\",\"OptionName\":\"InstanceType\",\"Value\":\"$INSTANCE_TYPE\"},
    {\"Namespace\":\"aws:elasticbeanstalk:container:php:phpini\",\"OptionName\":\"document_root\",\"Value\":\"/redcap\"}
]"

if [ "$KEY_NAME" != "null" ] && [ -n "$KEY_NAME" ]; then
    OPTION_SETTINGS=$(echo "$OPTION_SETTINGS" | jq ". += [{\"Namespace\":\"aws:autoscaling:launchconfiguration\",\"OptionName\":\"EC2KeyName\",\"Value\":\"$KEY_NAME\"}]")
fi

# Create new environment
echo ""
echo "=== Creating new environment: $NEW_ENV_NAME ==="
aws elasticbeanstalk create-environment \
    --application-name "$APP_NAME" \
    --environment-name "$NEW_ENV_NAME" \
    --solution-stack-name "$SOLUTION_STACK" \
    --version-label "$VERSION_LABEL" \
    --option-settings "$OPTION_SETTINGS"

echo ""
echo "=== Environment creation initiated ==="
echo "Monitor progress: aws elasticbeanstalk describe-environments --environment-names $NEW_ENV_NAME"
echo "Or visit: https://console.aws.amazon.com/elasticbeanstalk"
