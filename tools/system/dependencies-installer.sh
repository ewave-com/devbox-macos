#!/usr/bin/env bash

require_once "${devbox_root}/tools/system/constants.sh"
require_once "${devbox_root}/tools/system/output.sh"

############################ Public functions ############################

function install_dependencies() {
  install_docker
  install_docker_sync
  install_unison
  install_git
  install_composer
  install_extra_packages
  register_devbox_scripts_globally
}

############################ Public functions end ############################

############################ Local functions ############################

# Check and install docker
# If docker don't install, script will setup it.
function install_docker() {
  local _docker_location=$(which docker)
  if [[ -n "$(which docker-compose)" ]]; then
    local _compose_version="$(docker-compose --version | cut -d " " -f 3 | cut -d "," -f 1)"
    _compose_min_version="1.25.0"
    # --env-file available since docker-compose 1.25.
    # https://stackoverflow.com/questions/40525230/specify-the-env-file-docker-compose-uses
    if [[ "$(printf '%s\n' "${_compose_min_version}" "${_compose_version}" | sort -V | head -n1)" != "${_compose_min_version}" ]]; then
      show_warning_message "You are running docker-compose version ${_compose_version}. DevBox requires version ${_compose_min_version} or higher."
      show_warning_message "Docker and docker-compose will be tried to be updated automatically or you can reinstall Docker manually. This is one-time operation."

      #      $reply = Read-Host -Prompt "Update Docker automatically?[y/n]"
      #      if ($reply -notmatch "[yY]") {
      #          show_warning_message "You selected manual Docker installation. Exited"
      #          Exit 1
      #      }
      osascript -e 'quit app "Docker"'
      sudo rm -rf "/Applications/Docker.app"
      brew uninstall --cask docker
      _docker_location=""
    fi
  fi

  if [ -z "${_docker_location}" ]; then
    if [[ -z "$(ls -l /Applications | grep Docker.app)" ]]; then
      brew install --cask docker

      # Mac only related issue, "UnixHTTPConnectionPool(host='localhost', port=None): Read timed out"
      # https://github.com/docker/for-mac/issues/4957
      show_warning_message "After installation strongly recommended to disable the setting \"Use gRPC FUSE for file sharing\" in Experimental Features of Docker Settings."
    fi

    if [[ ! -z "$(ls -l /Applications | grep Docker.app)" ]]; then
      open "/Applications/Docker.app"
    else
      show_error_message "Unable to run docker application. Dmg image not found at path /Applications/Docker.app"
      show_error_message "Please install in and run manually"
      show_error_message "https://download.docker.com/mac/stable/Docker.dmg"
    fi
  fi

# group docker does not exist for mac os, you should ensure socket target path behind symlink '/var/run/docker.sock' is executable
# /Users/user/Library/Containers/com.docker.docker/Data/docker.sock
#  if [[ -z $(echo "$(groups)" | grep "docker") ]]; then
#    sudo usermod -a -G docker "${host_user}"
#  fi
}

# Check and install unison, for mac only, not required for linux
function install_unison() {
  if [[ "${os_type}" == "macos" ]]; then
    if [ -z "$(which unison)" ]; then
      if [ -z "$(which brew)" ]; then
        #The Ruby Homebrew installer is now deprecated and has been rewritten in Bash
        #ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)" < /dev/null 2> /dev/null
        bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      fi

      brew install python
      brew install unison
      brew install eugenmayer/dockersync/unox
      brew install autozimu/homebrew-formulas/unison-fsmonitor
      sudo easy_install pip
      sudo pip install macfsevents
    fi
  fi
}

function install_docker_sync() {
  if [[ -z "$(which ruby)" || -z "$(which gem)" ]]; then
    brew install ruby ruby-dev >/dev/null
  fi

  if [[ -z "$(which docker-sync)" ]]; then
    sudo gem install docker-sync --quiet >/dev/null

    _docker_sync_lib_sources_dir="$(dirname "$(gem which docker-sync)")"
    sudo cp -f "${devbox_root}/tools/bin/docker-sync/lib/docker-sync/sync_strategy/unison.rb" "${_docker_sync_lib_sources_dir}/docker-sync/sync_strategy/unison.rb"
  fi
}

function install_git() {
  if [[ -z "$(which git)" ]]; then
    brew install git >/dev/null
  fi
}

# Check and install composer
function install_composer() {
  function run_composer_installer() {
    # https://getcomposer.org/doc/faqs/how-to-install-composer-programmatically.md
    composer_expected_checksum="$(curl https://composer.github.io/installer.sig)"
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    composer_actual_checksum="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

    if [ "${composer_expected_checksum}" != "${composer_actual_checksum}" ]; then
      echo >&2 'ERROR: Invalid composer installer checksum'
      rm composer-setup.php
      exit 1
    fi

    sudo php composer-setup.php --install-dir=/usr/local/bin --filename=composer --quiet >/dev/null
    RESULT=$?
    rm composer-setup.php
    return $RESULT
  }

  if [ -z "$(which composer)" ]; then
    run_composer_installer
  fi

  local _composer_output=''
  if [[ ! -f "${devbox_root}/composer.lock" ]]; then
    show_success_message "Running initial composer install command."
    # locally catch the possible composer error without application stopping
    set +e && _composer_output=$(COMPOSER="${devbox_root}/composer.json" composer install --quiet) && set -e
  elif [[ "${composer_autoupdate}" == "1" && -n $(find "${devbox_root}/composer.lock" -mmin +604800) ]]; then
    show_success_message "Running composer update command to refresh packages. Last run is a week ago. Please wait a few seconds"
    set +e && _composer_output=$(COMPOSER="${devbox_root}/composer.json" composer update --quiet) && set -e
  fi

  if [[ $(echo ${_composer_output} | grep "Fatal error") ]]; then
    # PHP 8.0+ Compatibility fix, the following error or similar might occur during 'composer install' command.
    # PHP Fatal error:  Uncaught ArgumentCountError: array_merge() does not accept unknown named parameters in /usr/share/php/Composer/DependencyResolver/DefaultPolicy.php:84
    # "composer selfupdate" is errored as well. So we need to completely reinstall composer.
    show_warning_message "An error occurred during \"composer install\" operation."
    show_warning_message "This might be caused you are using PHP 8.0+ on the host system. We will try to update composer version to fix the errors."
    brew install composer composer >/dev/null
    run_composer_installer
  fi
  
  return 0
}

function install_extra_packages() {
  if [[ -z "$(which openssl)" ]]; then
    brew install openssl
  fi

  if [[ -z "$(which gfind)" || -z "$(which realpath)" ]]; then
    brew install coreutils findutils
  fi
}

function register_devbox_scripts_globally() {
  sudo chmod ug+x "${devbox_root}/start-devbox.sh"
  sudo chmod ug+x "${devbox_root}/down-devbox.sh"
  sudo chmod ug+x "${devbox_root}/sync-actions.sh"

  if [[ -z $(echo "${PATH}" | grep "${devbox_root}" ) ]]; then
    echo -en '\n' >> ~/.bashrc
    echo "export PATH='${PATH}:${devbox_root}'" >> ~/.bashrc

    export PATH="${PATH}:${devbox_root}"
  fi
}

############################ Local functions end ############################
