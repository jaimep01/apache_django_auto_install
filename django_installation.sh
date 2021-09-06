#! /bin/bash

printf "I will help you set up an apache server, a django app, and a postgresql database.\n"

read -p "Input DB USERNAME: " USERNAME

read -p "Input name of project: " PROJECT_NAME

read -p "Input project working directory: " PROJECT_DIR

read -p "Want to setup networking? [Y/n]" SETUP_NET

if [ $SETUP_NET = "Y" ] || [ $SETUP_NET = "y" ] ;
then
  read -p "Input your staticIP in format 192.168.1.10/24: " PROJECT_IP

  read -p "Input your gateway address ex: 192.168.1.1: " PROJECT_GATEWAY

  read -p "Iput your DNS servers, I recommend to add 2,  if this is an enterprise app, you should add your internal dns server IP to recognize internal dns records, if not use google 8.8.8.8 or 1.1.1.1: " PROJECT_DNS
  
  printf "Please select your network adapter from the list:"
  ip -br link | awk  '{print "NIC: "$1,"    Stauts: "$2}' && printf "\n"
  read -p "NIC: " NIC

  if [ -f /etc/netplan/00-installer-config.yaml.bak ]
  then
      printf "\nOriginal backup exists on your filesystem not overwriting for safety measures.\n"
  elif [ -f /etc/netplan/00-installer-config.yaml ] 
  then
      printf "Created backup 00-installer-config.yaml.bak"
      cp /etc/netplan/00-installer-config.yaml /etc/netplan/00-installer-config.yaml.bak
  else
      netplan generate
  fi

  printf "# This is the network config written by 'subiquity'
  network:
    ethernets:
      $NIC:
        dhcp4: no
        addresses: [$PROJECT_IP]
        gateway4: $PROJECT_GATEWAY
        nameservers:
          addresses: [$PROJECT_DNS]
    version: 2" | tee /etc/netplan/00-installer-config.yaml 

  netplan apply 
fi

# Updating OS
sudo apt update && printf "\n"

# Installing Apache Web Server, Postgresql, python3 pip (if not installed), and Mod-WSGI
apt install python3 python3-pip apache2 postgresql postgresql-contrib libpq-dev python3-dev libapache2-mod-wsgi-py3 -y -qq && printf "\n"

#Creaet default user and database
sudo -u postgres createuser -s $USERNAME
sudo -u postgres createdb django_main
sudo -u postgres psql -d django_main -c "CREATE USER django WITH PASSWORD 'root'"
sudo -u postgres psql -d django_main -c "grant ALL on DATABASE django_main to django;"

#sudo create developers group to control acces to folders and add current user
addgroup developers && printf "\n"
adduser $USERNAME developers && printf "\n"

Creating projects folder and give permisions

echo "$PROJECT_DIR/$PROJECT_NAME"

if [ -d $PROJECT_DIR/$PROJECT_NAME ]
then
    printf "folder $PROJECT_DIR already created.\n"
else
    mkdir -p $PROJECT_DIR/$PROJECT_NAME
    chown root:developers -R $PROJECT_DIR 
    chmod -R 770 $PROJECT_DIR 
fi

# Install virtualenv to keep python installation clean
pip -q install virtualenv
# Install virtualenv for python in projects, and install django
python3 -m virtualenv $PROJECT_DIR/venv_django
$PROJECT_DIR/venv_django/bin/python -m pip install --upgrade pip
$PROJECT_DIR/venv_django/bin/pip install asgiref Django django-cors-headers django-filter djangorestframework flake8 Markdown mccabe psycopg2 pycodestyle pyflakes pytz sqlparse 
$PROJECT_DIR/venv_django/bin/python -m django startproject $PROJECT_NAME $PROJECT_DIR/$PROJECT_NAME

# Create old apache config backup, skips if exists

if [ -f /etc/apache2/sites-available/000-default.conf.bak ]
then
    printf "\nOriginal backup exists on your filesystem not overwriting for safety measures.\n"
else
    cp /etc/apache2/sites-available/000-default.conf /etc/apache2/sites-available/000-default.conf.bak
fi

#Use the backup and concatenate the django requiered confs
( head -n -3 /etc/apache2/sites-available/000-default.conf.bak; printf "
        alias /static $PROJECT_DIR/$PROJECT_NAME/site/public/static

        <Directory $PROJECT_DIR/$PROJECT_NAME/site/public/static>
                Require all granted
        </Directory>

        <Directory $PROJECT_DIR/$PROJECT_NAME/$PROJECT_NAME>
                <Files wsgi.py>
                        Require all granted
                </Files>
        </Directory>

        WSGIDaemonProcess $PROJECT_NAME python-path=$PROJECT_DIR/$PROJECT_NAME python-home=$PROJECT_DIR/venv_django
        WSGIProcessGroup $PROJECT_NAME
        WSGIScriptAlias / $PROJECT_DIR/$PROJECT_NAME/$PROJECT_NAME/wsgi.py

</VirtualHost>

"  ) | tee /etc/apache2/sites-available/000-default.conf

chown root:developers -R $PROJECT_DIR
chmod -R 770 $PROJECT_DIR 

service apache2 restart

printf "
USERNAME: $USERNAME
project name: $PROJECT_NAME
static ip: $PROJECT_IP
ip gateway: $PROJECT_GATEWAY
global dns: $PROJECT_DNS
network adapter name: $NIC

psql created database: django_main
psql super user created: $USERNAME
psql user for django settings: django
psql password for user django: root

your project is here: $PROJECT_DIR/$PROJECT_NAME
I will recommend to check the ownership of the files since its a hit or miss right now (tip: chmod and chown are your friends when you cannot access the files)
" > ./django_installation_information.txt
