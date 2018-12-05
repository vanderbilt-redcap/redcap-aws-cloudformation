# Deploy a REDCap environment on AWS using automation and architectural best practices

## Quick Start

<a href="https://console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks/new?stackName=myredcapstack100&templateURL=https://s3.amazonaws.com/redcap-aws-cloudformation/00-master-rc.yaml" target="_blank"><img src="https://s3.amazonaws.com/cloudformation-examples/cloudformation-launch-stack.png"/></a> 

Click the launch button above to begin the process of deploying a REDCap environment on AWS CloudFormation. NOTE: This launch button already has the *US East* region pre-selected as part of the URL (i.e., &region=us-east-1), but once you click the button, you can change your preferred deployment region in AWS by selecting it from the top bar of the AWS Console, after which you may need to provide the Amazon S3 Template URL (https://s3.amazonaws.com/redcap-aws-cloudformation/00-master-rc.yaml).

## Summary
This repository contains AWS CloudFormation templates to automatically deploy a REDCap environment that adheres to AWS architectural best practices.  In order to use this automation, you must supply your own copy of the REDCap source files.  These are available for qualified entities at https://projectredcap.org.  Once you have downloaded your source files then you can follow the below instructions for deployment.

In their own words: "REDCap is a secure web application for building and managing online surveys and databases. While REDCap can be used to collect virtually any type of data (including 21 CFR Part 11, FISMA, and HIPAA-compliant environments), it is specifically geared to support online or offline data capture for research studies and operations. The REDCap Consortium, a vast support network of collaborators, is composed of thousands of active institutional partners in over one hundred countries who utilize and support REDCap in various ways."

**NOTE: REDCap 8.9.3 or higher is required for using this AWS CloudFormation template.** Earlier versions of REDCap may not install correctly and will not be able to utilize the Easy Upgrade feature.

You must be a REDCap consortium partner in order to utilize this AWS CloudFormation template. But once your institution is a partner, no additional licenses with Vanderbilt are required for running REDCap on AWS.

## REDCap on AWS architecture and features
The features of using this architecture are as follows:
* A complete and ready-to-use REDCap environment is automatically deployed in about 20 minutes.
* REDCap is deployed in an isolated, three-tiered Virtual Private Cloud
* The environment enables automatic scaling up and down based on load
* Data is encrypted by default at rest and in flight (in accordance with HIPAA)
* Managed services are used that provide automated patching and maintenance of OS, middleware, and database software
* Database backups are performed automatically to enable operational and disaster recovery
* [The design results in a reasonable monthly cost](https://calculator.s3.amazonaws.com/index.html#r=IAD&key=calc-42CFC1C0-3356-4A35-8697-0A9567A8EA3B) 

A high-level diagram showing how the different functions of REDCap map to AWS Services is shown below.  
![alt-text](https://github.com/vanderbilt-redcap/redcap-aws-cloudformation/blob/master/images/AWS%20Project%20REDCap%20Block%20Diagram.png "AWS REDCap High-Level Diagram")

Starting from the user, public Internet DNS services are (optionally) provided by **Amazon Route 53**.  This gives you the ability to automatically add a domain to an existing hosted zone in Route 53 (i.e. redcap.example.edu if example.edu is already hosted in Route 53).  In addition, if you are deploying a new domain to Route 53, an SSL certificate can be automatically generated and applied using **AWS Certificate Manager (ACM)**.  This enables HTTPS communication and ensures the data sent from the users is encrypted in-transit (in accordance with HIPAA).  HTTPS communication is also used between the Application Load Balancers and the REDCap servers.

**AWS Elastic Beanstalk** is used to deploy the REDCap application onto Apache/PHP Linux servers.  Elastic Beanstalk is an easy-to-use service for deploying and scaling web applications. It covers everything from capacity provisioning, load balancing, regular OS and middleware updates, autoscaling, and high availability, to application health monitoring. Using a feature of Elastic Beanstalk called ebextensions, the REDCap servers are customized to use an encrypted storage volume for the middleware application logs.

**Amazon Relational Database Service (RDS)** with Amazon Aurora MySQL is used to provide an (optionally) highly available database for REDCap.  Amazon Aurora is a relational database built for the cloud that combines the performance and availability of high-end commercial databases with the simplicity and cost-effectiveness of open-source databases. It provides cost-efficient and resizable capacity while automating time-consuming administration tasks such as hardware provisioning, database setup, patching, and backups. It is configured for high availability and uses encryption at rest for the database and backups, and encryption in flight for the JDBC connections.  The data stored inside this database is also encrypted at rest.

**Amazon Simple Storage Service (S3)** is used as a file repository for files uploaded through REDCap.  S3 is designed to deliver 99.999999999% durability, and stores data for millions of applications used by market leaders in every industry. S3 provides comprehensive security and compliance capabilities that meet even the most stringent regulatory requirements.  The S3 bucket used to store these files is encrypted using AES-256.

**Amazon Simple Email Service (SES)** is used enable REDCap to send emails to users.  SES is a powerful, affordable, and highly-scalable email sending and receiving platform for businesses and developers that integrates seamlessly with applications and with other AWS products.  SES provides a reliable SMTP gateway without the need to maintain a separate SMTP server.

A more detailed, network-oriented diagram of this environment is shown following.
![alt-text](https://github.com/JamesSWiggins/project-redcap-aws-automation/blob/master/images/AWS%20Project%20REDCap%20Network%20Diagram.png "AWS REDCap Network Diagram")

## REDCap on AWS deployment instructions
Before deploying an application on AWS that transmits, processes, or stores protected health information (PHI) or personally identifiable information (PII), address your organization's compliance concerns. Make sure that you have worked with your internal compliance and legal team to ensure compliance with the laws and regulations that govern your organization. To understand how you can use AWS services as a part of your overall compliance program, see the [AWS HIPAA Compliance whitepaper](https://d0.awsstatic.com/whitepapers/compliance/AWS_HIPAA_Compliance_Whitepaper.pdf). With that said, we paid careful attention to the HIPAA control set during the design of this solution.

### Pre-requisite tasks
0.1. Follow the instructions on the [REDCap website](https://projectredcap.org/) to obtain a copy of the REDCap source files.

0.2. [Create a private S3 bucket](https://docs.aws.amazon.com/AmazonS3/latest/user-guide/create-bucket.html) and [upload your REDCap source file](https://docs.aws.amazon.com/AmazonS3/latest/user-guide/upload-objects.html) into it.  Ensure that you do not make either the bucket or the source file publicly readable.  This CloudFormation template also creates two additional S3 buckets, so make sure you aren't near the [limit of your maximum number of buckets](https://docs.aws.amazon.com/AmazonS3/latest/dev/BucketRestrictions.html) (default is 100).

0.3. [Obtain your Amazon SES SMTP Credentials](https://docs.aws.amazon.com/ses/latest/DeveloperGuide/smtp-credentials.html) using the Amazon SES console in the **N. Virginia (us-east-1) Region**.  Download your credentials and store them in a safe place.

0.4. AWS has strict safeguards in place regardng email to prevent inappropriate use.  In order to send outbound email you must [verify the specific email address(es) from which you will be sending mail](https://docs.aws.amazon.com/ses/latest/DeveloperGuide/verify-email-addresses-procedure.html) and/or [verify the domain from which you will be sending mail](https://docs.aws.amazon.com/ses/latest/DeveloperGuide/verify-domain-procedure.html).  In addition, if you intend to send email to an email address or domain other than those you have verified, you must [submit a request to be moved out of the Amazon SES sandbox](https://docs.aws.amazon.com/ses/latest/DeveloperGuide/request-production-access.html).  If these steps are not taken then sending e-mail from your REDCap application will not work properly.

It is also strongly recommended that you implement a [method to handle email bounces and complaints that might occur](https://aws.amazon.com/blogs/messaging-and-targeting/handling-bounces-and-complaints/).

#### If you intend to use Route 53 for DNS or ACM to provide an SSL certificate
0.5. Automatically provisioning and applying an SSL certificate with this CloudFormation template using ACM requires the use of Route 53 for your DNS service.  If you have not already done so, [create a new Route 53 Hosted Zone](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/CreatingHostedZone.html), [transfer registration of an existing domain to Route 53](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/domain-transfer-to-route-53.html), or [transfer just your DNS service to Route 53](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/MigratingDNS.html).

If you do not intend to use Route 53 and ACM to automatically generate and provide an SSL certificate, [an SSL certificate can be applied to your environment after it is deployed](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/configuring-https-elb.html).

### Deployment Instructions
0. This template must be run by an AWS IAM User who has sufficient permission to create the required resources.  These resources include:  VPC, IAM User and Roles, S3 Bucket, EC2 Instance, ALB, Elastic Beanstalk, Route53 entries, and ACM certificates.  If you are not an Administrator of the AWS account you are using, please check with them before running this template to ensure you have sufficient permission.  

1. From your AWS account, [open the CloudFormation Management Console](https://console.aws.amazon.com/cloudformation/) and choose **Create Stack**.  From there, copy and paste the following URL in the **Specify an Amazon S3 template URL**, and choose **Next**.  https://s3.amazonaws.com/redcap-aws-cloudformation/00-master-rc.yaml
![alt-text](https://github.com/JamesSWiggins/project-redcap-aws-automation/blob/master/images/redcap_cfn_select_template.png "CFN Select Template")


2. On the next screen, provide a **Stack Name** and a few other parameters for your REDCap environment.  A description is provided for each parameter to explain its function.  Please keep in mind that the **Elastic Beanstalk Endpoint Name** must be unique within your AWS Region.  You can check to see if an endpoint name is in use by checking for an existing DNS entry using the 'nslookup' command (nslookup (EBEndpoint).(region).elasticbeanstalk.com).  If the command returns an IP address, that means that the name is in use and you should pick a different name.  When you've provided appropriate values for the **Parameters**, choose **Next**.

3. On the next screen, you can provide some other optional information like tags at your discretion, or just choose **Next**.

4. On the next screen, you can review what will be deployed. At the bottom of the screen, there is a check box for you to acknowledge that **AWS CloudFormation might create IAM resources with custom names**. This is correct; the template being deployed creates four custom roles that give permission for the AWS services involved to communicate with each other. Details of these permissions are inside the CloudFormation template referenced in the URL given in the first step. Check the box acknowledging this and choose **Next**.

5. You can watch as CloudFormation builds out your REDCap environment. A CloudFormation deployment is called a *stack*. The parent stack creates several child stacks depending on the parameters you provided.  When all the stacks have reached the green CREATE_COMPLETE status, as shown in the screenshot following, then the REDCap architecture has been deployed.  Select the **Outputs** tab to find your REDCap environment URL.
![alt-text](https://github.com/JamesSWiggins/project-redcap-aws-automation/blob/master/images/redcap_cfn_stack_complete.png "CFN Stack Complete")

6. After clicking on the provided URL, you will be taken to the REDCap login screen.  You can login by using the username 'redcap_admin' and the password you provided in the **DB Master Password Parameter**.  You will immediately be asked to change the password.

### Ongoing Operations
At this point, you have a fully functioning and robust REDCap environment to begin using.  Following are some helpful points to consider regarding how to support this environment on-going.

#### Web Security
Consider implementing a [AWS Web Application Firewall (WAF)](https://aws.amazon.com/waf/) in front of your REDCap application to help protect against common web exploits that could affect availability, compromise security or consume excessive resources.  You can use AWS WAF to create custom rules that block common attack patterns, such as SQL injection or cross-site scripting.  Learn more in the whitepaper ["Use AWS WAF to Mitigate OWASP’s Top 10 Web Application Vulnerabilities"](https://d0.awsstatic.com/whitepapers/Security/aws-waf-owasp.pdf) .  You can deploy AWS WAF on either Amazon CloudFront as part of your CDN solution or on the Application Load Balancer (ALB) that was deployed as a part of this solution.

#### Pull logs, view monitoring data, get alerts, and apply patches
Using the Elastic Beanstalk service you can [pull log files from one or more of your instances](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/using-features.logging.html).  You can also [view monitoring data](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/environments-health.html) including CPU utilization, network utilization, HTTP response codes, and more.  From this monitoring data, you can [configure alarms](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/using-features.alarms.html) to notify you of events within your REDCap application environment.  Elastic Beanstalk also makes [managed platform updates available](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/environment-platform-update-managed.html), including Linux, PHP, and Apache upgrades that you can apply during maintanence windows your define.

Using AWS Relational Database Services (RDS) you can [pull log files from you Aurora MySQL database](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_LogAccess.html).  You can also [view monitoring data and create alarms on metrics](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Aurora.Monitoring.html) including disk space, CPU utilization, memory utilization, and more.  RDS also makes available [Aurora MySQL DB Engine upgrades](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Aurora.Updates.html) that are applied automatically during a maintenance window you define.

#### Access Running REDCap Instances
If you need to access the command line on the running REDCap instances, this can be done by using the [AWS Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html).   It lets you manage your Amazon EC2 instances through an interactive one-click browser-based shell or through the AWS CLI. Session Manager provides secure and auditable instance management without the need to open inbound ports, maintain bastion hosts, or manage SSH keys.  Just go to the the [AWS Systems Manager Session Manager Console](https://console.aws.amazon.com/systems-manager/session-manager/) and **click Start session**.  You'll then see a list of your REDCap instances.  Select the one that you want to access and **click Start session**.  Now you have a shell with sudoers access.
![alt-text](https://github.com/JamesSWiggins/project-redcap-aws-automation/blob/master/images/redcap-session-manager.gif "REDCap Session Manager demo") 

#### Fault tolerance and backups
Elastic Beanstalk keeps a highly available copy of your current and previous REDCap application versions as well as your environment configuration.  This can be used to re-deploy or re-create your REDCap application environment at any time and serves as a 'backup'.  You can also [clone an Elastic Beanstalk environment](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/using-features.managing.clone.html) if you want a temporary environment for testing or as a part of a recovery exercise.  High availability and fault tolerance are provided are achieved by [configuring your environment to have a minimum of 2 instances](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/using-features.managing.as.html).  Elastic Beanstalk will deploy these REDCap application instances over multiple availability zones.  If an instance is unhealthy it will automatically be removed and replaced.

The AWS Relational Database Service (RDS) automatically takes backups of your database that you can use to restore or "roll-back" the state of your application.  You can [configure how long they are retained and when they are taken using the RDS management console](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_WorkingWithAutomatedBackups.html).  These backups can also be used to create a copy of your database for use in testing or as a part of a recovery exercise.  High availability and fault tolerance are provided by using the ['Multi-AZ' deployment option for RDS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZ.html).  This creates a primary and secondary copy of the database in two different availability zones.  

#### Scalability
Your Elastic Beanstalk environment is configured to scale automatically based on CPU utilization within the minimum and maximum instance parameters you provided during deployment.  [You can change this configuration](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/using-features.managing.as.html) to specify a larger minimum footprint, a larger maximum footprint, different instance sizes, or different scaling parameters.  This allows your REDCap application environment to respond automatically to the amount of load seen from your users.

Your Relational Database Environment can be scaled by [selecting a larger instance type](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/AuroraMySQL.Managing.Performance.html#AuroraMySQL.Managing.Performance.InstanceScaling) or increasing the storage capacity of your instances.

### Changing your REDCap configuration

In general, the REDCap application is configured through the **Control Center** within the REDCap web interface.  There are, however, certain configuration changes that must be made by modifying files within the REDCap application on the application server file system.  One common example of this is configuring REDCap application authentication with an external LDAP account repository (like Microsoft Active Directory).

Elastic Beanstalk provides an elastic environment for applications that can dynamically scale-up and scale-down in response to load.  You can also use Elastic Beanstalk to replicate or re-create your application environment.  As Elastic Beanstalk does this, it uses configuration files to ensure all of the instances it dynamically creates are in sync.  This configuration is stored in a special directory within the application package you provide to Elastic Beanstalk [called '.ebextensions'](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/ebextensions.html).  Following is an example of how to make filesystem level configuration changes (like LDAP integration) to your REDCap environment.

To access your current application version, open the [Elastic Beanstalk console](https://console.aws.amazon.com/elasticbeanstalk) and **Choose your REDCap application**.  In the navigation pane, **choose Application Versions**.  Then select the zip file under the **Source** column of the currently deployed version.

Once you've downloaded the zip file, you can open it and find the directory called **.ebextensions/**.  This directory [contains configuration files with a specific, YAML format](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/customize-containers-ec2.html) that tell Elastic Beanstalk which steps to perform when deploying this application.  You can also use this directory to add files to the filesystem of each Elastic Beanstalk instance by creating a directory structure.  On Elastic Beanstalk PHP servers, the PHP application is deployed to **/var/app/current/**, and we know that we need to update the file within the REDCap application called **./redcap/webtools2/ldap/ldap_config.php**.  So, within create the directory structure within your application zip file **.ebextensions/var/app/current/redcap/webtools2/ldap/** and place your updated **ldap_config.php** file within it.  As you can see, the directory structure of your Elastic Beanstalk application zip file is very important, so be careful to precisely capture it.

Now you can [upload your modified application zip file as a new version](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/applications-versions.html) to your Elastic Beanstalk REDCap environment.  Once the new version has been uploaded, select it and [deploy it to your REDCap Environment](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/using-features.deploy-existing-version.html).  There are several different deployment options provided by Elastic Beanstalk that help you manage deployment time, application downtime, and the impact of a failed deployment.  Once your new application version has been applied with your REDCap application filesystem changes it will be used to keep your environment in sync when new instances are created if your environment scales out, if an instance fails, or if you need to re-create your environment for operational or disaster recovery.



