#! /bin/bash

echo "Hello I will help you setup an non https django project the install location will be under /projects\n"
echo "This will help you set up an apache server to serve the django app wiht a postgresql database \n"

echo "\nWho are you?"
echo users
read username

echo "\nInput name of project"
read project_name

echo "\nInput your staticIP in format 192.168.1.10/24"
read project_ip

echo "\nInput your gateway address ex: 192.168.1.1, usually it is the first ip of your ip address"
read project_gateway

echo "\nInput your DNS servers, I recommend to add 2,  if this is a enterprise app, you should add you dns server IP to recognize internal dns records, if not use google 8.8.8.8 or 1.1.1.1"
read proejct_dns

echo "\nPlease select your network adapter"
sudo ip link && echo "\n"
read ethernet_card

echo "# This is the network config written by 'subiquity'
network:
  ethernets:
    $ethernet_card:
      dhcp4: no
      addresses: [$project_ip]
      gateway4: $project_gateway
      nameservers:
        addresses: [$proejct_dns]
  version: 2" | sudo tee /etc/netplan/00-installer-config.yaml 

sudo netplan apply

# Updating OS
# sudo apt update && echo "\n"

# Installing Apache Web Server, Postgresql, python3 pip (if not installed), and Mod-WSGI
sudo apt install python3 python3-pip apache2 postgresql postgresql-contrib libpq-dev python3-dev libapache2-mod-wsgi-py3 -y -qq && echo "\n"

#Creaet default user and database
sudo -u postgres createuser -s $username
createdb django_main
psql -d django_main -c "CREATE USER django WITH PASSWORD 'root'"
psql -d django_main -c "grant ALL on DATABASE django_main to django;"

#sudo create developers group to control acces to folders and add current user
sudo addgroup developers && echo "\n"
sudo adduser $username developers && echo "\n"

# Creating projects folder and give permisions

if [ -d /projects ]
then
    echo "folder /projects already created. \n"
else
    sudo mkdir /projects
    sudo mkdir /projects/$project_name
    sudo chown root:developers -R /projects 
    sudo chmod -R 775 /projects 
fi

# Install virtualenv to keep python installation clean
pip -q install virtualenv
# Install virtualenv for python in projects, and install django
python3 -m virtualenv /projects/venv_django
/projects/venv_django/bin/pip install asgiref Django django-cors-headers django-filter djangorestframework flake8 Markdown mccabe psycopg2 pycodestyle pyflakes pytz sqlparse 
/projects/venv_django/bin/python -m django startproject $project_name /projects/$project_name

# Create old apache config backup, skips if exists

if [ -f /etc/apache2/sites-available/000-default.conf.bak ]
then
    echo "\nOriginal backup exists on your filesystem not overwriting for safety measures.\n"
else
    sudo cp /etc/apache2/sites-available/000-default.conf /etc/apache2/sites-available/000-default.conf.bak
fi

#Use the backup and concatenate the django requiered confs
( head -n -3 /etc/apache2/sites-available/000-default.conf.bak; echo "
        alias /static /projects/$project_name/site/public/static

        <Directory /projects/$project_name/site/public/static>
                Require all granted
        </Directory>

        <Directory /projects/$project_name/$project_name>
                <Files wsgi.py>
                        Require all granted
                </Files>
        </Directory>

        WSGIDaemonProcess $project_name python-path=/projects/$project_name python-home=/projects/venv_django
        WSGIProcessGroup $project_name
        WSGIScriptAlias / /projects/$project_name/$project_name/wsgi.py

</VirtualHost>

"  ) | sudo tee /etc/apache2/sites-available/000-default.conf

sudo service apache2 restart

echo "
username: $username
project name: $project_name
static ip: $project_ip
ip gateway: $project_gateway
global dns: $proejct_dns
network adapter name: $ethernet_card

psql created database: django_main
psql super user created: $username
psql user for django settings: django
psql password for user django: root

your project is here: /projects/$project_name
I will recommend to check the ownership of the files since its a hit or miss right now (tip: chmod and chown are your friends when you cannot access the files)
" > ./django_installation_information.txt
