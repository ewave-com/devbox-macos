#!/usr/bin/env bash

### List of functions ###
docker_compose_log_level=ERROR
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

# Function for scan directory
list_projects(){
echo "----------------------------------------------"
echo -e " * * * * * * * $GREEN Check project $SET * * * * * * * * "
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

# Set variable  from file .env
set_env(){
export $(grep -v '^#' ./projects/$project_folder/.env | xargs)
}

# Unset variable  from file .env
unset_env(){
unset $(cat ./projects/$project_folder/.env | grep -Ev "^$"  | grep -v '^#' | sed -E 's/(.*)=.*/\1/' | xargs)
}

stop_project(){
# Stop all additionals images
for additional_images_yml in $(ls ./projects/$project_folder/ | grep .yml | awk '{ print $1 }' | grep -v docker-compose.yml);
do
cd ./projects/$project_folder/ && sudo docker-compose --log-level "$docker_compose_log_level"  -f $additional_images_yml stop > /dev/null 2>&1 && cd ../../
done

# Always delete nginx conf with unavaible proxy pass
if [[ -f ./configs/env/nginx/conf.d/"$WEBSITE_HOST_NAME".conf ]] ; then
rm -rf ./configs/env/nginx/conf.d/"$WEBSITE_HOST_NAME".conf 
fi
# Reload nginx after delete website
sudo docker exec -ti nginx-reverse-proxy bash -c "service nginx restart"

#Check file and run step if file exist
###
if [ -f ./projects/$project_folder/docker-compose.yml ] ; then
  cd ./projects/$project_folder/ && sudo docker-compose stop && cd ../../
else
  echo -e  "-------------------------------------------$GREEN SKIP $SET-------------------------------------------------"
  echo -e  "Project $WEBSITE_HOST_NAME is already turned off. Docker-compose.yml in folder $project_folder not found"
  echo -e  "--------------------------------------------------------------------------------------------------\n"
fi

sudo rm -rf /usr/local/share/ca-certificates/$WEBSITE_HOST_NAME.crt >/dev/null 2>&1;
sudo update-ca-certificates --fresh > /dev/null 2>&1

sudo -- sh -c -e "cat /etc/hosts | grep $WEBSITE_HOST_NAME | xargs -0  sed -i '' '/$server_ip $WEBSITE_HOST_NAME/d' /etc/hosts"  >/dev/null 2>&1 ;
echo -e  "--------------------- $GREEN DELETE VHOST FROM HOSTS $SET------------------------"
echo -e "$GREEN Website:$SET http://$WEBSITE_HOST_NAME  was delete form file /etc/hosts"
echo -e  "-----------------------------------------------------------------------\n"
}

stop_all_projects(){
for project_folder in $( ls -Al projects/ | grep "^d" | awk -F" " '{print $9}' );
do
set_env ; stop_project ; unset_env
done

# Stop all env images
for env_images_yml in $(ls ./configs/env/ | grep .yml | awk '{ print $1 }' | grep -v docker-compose.yml);
do
cd ./configs/env/ && sudo docker-compose --log-level "$docker_compose_log_level" -f $env_images_yml down ; cd ../../
done


echo -e "---------------------------$GREEN ENV $SET--------------------------------"
echo -e "$GREEN Containers $SET [NGINX-REVERSE-PROXY, PORTAINER, MAILHOG] were off "
echo -e "----------------------------------------------------------------\n" 
}

kill_project(){
echo ================================
echo Copying DB Files to host machine

check_mysql_container=$(docker ps -a | egrep '3306'  | grep "$PROJECT_NAME" | grep "$CONTAINER_MYSQL_NAME" | grep Up | awk '{print $1}')
if [[ -z "$check_mysql_container" ]]; then
  docker start "$PROJECT_NAME"_"$CONTAINER_MYSQL_NAME"
  sleep 10;
  docker cp "$PROJECT_NAME"_$CONTAINER_MYSQL_NAME:/var/lib/mysql/ ./projects/$project_folder/db/.
else
  docker cp "$PROJECT_NAME"_$CONTAINER_MYSQL_NAME:/var/lib/mysql/ ./projects/$project_folder/db/.
fi
echo ================================

# Stop all additionals images
for additional_images_yml in $(ls ./projects/$project_folder/ | grep .yml | awk '{ print $1 }' | grep -v docker-compose.yml);
do
cd ./projects/$project_folder/ && sudo docker-compose --log-level "$docker_compose_log_level" -f $additional_images_yml down ; rm -rf $additional_images_yml > /dev/null 2>&1  ; cd ../../
done

if [[ -f ./configs/env/nginx/conf.d/"$WEBSITE_HOST_NAME".conf ]] ; then
rm -rf ./configs/env/nginx/conf.d/"$WEBSITE_HOST_NAME".conf 
fi

#Check file and run step if file exist
###
if [ -f ./projects/$project_folder/docker-compose.yml ] ; then
  cd ./projects/$project_folder/ && sudo docker-compose down && rm -rf docker-compose.yml && cd ../../
else
  echo -e  "-------------------------------------------$GREEN SKIP $SET-------------------------------------------------"
  echo -e  "Project $WEBSITE_HOST_NAME is already turned off. Docker-compose.yml in folder $project_folder not found"
  echo -e  "--------------------------------------------------------------------------------------------------\n"
fi
###
sudo rm -rf /usr/local/share/ca-certificates/$WEBSITE_HOST_NAME.crt >/dev/null 2>&1;
sudo update-ca-certificates --fresh > /dev/null 2>&1

sudo -- sh -c -e "cat /etc/hosts | grep $WEBSITE_HOST_NAME | xargs -0  sed -i '' '/$server_ip $WEBSITE_HOST_NAME/d' /etc/hosts"  >/dev/null 2>&1 ;
echo -e  "--------------------- $GREEN DELETE VHOST FROM HOSTS $SET------------------------"
echo -e "$GREEN Website:$SET http://$WEBSITE_HOST_NAME  was delete form file /etc/hosts"
echo -e  "-----------------------------------------------------------------------\n"
}

# Function for stop all containers [included function stop_project]
kill_all_projects(){
for project_folder in $( ls -Al projects/ | grep "^d" | awk -F" " '{print $9}' );
do
set_env ; kill_project ; unset_env
done

# Stop all env images
for env_images_yml in $(ls ./configs/env/ | grep .yml | awk '{ print $1 }' | grep -v docker-compose.yml);
do
cd ./configs/env/ && sudo docker-compose --log-level "$docker_compose_log_level" -f $env_images_yml down ; cd ../../
done

echo -e "---------------------------$GREEN ENV $SET--------------------------------"
echo -e "$GREEN Containers $SET [NGINX-REVERSE-PROXY, PORTAINER, MAILHOG] were off "
echo -e "----------------------------------------------------------------\n"
}

stop_menu(){
while :
  do
  echo "----------------------------------------------"
  echo -e " * * * * * * * * $GREEN Stop menu $SET * * * * * * * * * "
  echo "----------------------------------------------"

  echo "[1] Kill ONE project (Project's containers will be delete. [You need to sync files first])"
  echo "[2] Kill ALL projects (All containers will be delete. [You need to sync files first])"
  echo "[3] Stop ONE project (Project's containers will be STOP. [You didn't need to sync files first])"
  echo "[4] Stop ALL projects (All containers will be STOP. [You didn't need to sync files first])"
  echo "[0] Exit/stop"
  echo "----------------------------------------------"
  echo -n "Enter your menu choice [1,2 or 0]:"
  read point
  case $point in
    1) list_projects  ; set_env ; kill_project ; unset_env ;  break ;;
    2) kill_all_projects ; break ;;
    3) list_projects  ; set_env ; stop_project ; unset_env ;  break ;;
    4) stop_all_projects ; break ;;
    0) exit 0 ;;
 #   *) echo "Opps!!! Please select choice 1,2, or 0"
 #      echo "Press a key. . ."
 #      read -n 1
 #      ;;
   esac
done
}

#  Total: Run only one function
stop_menu
