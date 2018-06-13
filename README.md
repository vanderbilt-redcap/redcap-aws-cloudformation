# Deploy a Project REDCap environment on AWS using automation and architectural best practices
This repository contains AWS CloudFormation templates to automatically deploy a Project REDCap environment that adheres to AWS architectural best practices.  In order to use this automation you must supply your own copy of te Project REDCap source files.  These are available for qualified entities at https://www.project-redcap.org/.  Once you have downloaded your source files then you can follow the below instructions for deployment.

## Project REDCAp on AWS architecture and features
The features of using this architecture are as follows:
* A complete and ready-to-use Project REDCap environment is automatically deployed in about 20 minutes.
* Project REDCap is deployed in an isolated, three-tiered Virtual Private Cloud
* The environment enables automatic scaling up and down based on load.
* Data is encrypted by default at rest and in flight (in accordance with HIPAA)
* Managed services are used that provide automated patching and maintanence of OS, middleware, and database software.
* Database backups are performed automatically to enable operational and disaster recovery.
* [The design results in a reasonable monthly cost](https://calculator.s3.amazonaws.com/index.html#r=IAD&key=calc-2CA042AD-1E05-4BDD-9571-5473C42A24F7) 

A high-level diagram showing how the different functions of Project REDCap map to AWS Services is shown below.  
![alt-text](https://github.com/JamesSWiggins/project-redcap-aws-automation/raw/master/AWS%20Project%20REDCap%20Block%20Diagram.png "AWS Project REDCap High-Level Diagram")

Starting from the user, public Internet DNS services are (optionally) provided by Amazon Route53.  This gives you the ability to automatically add a domain to an existing hosted zone in Route53 (i.e. redcap.example.edu if example.edu is already hosted in Route53).  In addition, if you are deploying a new domain to Route53, an SSL certificate can be automatically generated and applied using AWS Certificate Manager (ACM).  This enables HTTPS communication and ensures the data sent from the users it encrypted in-transit (in accordance with HIPAA).  HTTPS communication is also used between the Application Load Balancers and the Project REDCap servers.

AWS Elastic Beanstalk is used to deploy the Project REDCap application onto Apache/PHP Linux servers.  Elastic Beanstalk is an easy-to-use service for deploying and scaling web applications. It covers everything from capacity provisioning, load balancing, regular OS and middleware updates, autoscaling, and high availability, to application health monitoring. Using a feature of Elastic Beanstalk called ebextensions, the Project REDCap servers are customized to use an encrypted storage volume for the middleware application logs.

Amazon Relational Database Service (RDS) with Amazon Aurora MySQL is used to provide an (optionally) highly available database for the Project REDCap application.  Amazon Aurora is a relational database built for the cloud that combines the performance and availability of high-end commercial databases with the simplicity and cost-effectiveness of open-source databases. It provides cost-efficient and resizable capacity while automating time-consuming administration tasks such as hardware provisioning, database setup, patching, and backups. It is configured for high availability and uses encryption at rest for the database and backups, and encryption in flight for the JDBC connections.  The data stored inside this database is also encrypted at rest.

Amazon Simple Storage Service (S3) is used as a file repository for files uploaded through Project REDCap.  S3 is designed to deliver 99.999999999% durability, and stores data for millions of applications used by market leaders in every industry. S3 provides comprehensive security and compliance capabilities that meet even the most stringent regulatory requirements.  The S3 bucket used to store these files is encrypted using AES-256.

Amazon Simple Email Service (SES) is used enable Project REDCap to send emails to users.  SES is a powerful, affordable, and highly-scalable email sending and receiving platform for businesses and developers that integrates seamlessly with applications and with other AWS products.  SES provides a reliable SMTP gateway without the need to maintain a separate SMTP server.

