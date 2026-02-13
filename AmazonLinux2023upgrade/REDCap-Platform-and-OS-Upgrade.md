# REDCap PHP Platform and OS Upgrade (Manual Process)
## Why is this important?
PHP 8.1 and Amazon Linux 2 are nearing the end of their lifespan. Many deployments of REDCap on AWS were deployed using both of these platforms. In order to remain on Elastic Beanstalk, we do need to upgrade both the Platform (PHP 8.2+) and the OS (Amazon Linux 2023).

The risk of running unsupported platforms is that you will no longer receive any security updates and there is potential for additional compatibility issues.

## How do I upgrade my application?
I am currently working on a programmatic way of performing the updates. However, due to the demand I decided to do this write up (along with scripts) for those that would like explore manually doing the upgrade. The script provided will create a new Beanstalk Environment and the old environment will not be deleted or modified. This will give you the opportunity to verify that everything is working prior to cutting over the DNS.

My goal is to have a automated deployment that will programmatically perform updates, however, this is taking longer than expected.

## Are there any tradeoffs with the manual deployment?
The main tradeoff is that you might need to re-create the Beanstalk environment if\when you decide to go back to the programmatic deploy of the REDCap application. Despite the direction you go, **DO NOT DELETE** the CloudFormation template without modifying the template to retain the database. 

In a scenario where you accidentally delete the Amazon RDS database, a final snapshot is created and you can restore the database from this snapshot. However, this would mean downtime until you restore the database and point the application to the new database (via the database.php).

As an alternative to deleting the old environment, you can scale down the auto scaling group of the Beanstalk app to save cost while you wait for the automated deployment.

## I understand the risks and I would to continue with the manual deployment
Below, I have included steps you can follow to upgrade your environment along with a script to facilitate the creation of a clone of your environment on a newer platform\OS. Keep in mind that this clone will connect to the existing database.

1. Log into the AWS Console - [AWS Console Link](https://console.aws.com)
2. Navigate to the Beantstalk Console - [Amazon Elastic Beanstalk Console](https://console.aws.amazon.com/elasticbeanstalk)
3. Click on the environment name you would like to use 
4. On the left hand menu, click on **Application versions** 
5. Select the zip file under the **Source** column of the currently deployed version
6. You have the option to eith keep this file locally or upload it to Amazon S3 (script supports both options)
7. Download the script and use the following example command as a reference: ./upgrade-beanstalk-env.sh <source-env> <new-env> <bundle-path> [php-version]
8. Navigate back to the Beanstalk console and wait for the environment to become healthy
