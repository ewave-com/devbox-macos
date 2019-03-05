#!/usr/bin/env bash
# List constants
xdebug_port=9001
current_folder="$(pwd)"
current_user="$(whoami)"
docker_compose_log_level=ERROR
# List of functions
# Set color variable
DARKGRAY='\033[1;30m'
RED='\033[0;31m'
LIGHTRED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
LIGHTPURPLE='\033[1;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
SET='\033[0m'

#Prepare system, Installing Brew
prepare_system () {
if [ ! -f  /usr/local/bin/docker ]; then
  echo -e "$RED Docker is not installed! $SET"
  echo -e "$GREEN Please download and install $SET"
  echo -e "$GREEN https://download.docker.com/mac/stable/Docker.dmg $SET"
  exit 0
fi

if [ ! -f  /usr/local/bin/unison ]; then
  ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)" < /dev/null 2> /dev/null
  brew install python
  brew install unison
  brew install eugenmayer/dockersync/unox
  brew install openssl
  sudo easy_install pip
  sudo chmod +x /usr/local/bin/unison-fsmonitor
  sudo pip install macfsevents
fi

if [ ! -f  /usr/local/bin/composer ]
then
  brew install composer
  composer install
else
  composer install
fi
}

# Function which find projects in folder
list_projects(){
echo "----------------------------------------------"
echo -e " * * * * * * * $GREEN Select project $SET* * * * * * * * "
echo "----------------------------------------------"
PS3='Please input number  --->:'
list="$(ls "./projects" | sed 's/ /£/'| grep -v ".txt") Exit"
select project_folder in $list
do
    if [ "$project_folder" = "Exit" ] #if user selects Exit, then exit the program
    then
        exit 0
    elif [ -n "$project_folder" ] #if name is valid, shows the files inside
    then
        break
    else #if the number of the choice given by user is wrong, exit
        echo "Invalid choice ($REPLY)!"
    fi
done
}

#Prepare ENV file
prepare_env(){
sudo chmod 777 ./projects/$project_folder/.env
tr '\r' '\n' < ./projects/$project_folder/.env > ./projects/$project_folder/newfile.env
sudo chmod 777 ./projects/$project_folder/newfile.env
mv ./projects/$project_folder/newfile.env ./projects/$project_folder/.env
}

###########################################
# Function which set variable from ENV file
set_env(){
export $(cat ./projects/$project_folder/.env | grep -Ev "^$" | grep -v '^#' | xargs)
}

# Function which unset variable from ENV file
# Run function ONLY in the END
unset_env(){
unset -f $(cat ./projects/$project_folder/.env | grep -Ev "^$"  | grep -v '^#' | sed -E 's/(.*)=.*/\1/' | xargs)
}
###########################################


# Function which start nginx,portainer,mailhog
start_env () {
export $(cat ./configs/env/.env | grep -Ev "^$" | grep -v '^#' | xargs)
cd ./configs/env/
sudo docker-compose --log-level "$docker_compose_log_level" -f docker-compose-portainer.yml up -d
sudo docker-compose --log-level "$docker_compose_log_level" -f docker-compose-nginx-reverse-proxy.yml up -d

if [[ $MAILER_TYPE = mailhog ]]; then
  sudo docker-compose --log-level "$docker_compose_log_level" -f docker-compose-mailhog.yml up -d
fi
if [[ $MAILER_TYPE = exim4 ]]; then
  sudo docker-compose --log-level "$docker_compose_log_level" -f docker-compose-exim4.yml up -d 
fi
if [[ $ADMINER_ENABLE = yes ]]; then
  sudo docker-compose --log-level "$docker_compose_log_level" -f docker-compose-adminer.yml up -d 
fi
cd ../../
unset -f $(cat ./configs/env/.env | grep -Ev "^$"  | grep -v '^#' | sed -E 's/(.*)=.*/\1/' | xargs)
}


