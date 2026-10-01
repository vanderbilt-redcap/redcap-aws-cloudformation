#!/bin/bash
filename=
s3source=

#Staging directory for the upgrade. This deliberately lives on the root volume
#rather than /tmp: on Amazon Linux 2023 /tmp is a tmpfs capped at 50% of RAM,
#which is too small to hold two unpacked REDCap bundles plus the zips.
WORKDIR="/upgrade-files"

usage() {
        cat <<EOF
Build a new Elastic Beanstalk application version from a REDCap release and
deploy it to the Elastic Beanstalk environment this instance belongs to. The
.ebextensions and .platform directories from the currently deployed version are
carried forward into the new bundle so environment customisations are kept.

Usage:
  upgrade-aws-eb.sh --file /path/to/redcapX.Y.Z.zip
  upgrade-aws-eb.sh --s3 s3://my-bucket/path/redcapX.Y.Z.zip

Options:
  -f, --file <path>   REDCap release zip already present on this instance
  -s, --s3 <uri>      REDCap release zip stored in S3, as s3://bucket/key
  -h, --help          Show this message

Exactly one of --file or --s3 is required.

Run this with sudo. Files are staged in $WORKDIR on the root volume.
EOF
}

while [ "$1" != "" ]; do
    case $1 in
        -f | --file )           shift
                                filename=$1
                                ;;
        -s | --s3 )             shift
                                s3source=$1
                                ;;
        -h | --help )           usage
                                exit
                                ;;
        * )                     usage
                                exit 1
    esac
    shift
done

#Exactly one source is required
if [ -n "$filename" ] && [ -n "$s3source" ]; then
        echo "Specify either --file or --s3, not both."
        exit 1
fi

if [ -z "$filename" ] && [ -z "$s3source" ]; then
        echo "No REDCap release specified."
        echo
        usage
        exit 1
fi

#Validate the chosen source before doing any work, and work out the name that
#will be used for the new application version
if [ -n "$filename" ]; then
        if [ ! -f "$filename" ]; then
                echo "The file you specified does not exist: $filename"
                exit 1
        fi
        file=$(basename "$filename")
else
        case "$s3source" in
                s3://*/?*) : ;;
                * )     echo "The S3 source must be in the form s3://bucket/key: $s3source"
                        exit 1 ;;
        esac
        file=$(basename "$s3source")
        echo "Checking the S3 source object: $s3source"
        if ! aws s3 ls "$s3source" > /dev/null 2>&1; then
                echo "Cannot read the S3 source object: $s3source"
                echo "Check the URI, and that this instance's IAM role is allowed to read it."
                exit 1
        fi
fi

#The staging area needs room for both bundles unpacked (~200 MB each) plus the
#three zip files (~50 MB each). Fail early and clearly instead of part way
#through an unzip, which would leave a truncated bundle to be deployed.
REQUIRED_KB=2097152
AVAILABLE_KB=$(df -Pk / | awk 'NR==2 {print $4}')
if [ "$AVAILABLE_KB" -lt "$REQUIRED_KB" ]; then
        echo "Not enough free space on / to stage the upgrade in $WORKDIR"
        echo "Required: 2 GB    Available: $((AVAILABLE_KB / 1024)) MB"
        echo "Free up space on the root volume, or grow it, then run this script again."
        exit 1
fi

