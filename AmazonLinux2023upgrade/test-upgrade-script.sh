#!/bin/bash

# Test script for upgrade-beanstalk-env.sh
# This validates the script logic without creating actual resources

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPGRADE_SCRIPT="$SCRIPT_DIR/upgrade-beanstalk-env.sh"

echo "=== Testing upgrade-beanstalk-env.sh ==="
echo ""

# Test 1: No arguments
echo "Test 1: No arguments (should fail)"
if $UPGRADE_SCRIPT 2>&1 | grep -q "Usage:"; then
    echo "✓ PASS: Shows usage when no arguments provided"
else
    echo "✗ FAIL: Should show usage"
    exit 1
fi
echo ""

# Test 2: Invalid PHP version
echo "Test 2: Invalid PHP version (should fail)"
if $UPGRADE_SCRIPT test-env new-env s3://bucket/app.zip 7.4 2>&1 | grep -q "Invalid PHP version"; then
    echo "✓ PASS: Rejects invalid PHP version"
else
    echo "✗ FAIL: Should reject PHP 7.4"
    exit 1
fi
echo ""

# Test 3: Valid PHP versions
echo "Test 3: Valid PHP versions"
for version in 8.2 8.3 8.4 8.5; do
    # Check if AWS CLI is available
    if ! command -v aws &> /dev/null; then
        echo "⚠ SKIP: AWS CLI not installed, cannot test version $version"
        continue
    fi
    
    # Test that the script accepts the version (will fail at AWS call, but that's expected)
    if $UPGRADE_SCRIPT test-env new-env s3://bucket/app.zip $version 2>&1 | grep -q "Invalid PHP version"; then
        echo "✗ FAIL: Should accept PHP $version"
        exit 1
    else
        echo "✓ PASS: Accepts PHP $version"
    fi
done
echo ""

# Test 4: Check jq dependency
echo "Test 4: Check dependencies"
if command -v jq &> /dev/null; then
    echo "✓ PASS: jq is installed"
else
    echo "✗ FAIL: jq is required but not installed"
    echo "  Install with: brew install jq (macOS) or apt-get install jq (Linux)"
    exit 1
fi
echo ""

# Test 5: Check AWS CLI
echo "Test 5: Check AWS CLI"
if command -v aws &> /dev/null; then
    echo "✓ PASS: AWS CLI is installed"
    AWS_VERSION=$(aws --version 2>&1)
    echo "  Version: $AWS_VERSION"
else
    echo "✗ FAIL: AWS CLI is required but not installed"
    exit 1
fi
echo ""

# Test 6: Validate script syntax
echo "Test 6: Validate script syntax"
if bash -n "$UPGRADE_SCRIPT"; then
    echo "✓ PASS: Script syntax is valid"
else
    echo "✗ FAIL: Script has syntax errors"
    exit 1
fi
echo ""

# Test 7: Check AWS credentials (optional)
echo "Test 7: Check AWS credentials"
if aws sts get-caller-identity &> /dev/null; then
    echo "✓ PASS: AWS credentials are configured"
    IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
    echo "  Identity: $IDENTITY"
else
    echo "⚠ WARNING: AWS credentials not configured or invalid"
    echo "  Configure with: aws configure"
fi
echo ""

# Test 8: Test solution stack query (if AWS is configured)
echo "Test 8: Test solution stack availability"
if command -v aws &> /dev/null && aws sts get-caller-identity &> /dev/null; then
    for version in 8.2 8.3; do
        STACK=$(aws elasticbeanstalk list-available-solution-stacks \
            --query "SolutionStacks[?contains(@, 'Amazon Linux 2023') && contains(@, 'PHP $version')] | [0]" -o text 2>/dev/null || echo "")
        
        if [ -n "$STACK" ] && [ "$STACK" != "None" ]; then
            echo "✓ PASS: Found solution stack for PHP $version"
            echo "  Stack: $STACK"
        else
            echo "⚠ WARNING: No solution stack found for PHP $version"
        fi
    done
else
    echo "⚠ SKIP: AWS not configured, cannot test solution stacks"
fi
echo ""

echo "=== Test Summary ==="
echo "All critical tests passed!"
echo ""
echo "To run the actual upgrade script:"
echo "  $UPGRADE_SCRIPT <source-env> <new-env> <bundle-path> [php-version]"
echo ""
echo "Example:"
echo "  $UPGRADE_SCRIPT redcap-prod redcap-prod-al2023 s3://my-bucket/app.zip 8.3"