# Function which find free port for ssh service
ssh_free () {
count_stop_projects=$(docker ps --filter "status=exited" | grep "$CONTAINER_WEB_NAME" | wc -l | awk '{print $1}' )  
sleep 2;
if [[ $count_stop_projects = 0 ]]; then 
    ssh_port=$(netstat -anv | egrep -w [.] | grep LISTEN | grep "tcp4" |  awk '{print $4}' | grep "*." | grep 230 | cut -c3- | sort -g -r | head -n 1);
    if [[ -z "$ssh_port" ]]; then
    ssh_port=2300
    else
    ssh_port=$(($ssh_port +1))
    fi
else 
#Array for port which in using docker compose
arr=()
# Counter
x=0
for ii in $(for i in $(find ./projects -name docker-compose.yml -type f -maxdepth 2); do grep -R 23 $i | grep -Eo '[0-9]{4}' | sort -t: -u -k1,1 | head -1; done)
  do
arr[x]=$ii
x=$x+1
  done
IFS=$'\n'
ssh_temp_port=$(echo "${arr[*]}" | sort -nr | head -n1)
ssh_port=$(($ssh_temp_port+1))
fi

}

mysql_check_used_port(){
if [[ ! -z $CONTAINER_MYSQL_PORT ]];then
  if [[ $CONTAINER_MYSQL_PORT < 3400 ]];then 
  echo -e "$RED MYSQL port less then 3400 $SET. Set CONTAINER_MYSQL_PORT between 3400-3499"; exit 1;
  fi
  if [[ $CONTAINER_MYSQL_PORT > 3499 ]];then 
  echo -e "$RED MYSQL port more then 3499 $SET. Set CONTAINER_MYSQL_PORT between 3400-3499"; exit 1;
  fi
fi  
}

# Function which find free port for mysql service
mysql_free (){
count_stop_projects=$(docker ps --filter "status=exited" | grep "$CONTAINER_MYSQL_NAME" | wc -l | awk '{print $1}')  
sleep 2;
if [[ $count_stop_projects = 0 ]]; then 
  if [[ -z $CONTAINER_MYSQL_PORT ]]; then
    mysql_port=$(netstat -anv | egrep -w [.] | grep LISTEN | grep "tcp4" |  awk '{print $4}' | grep "*." | grep 340 | cut -c3- | sort -g -r | head -n 1);
    if [[ -z "$mysql_port" ]]; then
    mysql_port=3400
    else
    mysql_port=$(($mysql_port +1))
    fi
  else
  mysql_port=$CONTAINER_MYSQL_PORT
  fi
else 
#Array for port which in using docker compose
arr=()
# Counter
x=0
for ii in $(for i in $(find ./projects -name docker-compose.yml -type f -maxdepth 2); do grep -R 34 $i | grep -Eo '[0-9]{4}' | grep -v '3306' | sort -t: -u -k1,1 | head -1; done)
  do
arr[x]=$ii
x=$x+1
  done
IFS=$'\n'
mysql_temp_port=$(echo "${arr[*]}" | sort -nr | head -n1)
mysql_port=$(($mysql_temp_port+1))
fi
}

# Function which find free port for Unison socket
unison_free () {
count_stop_projects=$(docker ps --filter "status=exited" | grep "$CONTAINER_WEB_NAME" | wc -l | awk '{print $1}')  
sleep 2;
if [[ $count_stop_projects = 0 ]]; then 
  unison_port=$(netstat -anv | egrep -w [.] | grep LISTEN | grep "tcp4" | awk '{print $4}' | grep "*." | grep 700 | cut -c3- | sort -g -r | head -n 1);
    if [[ -z "$unison_port" ]]; then
    unison_port=7000
    else
    unison_port=$(($unison_port +1))
    fi
else 
#Array for port which in using docker compose
arr=()
# Counter
x=0
for ii in $(for i in $(find ./projects -name docker-compose.yml -type f -maxdepth 2); do grep -R 70 $i | grep -Eo '[0-9]{4}' | grep -v '5000' | sort -t: -u -k1,1 | head -1; done)
  do
arr[x]=$ii
x=$x+1
  done
IFS=$'\n'
unison_temp_port=$(echo "${arr[*]}" | sort -nr | head -n1)
unison_port=$(($unison_temp_port+1))
fi
}

