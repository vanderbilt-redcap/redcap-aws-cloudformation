#!/bin/bash
filename=

while [ "$1" != "" ]; do
    case $1 in
        -f | --file )           shift
                                filename=$1
                                ;;
        -h | --help )           echo "Usage: eb-upgrade.sh --file /new/redcap/directory/new_redcap_filename.zip" 
                                exit
                                ;;
        * )                     echo "Usage: eb-upgrade.sh --file /new/redcap/directory/new_redcap_filename.zip" 
                                exit 1
    esac
    shift
done

if [ ! -f $filename ]; then
        echo "The file you specified does not exist: $filename"
        exit 1
fi

        INSTANCE_ID=$(/opt/aws/bin/ec2-metadata -i | awk '{print $2}')
        echo "INSTANCE_ID = $INSTANCE_ID"
        REGION=$(/opt/aws/bin/ec2-metadata -z | awk '{print substr($2, 0, length($2)-1)}')
        echo "REGION = $REGION"
        TAG="elasticbeanstalk:environment-name"
        echo "TAG = $TAG"
        ENVIRONMENT_NAME=$(aws ec2 describe-tags --output text --filters "Name=resource-id,Values=${INSTANCE_ID}" "Name=key,Values=${TAG}" --region "${REGION}" --query "Tags[*].Value")
        echo "ENVIRONMENT_NAME = $ENVIRONMENT_NAME"
        APPLICATION_NAME=$(aws elasticbeanstalk describe-environments --region $REGION --environment-names $ENVIRONMENT_NAME --query 'Environments[0].ApplicationName' --output text)
        echo "APPLICATION_NAME = $APPLICATION_NAME"
        VERSION_LABEL=$(aws elasticbeanstalk describe-environments --region $REGION --environment-names $ENVIRONMENT_NAME --query 'Environments[0].VersionLabel' --output text)
        echo "VERSION_LABEL = $VERSION_LABEL"
        S3_BUCKET=$(aws elasticbeanstalk describe-application-versions --region $REGION --application-name $APPLICATION_NAME --version-labels "$VERSION_LABEL" --query 'ApplicationVersions[0].SourceBundle.S3Bucket' --output text)
        echo "S3_BUCKET = $S3_BUCKET"
        S3_KEY=$(aws elasticbeanstalk describe-application-versions --region $REGION --application-name $APPLICATION_NAME --version-labels "$VERSION_LABEL" --query 'ApplicationVersions[0].SourceBundle.S3Key' --output text)
        echo "S3_KEY = $S3_KEY"
        file=$(echo $filename | rev | cut -d / -f1 | rev)

        aws s3 cp s3://$S3_BUCKET/$S3_KEY /tmp/

        cp $filename /tmp/

        rm -Rf /tmp/redcap-current
        rm -Rf /tmp/redcap-next

        unzip /tmp/$S3_KEY -d "/tmp/redcap-current"
        unzip /tmp/$file -d "/tmp/redcap-next"
        chmod -R +r /tmp/redcap-current/.ebextensions/
        chmod -R +r /tmp/redcap-current/.platform/

        cp -a /tmp/redcap-current/.ebextensions /tmp/redcap-next/
        cp -a /tmp/redcap-current/.platform /tmp/redcap-next/
        cd /tmp/redcap-next
        zip -r eb-$file .
        aws s3 cp eb-$file s3://$S3_BUCKET/
        
        aws elasticbeanstalk create-application-version --region $REGION --application-name $APPLICATION_NAME --version-label eb-$file --source-bundle S3Bucket=$S3_BUCKET,S3Key=eb-$file
        aws elasticbeanstalk update-environment --region $REGION --environment-name $ENVIRONMENT_NAME --version-label eb-$file
        rm -Rf /tmp/redcap-current
        rm -Rf /tmp/redcap-next
        rm /tmp/$S3_KEY
        rm /tmp/$file
        rm /tmp/eb-$file