#!/usr/bin/env bash
export AWS_DEFAULT_REGION=${AWS::Region}
#Insert the correct environment details into the database.php file
sed -i 's!'your_mysql_host_name'!'${RDSEndpoint}'!' /var/app/current/redcap/database.php
sed -i 's!'your_mysql_db_name'!'redcap'!' /var/app/current/redcap/database.php
sed -i 's!'your_mysql_db_username'!'redcap_user'!' /var/app/current/redcap/database.php
sed -i 's!'your_mysql_db_password'!'${DBPassword}'!' /var/app/current/redcap/database.php
#If we don't have an established 'salt' string, generate one and store it in AWS SSM
if ! aws ssm get-parameter --name redcap-salt; then
    aws ssm put-parameter --name "redcap-salt" --type "SecureString" --value `head /dev/urandom | tr -dc a-z0-9 | head -c 8 ; echo ''`
fi
#Apply 'salt' string from AWS SSM to the database.php file.  This ensures the 'salt' string is the same on every PHP server.
sed -i "s#\$salt = '';#\$salt = '`aws ssm get-parameter --name redcap-salt --with-decryption --query 'Parameter.Value' --output text`';#" /var/app/current/redcap/database.php

#only do the below tasks if it's the first deployment to this server.
if [ ! -f /eb-configured ]; then

touch /var/log/eb-activity.log
#sudo yum install -y https://dev.mysql.com/get/mysql57-community-release-el7-11.noarch.rpm
#sudo yum install -y mysql-community-client

yum install -y php-ldap sendmail-cf                

#Create the REDCap CRON entry
(crontab -l ; echo -e "# REDCap Cron Job (runs every minute)\n* * * * * /usr/bin/php /var/app/current/redcap/cron.php > /dev/null") | crontab

#Create redcap_user and redcap_user2
mysql -h ${RDSEndpoint} -u master -D redcap --password=${DBPassword} < /create-redcap-user.sql

# If this is the leader-node and if the REDCap schema hasn't already been applied, create the initial 'redcap_admin' user, grab the SQL off the install.php website and apply it.
if [ -e /leaderonly ]; then
  if ! mysql -h ${RDSEndpoint} -u master -D redcap --password=${DBPassword} -e "select * from redcap_actions"; then
          count=0  
          while ! [ -s /curl.out ] && [ $count -ne "100" ];
          do
            (curl -o /curl.out -k -F redcap_csrf_token= -F superusers_only_create_project=0 -F superusers_only_move_to_prod=1 -F auto_report_stats=1 -F bioportal_api_token= -F redcap_base_url='${Protocol}${RCDomainName}.${HostedZone}/' -F enable_url_shortener=1 -F default_datetime_format='D/M/Y_12' -F default_number_format_decimal=, -F default_number_format_thousands_sep=. -F homepage_contact='REDCap Administrator (123-456-7890)' -F homepage_contact_email=email@yoursite.edu -F project_contact_name='REDCap Administrator (123-456-7890)' -F project_contact_email=email@yoursite.edu -F institution='SoAndSo University' -F site_org_type='SoAndSo Institute for Clinical and Translational Research' -F hook_functions_file='/var/app/current/redcap/hook_functions.php' ${Protocol}localhost/install.php)
            sleep 20
            let count+=1
          done                               
          sed -ni '/onclick=\x27this.select();\x27>/,/<\/textarea>/p' /curl.out 
          sed -i -e "1d" /curl.out
          temp=`tail -1 /curl.out | cut -d';' -f1`; sed '$d' /curl.out > /mysql-rc.sql; echo $temp';' >> /mysql-rc.sql
          mysql -h ${RDSEndpoint} -u master -D redcap --password=${DBPassword} < /mysql-rc.sql
          mysql -h ${RDSEndpoint} -u master -D redcap --password=${DBPassword} < /create-initial-user.sql
  fi
fi
rm -f /curl.out /mysql.sql /mysql-rc.sql /create-redcap-user.sql /create-initial-user.sql

#Apply additional PHP configuration as specified by REDCap
echo "max_input_vars = 100000" >> /etc/php.ini
sed -i "s/upload_max_filesize = 2M/upload_max_filesize = 32M/" /etc/php.ini
sed -i "s/post_max_size = 8M/post_max_size = 32M/" /etc/php.ini

if [ ${Protocol} == 'https']; then
  echo "session.cookie_secure = on" >> /etc/php.ini
fi

systemctl restart nginx
systemctl restart php-fpm

#sendmail configuration to enable sending e-mails
sudo postconf -e "relayhost = [email-smtp.us-east-1.amazonaws.com]:587" \
"smtp_sasl_auth_enable = yes" \
"smtp_sasl_security_options = noanonymous" \
"smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd" \
"smtp_use_tls = yes" \
"smtp_tls_security_level = encrypt" \
"smtp_tls_note_starttls_offer = yes"
echo "[email-smtp.us-east-1.amazonaws.com]:587 ${SESu}:${SESpw}" >> /etc/postfix/sasl_passwd
sudo postmap hash:/etc/postfix/sasl_passwd
sudo postconf -e 'smtp_tls_CAfile = /etc/ssl/certs/ca-bundle.crt'
sudo postfix start
sudo postfix reload
touch /eb-configured
else 
echo "Already ran EB configuration scripts.  This must be an application redeployment"
fi