# Function which overwtire bin unison in images.
unison_conf () {
  cat /dev/null > /Users/$current_user/unison.log
  mkdir -p ~/Library/Application\ Support/Unison/
  sudo chmod +x ./tools/unison/unison-2.51/*
  sudo chmod -R 777 ./tools/unison/unison-2.51/*
if [[ ! -f ./projects/$project_folder/docker-compose.yml ]]; then
  cp -r ./configs/templates/unison/$CONFIGS_PROVIDER_UNISON/unison.prf ~/Library/Application\ Support/Unison/$project_folder.prf
  sed -i '' 's|WEBSITE_DOCUMENT_ROOT|'$WEBSITE_DOCUMENT_ROOT'|g' ~/Library/Application\ Support/Unison/$project_folder.prf
  sed -i '' 's/unison_port/'$unison_port'/g' ~/Library/Application\ Support/Unison/$project_folder.prf
  sed -i '' 's/project_folder/'$project_folder'/g' ~/Library/Application\ Support/Unison/$project_folder.prf
fi
}

# Function which pop-up terminal with unison sync
unison_run () {
osascript -e "tell application \"Terminal\" to do script \"cd $current_folder && unison -repeat=watch $project_folder\""
}

# Copy mysql's files in docker container
start_db () {
echo ================================
echo Copying DB Files to container
sleep 10
if [[ -z "$check_mysql_container_created" ]]; then
  if [[ -d ./projects/$project_folder/db/mysql/ ]]; then 
  docker cp ./projects/$project_folder/db/mysql/ "$PROJECT_NAME"_$CONTAINER_MYSQL_NAME:/var/lib/
# fix after copy.Must have.
  docker restart "$PROJECT_NAME"_$CONTAINER_MYSQL_NAME
  fi
fi
  echo ================================
}

presync_web () {
echo ================================
echo Copying WEB Files to container
sleep 3
if [[ -z "$check_web_container_created" ]]; then
  docker cp ./projects/$project_folder/public_html/. "$PROJECT_NAME"_"$CONTAINER_WEB_NAME":"$WEBSITE_DOCUMENT_ROOT"
fi
  echo ================================
}

# Function  which  ENV file in project's folder
check_env_file(){
if [ ! -f  ./projects/$project_folder/.env ]; then
  echo -e "$RED File .ENV not found! Please check! $SET"
  exit 0
fi
}

# Generate SSL 
ssl_on(){
if [[ ! -f ./projects/$project_folder/docker-compose.yml ]]; then  
  mkdir -p ./configs/env/nginx/conf.d/
  mkdir -p ./configs/env/nginx/ssl/
  mkdir -p ./configs/env/nginx/logs/
  sudo docker exec -ti nginx-reverse-proxy bash -c "openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name secp384r1) -keyout /etc/nginx/ssl/$WEBSITE_HOST_NAME.key -out /etc/nginx/ssl/$WEBSITE_HOST_NAME.crt -days 365 -subj "/C=BY/ST=Minsk/L=Minsk/O=DevOpsTeam_EWave/CN=$WEBSITE_HOST_NAME""
  cp -r ./configs/templates/nginx/reverse-proxy/nginx-https-proxy.conf.template ./configs/env/nginx/conf.d/$WEBSITE_HOST_NAME.conf
  sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ./configs/env/nginx/ssl/$WEBSITE_HOST_NAME.crt
fi
}

# Skip generate SSL 
ssl_off(){
if [[ ! -f ./projects/$project_folder/docker-compose.yml ]]; then    
  mkdir -p ./configs/env/nginx/conf.d/
  mkdir -p ./configs/env/nginx/ssl/
  mkdir -p ./configs/env/nginx/logs/
  cp -r ./configs/templates/nginx/reverse-proxy/nginx-http-proxy.conf.template ./configs/env/nginx/conf.d/$WEBSITE_HOST_NAME.conf
fi
}

# Function which run ssl_off or ssl_on 
ssl_check(){
if [[ -z $WEBSITE_PROTOCOL ]]; then
  request_ssl
else
  if [[ $WEBSITE_PROTOCOL = https ]]; then
    prepare_env ; unison_free ; mysql_free ; ssh_free ; unison_free ; start_env ; ssl_on
  else
    prepare_env ; unison_free ; mysql_free ; ssh_free ; unison_free ; start_env ; ssl_off
  fi
fi
}

# This function use in add_domain function
nginx_platform(){
if [[ ! -f ./projects/$project_folder/docker-compose.yml ]]; then   
  if [[ -z $CONFIGS_PROVIDER_NGINX ]]; then  
    cp -r ./configs/templates/nginx/default/website.conf.template ./projects/"$project_folder"/configs/nginxconf/$WEBSITE_HOST_NAME.conf
    else  
    cp -r ./configs/templates/nginx/"$CONFIGS_PROVIDER_NGINX"/website.conf.template ./projects/"$project_folder"/configs/nginxconf/$WEBSITE_HOST_NAME.conf
  fi
  # Add  another custom CONFIGS_PROVIDER_NGINX
    sed -i '' 's/WEBSITE_HOST_NAME/'$WEBSITE_HOST_NAME'/g'  ./projects/$project_folder/configs/nginxconf/$WEBSITE_HOST_NAME.conf
    sed -i '' 's|WEBSITE_DOCUMENT_ROOT|'$WEBSITE_DOCUMENT_ROOT'|g' ./projects/$project_folder/configs/nginxconf/$WEBSITE_HOST_NAME.conf
fi  
}

php_platform(){
if [[ ! -f ./projects/$project_folder/docker-compose.yml ]]; then 
  if [[ $CONFIGS_PROVIDER_PHP = default ]]; then
    cp -r ./configs/templates/php/default/ini/xdebug.ini ./projects/"$project_folder"/configs/php/xdebug.ini
    cp -r ./configs/templates/php/default/ini/zzz-custom.ini ./projects/"$project_folder"/configs/php/zzz-custom.ini
    sed -i '' 's/xdebug_port/'$xdebug_port'/g' ./projects/"$project_folder"/configs/php/xdebug.ini
  fi
fi
}

varnish_platform(){
cp -r ./configs/templates/varnish/$CONFIGS_PROVIDER_VARNISH/default.vcl.template ./projects/"$project_folder"/configs/varnish/default.vcl
# Add  another custom CONFGIS_PROVIDER_VARNISH
#
sed -i '' 's/PROJECT_NAME/'$PROJECT_NAME'/g' ./projects/"$project_folder"/configs/varnish/default.vcl
sed -i '' 's/CONTAINER_WEB_NAME/'$CONTAINER_WEB_NAME'/g' ./projects/"$project_folder"/configs/varnish/default.vcl
}

# Function  which add domain and sed variable
add_domain(){
sudo -- sh -c -e "echo '127.0.0.1 $WEBSITE_HOST_NAME' >> /etc/hosts";
if [[ ! -f ./projects/$project_folder/docker-compose.yml ]]; then    
  sed -i '' 's/WEBSITE_HOST_NAME/'$WEBSITE_HOST_NAME'/g' ./configs/env/nginx/conf.d/$WEBSITE_HOST_NAME.conf
  sed -i '' 's|WEBSITE_DOCUMENT_ROOT|'$WEBSITE_DOCUMENT_ROOT'|g' ./configs/env/nginx/conf.d/$WEBSITE_HOST_NAME.conf
  sed -i '' 's|PROJECT_NAME|'$PROJECT_NAME'|g' ./configs/env/nginx/conf.d/$WEBSITE_HOST_NAME.conf
  if [[ $VARNISH_ENABLE = yes ]]; then
  sed -i '' 's|CONTAINER_WEB_NAME|'$CONTAINER_VARNISH_NAME'|g' ./configs/env/nginx/conf.d/$WEBSITE_HOST_NAME.conf
  else
  sed -i '' 's|CONTAINER_WEB_NAME|'$CONTAINER_WEB_NAME'|g' ./configs/env/nginx/conf.d/$WEBSITE_HOST_NAME.conf
  fi
fi  


mkdir -p ./projects/$project_folder/configs/nginxconf/
mkdir -p ./projects/$project_folder/configs/nginxlogs/
mkdir -p ./projects/$project_folder/configs/varnish/
mkdir -p ./projects/$project_folder/configs/cron/
mkdir -p ./projects/$project_folder/configs/php/
mkdir -p ./projects/$project_folder/configs/node_modules
mkdir -p ./projects/$project_folder/dumps/db
mkdir -p ./projects/$project_folder/dumps/media
mkdir -p ./projects/$project_folder/dumps/configs
mkdir -p ./projects/$project_folder/db
mkdir -p ./projects/$project_folder/db/es
mkdir -p ./projects/$project_folder/public_html/
#Run funtcion which check nginx template config
nginx_platform 
php_platform 
}

webserver_start(){
#Fix for stop function
if [[ ! -f ./projects/$project_folder/docker-compose.yml ]]; then 
  if [[ $VARNISH_ENABLE = yes ]]; then
    cp -r ./configs/templates/docker/docker-compose-varnish-nginx-mysql.yml ./projects/$project_folder/docker-compose.yml
    #Run funtcion which check varnish template config
    varnish_platform
    else
    cp -r ./configs/templates/docker/docker-compose-nginx-mysql.yml ./projects/$project_folder/docker-compose.yml
  fi
  if [[ $BLACKFIRE_ENABLE = yes ]]; then
  cp -r ./configs/templates/docker/docker-compose-nginx-blackfire-mysql.yml ./projects/"$project_folder"/docker-compose.yml
  fi 
fi
}

#### START: Autostart additional images
# Functions:
redis_start(){
if [[ $REDIS_ENABLE = yes ]]; then
  cp -r ./configs/templates/docker/docker-redis-image.yml ./projects/$project_folder/docker-redis-image.yml
  cd ./projects/$project_folder/  && sudo docker-compose -f docker-redis-image.yml up -d > /dev/null 2>&1 
  cd ../../
fi
}

es_start(){
if [[ $ELASTIC_ENABLE = yes ]]; then
  cp -r ./configs/templates/docker/docker-elastic-image.yml ./projects/$project_folder/docker-elastic-image.yml
  cd ./projects/$project_folder/  && sudo docker-compose -f docker-elastic-image.yml up -d > /dev/null 2>&1 
  cd ../../
fi
}

custom_docker_compose(){
cat ./projects/"$project_folder"/.env | grep -v '#' | grep CUSTOM_COMPOSE > ./projects/"$project_folder"/custom-compose.txt  
sed -i '' -e 's/.*=//g' ./projects/"$project_folder"/custom-compose.txt
for custom_docker_compose_file in $(cat ./projects/"$project_folder"/custom-compose.txt );
do
cp -r ./configs/custom/docker/"$custom_docker_compose_file" ./projects/"$project_folder"/"$custom_docker_compose_file" ; cd ./projects/"$project_folder"/ ; sudo docker-compose --log-level "$docker_compose_log_level" -f "$custom_docker_compose_file" up -d ; cd ../../
done
rm -rf ./projects/"$project_folder"/custom-compose.txt 
}

# Autostart
auto_start_addimage()(
redis_start
es_start
custom_docker_compose
)
#### STOP: Autostart additional images

blackfire_start(){
if [[ ! -f ./projects/$project_folder/docker-compose.yml ]]; then 
  cp -r ./configs/templates/docker/docker-compose-nginx-blackfire-mysql.yml ./projects/"$project_folder"/docker-compose.yml
fi
}

# Change ports in common docker-composer file
sed_ip_port(){  
  sed -i '' 's/ssh_port/'$ssh_port'/g' ./projects/$project_folder/docker-compose.yml
  sed -i '' 's/mysql_port/'$mysql_port'/g' ./projects/$project_folder/docker-compose.yml
  sed -i '' 's/unison_port/'$unison_port'/g' ./projects/$project_folder/docker-compose.yml
}

# Start projecty
start_box(){
cd ./projects/"$project_folder"/ && sudo docker-compose --log-level "$docker_compose_log_level" -f docker-compose.yml up -d 
cd ../../
}

request_ssl(){
while :
  do
  echo "----------------------------------------------"
  echo -e " * * * * * * * $GREEN SSL  option $SET * * * * * * * * "
  echo "----------------------------------------------"
  echo "1)SSL off [prefer]"
  echo "2)SSL on [You will need change base_url in DB]"
  echo "----------------------------------------------"
  echo -n "Enter your menu choice [0-2]:"
  read request_ssl
  case $request_ssl in
    1) prepare_env ; mysql_free ; ssh_free ; unison_free ; start_env ; ssl_off ; break ;;
    2) prepare_env ; mysql_free ; ssh_free ; unison_free ; start_env ; ssl_on ; break ;;
    *) echo "Opps!!! Please select choice 1 or 2"
       echo "Press a key. . ."
       read -n 1
       ;;
   esac
done
}

docker_architecture(){
add_domain ; unison_conf ; webserver_start ; auto_start_addimage ; sed_ip_port ; start_box ; presync_web ; start_db ; unison_run
}

run_option(){
ssl_check ; docker_architecture ;
}

run_platform_tools() {
sudo docker exec -it "$PROJECT_NAME"_"$CONTAINER_WEB_NAME" /bin/bash -c "/usr/bin/php $TOOLS_PROVIDER_REMOTE_PATH/$TOOLS_PROVIDER_ENTRYPOINT --autostart"
}

addToolsAlias(){
sudo docker exec -it "$PROJECT_NAME"_"$CONTAINER_WEB_NAME" /bin/bash -c "echo 'alias platform-tools='\'/usr/bin/php $TOOLS_PROVIDER_REMOTE_PATH/$TOOLS_PROVIDER_ENTRYPOINT\''' >> ~/.bashrc"
sudo docker exec -it "$PROJECT_NAME"_"$CONTAINER_WEB_NAME" /bin/bash -c "echo 'alias platform-tools='\'/usr/bin/php $TOOLS_PROVIDER_REMOTE_PATH/$TOOLS_PROVIDER_ENTRYPOINT\''' >> /var/www/.bashrc && chown -R www-data:www-data /var/www/.bashrc"
}

service_restart(){
    sleep 10;
    #Fix for reload network
    sudo docker restart nginx-reverse-proxy
    #sudo docker exec -ti "$PROJECT_NAME"_"$CONTAINER_WEB_NAME" bash -c "service nginx restart"
}

print_info(){
    echo -e ""
    echo -e "-----------------------------------------------------------------------"
    echo -e " * * * * * * * $GREEN URL's, ports and container names  $SET * * * * * * * * "
    echo -e "-----------------------------------------------------------------------\n"

    echo -e "--------------------------$GREEN SERVICES $SET-----------------------------------"
    echo -e "$GREEN""Mailhog URL $SET: http://127.0.0.1:"$MAILHOG_PORT""
    echo -e "$GREEN""Portainer URL $SET: http://127.0.0.1:"$PORTAINER_PORT""
    echo -e "-----------------------------------------------------------------------\n"

    echo -e "--------------------------$GREEN WEB $SET----------------------------------------"
    echo -e "$GREEN""Project name URL $SET: "$WEBSITE_PROTOCOL"://$PROJECT_NAME.local"
    echo -e "$GREEN""Web container $SET: ""$PROJECT_NAME""_web"
if [[ $VARNISH_ENABLE = yes ]]; then
    echo -e "$GREEN""Varnish container $SET: ""$PROJECT_NAME""_varnish"
fi
    echo -e "-----------------------------------------------------------------------\n"

    echo -e "--------------------------$GREEN MYSQL $SET--------------------------------------"
    echo -e "$GREEN""MYSQL container $SET: ""$PROJECT_NAME""_mysql"
    echo -e "$GREEN""MYSQL connect $SET [from LOCAL PC]:"
    echo -e "$GREEN""Server IP $SET: 127.0.0.1" 
    echo -e "$GREEN""Server Port $SET: $mysql_port"
    echo -e "$GREEN""Credentials $SET: root / "$CONTAINER_MYSQL_ROOT_PASS" "
    echo -e "$GREEN""MYSQL connect $SET [from containers]: mysql -uroot -p"$CONTAINER_MYSQL_ROOT_PASS" -hdb $PROJECT_NAME"
    echo -e "-----------------------------------------------------------------------\n"
if [[ $REDIS_ENABLE = yes ]]; then
    echo -e "--------------------------$GREEN REDIS $SET--------------------------------------"
    echo -e "$GREEN""Redis container $SET: ""$PROJECT_NAME""_redis"
    echo -e "-----------------------------------------------------------------------\n"
fi
if [[ $ELASTIC_ENABLE = yes ]]; then
    echo -e "--------------------------$GREEN ES $SET--------------------------------------"
    echo -e "$GREEN""ES container $SET: ""$PROJECT_NAME""_elastic"
    echo -e "-----------------------------------------------------------------------\n"
fi
    echo -e "--------------------------$GREEN ALL CONTAINERS $SET-----------------------------"
    sudo docker ps --format '{{.Names}}'
    echo -e "-----------------------------------------------------------------------"
}

check_env_ports(){
check_env_https=$(netstat -anv | egrep -w [.] | grep LISTEN | grep "tcp4" | awk '{print $4}' | grep "*." | egrep -w '443'  | cut -c3- )
check_env_proxy_container=$(docker ps -a | egrep '443|80'  | grep nginx | grep Up | awk '{print $1}')
if [[ ! -z $check_env_https ]]; then
    if [[ -z $check_env_https ]]; then
    echo -e "http and http port are using.Please check and rid ports" ; exit 0;
    fi  
fi  
#netstat -anv | egrep -w [.] | grep LISTEN | grep "tcp4" | awk '{print $4}' | grep "*." | egrep -w '443'  | cut -c3-
#ocker ps -a | egrep '443|80'  | grep nginx | grep Up | awk '{print $1}'
}

#Prepare system
prepare_system

# Select folder with project
list_projects

check_env_ports
# Check file env file in project's directory
check_env_file

# Immediately run fucntion
set_env

#Check mysql ports which user use
mysql_check_used_port

## Check mysql containers
#check_mysql_container=$(docker ps -a --format '{{.Names}}'| grep "$PROJECT_NAME"_$CONTAINER_MYSQL_NAME)
check_mysql_container_up=$(docker ps -a | egrep '3306'  | grep "$PROJECT_NAME" | grep "$CONTAINER_MYSQL_NAME" | grep Up | awk '{print $1}')
check_mysql_container_created=$(docker ps -a | egrep '3306'  | grep "$PROJECT_NAME" | grep "$CONTAINER_MYSQL_NAME" | awk '{print $1}')
check_web_container_up=$(docker ps -a | grep "$PROJECT_NAME" | grep "$CONTAINER_WEB_NAME" | grep Up | awk '{print $1}')
check_web_container_created=$(docker ps -a | grep "$PROJECT_NAME" | grep "$CONTAINER_WEB_NAME" | awk '{print $1}')

# Run devbox
run_option

# Add Tools Alias
addToolsAlias

#final restart
service_restart

#run platform tools
run_platform_tools

# Print project info
print_info

#Unset
unset_env