mkdir -p "$WORKDIR"
chmod 700 "$WORKDIR"

        TOKEN=$(curl --request PUT "http://169.254.169.254/latest/api/token" --header "X-aws-ec2-metadata-token-ttl-seconds: 3600")
        INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id --header "X-aws-ec2-metadata-token: $TOKEN")
        echo "INSTANCE_ID = $INSTANCE_ID"
        REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region --header "X-aws-ec2-metadata-token: $TOKEN")
        echo "REGION = $REGION"
        TAG="elasticbeanstalk:environment-name"
        echo "TAG = $TAG"
        ENVIRONMENT_NAME=$(/opt/elasticbeanstalk/bin/get-config container -k environment_name)
        echo "ENVIRONMENT_NAME = $ENVIRONMENT_NAME"
        APPLICATION_NAME=$(aws elasticbeanstalk describe-environments --region $REGION --environment-names $ENVIRONMENT_NAME --query 'Environments[0].ApplicationName' --output text)
        echo "APPLICATION_NAME = $APPLICATION_NAME"
        VERSION_LABEL=$(aws elasticbeanstalk describe-environments --region $REGION --environment-names $ENVIRONMENT_NAME --query 'Environments[0].VersionLabel' --output text)
        echo "VERSION_LABEL = $VERSION_LABEL"
        S3_BUCKET=$(aws elasticbeanstalk describe-application-versions --region $REGION --application-name $APPLICATION_NAME --version-labels "$VERSION_LABEL" --query 'ApplicationVersions[0].SourceBundle.S3Bucket' --output text)
        echo "S3_BUCKET = $S3_BUCKET"
        S3_KEY=$(aws elasticbeanstalk describe-application-versions --region $REGION --application-name $APPLICATION_NAME --version-labels "$VERSION_LABEL" --query 'ApplicationVersions[0].SourceBundle.S3Key' --output text)
        echo "S3_KEY = $S3_KEY"
        echo "NEW_VERSION_LABEL = eb-$file"

        #Fixed staging filenames, so the source can never collide with the name
        #of the currently deployed bundle
        CURRENT_BUNDLE="$WORKDIR/current-bundle.zip"
        NEW_BUNDLE="$WORKDIR/new-bundle.zip"
        BUILT_BUNDLE="$WORKDIR/eb-$file"

        aws s3 cp "s3://$S3_BUCKET/$S3_KEY" "$CURRENT_BUNDLE" || { echo "Failed to download the currently deployed bundle. Aborting."; exit 1; }

        if [ -n "$filename" ]; then
                cp "$filename" "$NEW_BUNDLE" || { echo "Failed to stage $filename. Aborting."; exit 1; }
        else
                aws s3 cp "$s3source" "$NEW_BUNDLE" || { echo "Failed to download $s3source. Aborting."; exit 1; }
        fi

        rm -Rf "$WORKDIR/redcap-current"
        rm -Rf "$WORKDIR/redcap-next"

        unzip "$CURRENT_BUNDLE" -d "$WORKDIR/redcap-current" || { echo "Failed to unpack the current bundle. Aborting before anything is deployed."; exit 1; }
        unzip "$NEW_BUNDLE" -d "$WORKDIR/redcap-next" || { echo "Failed to unpack the new REDCap release. Aborting before anything is deployed."; exit 1; }
        chmod -R +r "$WORKDIR/redcap-current/.ebextensions/"
        chmod -R +r "$WORKDIR/redcap-current/.platform/"

        cp -a "$WORKDIR/redcap-current/.ebextensions" "$WORKDIR/redcap-next/"
        cp -a "$WORKDIR/redcap-current/.platform" "$WORKDIR/redcap-next/"
        cd "$WORKDIR/redcap-next"
        #Write the archive outside redcap-next so it is not nested inside the
        #directory being zipped
        zip -r "$BUILT_BUNDLE" . || { echo "Failed to build the deployment bundle. Aborting before anything is deployed."; exit 1; }
        aws s3 cp "$BUILT_BUNDLE" s3://$S3_BUCKET/
        
        aws elasticbeanstalk create-application-version --region $REGION --application-name $APPLICATION_NAME --version-label eb-$file --source-bundle S3Bucket=$S3_BUCKET,S3Key=eb-$file
        aws elasticbeanstalk update-environment --region $REGION --environment-name $ENVIRONMENT_NAME --version-label eb-$file
        cd /
        rm -Rf "$WORKDIR/redcap-current"
        rm -Rf "$WORKDIR/redcap-next"
        rm -f "$CURRENT_BUNDLE"
        rm -f "$NEW_BUNDLE"
        rm -f "$BUILT_BUNDLE"
