#!/usr/bin/env bash

require_once "${devbox_root}/tools/system/constants.sh"
require_once "${devbox_root}/tools/system/output.sh"

############################ Public functions ############################

export devbox_env_path_updated="0"

function install_dependencies() {
  show_success_message "Validating software dependencies"

  install_brew
  install_docker
  install_docker_sync
  install_unison
  install_git
  install_composer
  install_extra_packages
  register_devbox_scripts_globally

  if [[ "${devbox_env_path_updated}" == "1" ]]; then
    show_warning_message "###########################################################################################"
    show_success_message "Installed packages updated your PATH system variable."
    show_warning_message "!!! To apply changes please close this window and start again using new console window !!!."
    show_warning_message "###########################################################################################"
    unset_flag_terminal_restart_required
    exit
  fi
  unset_flag_terminal_restart_required
}

############################ Public functions end ############################

############################ Local functions ############################

function install_brew() {
  if [[ -z "$(which brew)" ]]; then
      #The Ruby Homebrew installer is now deprecated and has been rewritten in Bash
      bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      #ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)" < /dev/null 2> /dev/null
  fi
}

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
      show_warning_message "###########################################################################################"
      show_warning_message "After installation strongly recommended to disable the setting \"Use gRPC FUSE for file sharing\" in Experimental Features of Docker Settings."
      show_warning_message "###########################################################################################"
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
  if [ -z "$(which unison)" ]; then

    if [ -z "$(which python)" ]; then
      brew install python >/dev/null
    fi
    brew install unison >/dev/null
    brew install eugenmayer/dockersync/unox  >/dev/null
    brew install autozimu/homebrew-formulas/unison-fsmonitor  >/dev/null
    sudo easy_install pip  >/dev/null
    sudo pip install macfsevents  >/dev/null
  fi

  # replace unison binary with corresponding version of Ocaml
  # otherwise unison fails because brew repo version has been updated using another OCaml
  # todo find another approach, probably by adding 'host-bin' dir to PATH
  # used the release 2.51.3 compiled with OCaml 4.12.0
  # https://github.com/bcpierce00/unison/releases/tag/v2.51.3

  _unison_target_version="unison version 2.51.3 (ocaml 4.12.0)"
  if [[ "$(unison -version)" != "${_unison_target_version}" ]]; then
    # replace system unison binary
    [[ -n "$(which realpath)" ]] && _unison_system_bin="$(realpath $(which unison))" || _unison_system_bin="$(which unison)"
    sudo cp -f "${devbox_root}/tools/bin/host-bin/unison" "${_unison_system_bin}"
    sudo chown "${host_user}":"${host_user_group}" "${_unison_system_bin}"
    sudo chmod 555 "${_unison_system_bin}"

    # lock current version to avoid auto-updating
    brew pin unison
  fi
}

function install_docker_sync() {
  if [[ -z "$(which ruby)" || -z "$(which gem)" || -z $(echo "$(ruby -v)" | grep -E "^ruby\ 2\.") ]]; then
    # ruby@2.7 required, otherwise (ruby 3.0+) very old docker-sync (like 0.1) is installed from repos instead of needed 0.5.14+
    brew install ruby@2.7 ruby-dev >/dev/null

    # lock current version
    brew pin ruby

    set_flag_terminal_restart_required
  fi

  if [[ -z "$(which docker-sync)" ]]; then
    sudo gem install docker-sync -v 0.6 --quiet >/dev/null

    set_flag_terminal_restart_required
  fi

  # sync one of docker-sync files with patched version
  _docker_sync_lib_sources_dir="$(dirname "$(gem which docker-sync)")"
  _target_chsum=$(md5 -q "${_docker_sync_lib_sources_dir}/docker-sync/sync_strategy/unison.rb")
  _source_chsum=$(md5 -q "${devbox_root}/tools/bin/docker-sync/lib/docker-sync/sync_strategy/unison.rb")
  if [[ "${_target_chsum}" != "${_source_chsum}" ]]; then
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

  local _composer_version=''
  if [[ -n "$(which composer)" ]]; then
    _composer_version=$(echo "$(composer --no-plugins --version)" | grep -o -m 1 -E "^Composer version ([0-9.]+) " | sed 's/Composer version //' | tr -d ' ')
    _major_version="${_composer_version:0:1}"

    if [[ "${_major_version}" == "1" && ! "$(printf '%s\n' "1.10.21" "${_compose_version}" | sort -V | head -n1)" == "1.10.21" ]]; then
      show_success_message "Your composer will be updated to the latest version"
      brew uninstall composer >/dev/null
      _composer_version=''
    elif [[ "${_major_version}" == "2" && ! "$(printf '%s\n' "2.0.12" "${_compose_version}" | sort -V | head -n1)" == "2.0.12" ]]; then
      show_success_message "Your composer will be updated to the latest version"
      brew uninstall composer >/dev/null
      _composer_version=''
    fi
  fi

  if [ -z "${_composer_version}" ]; then
    run_composer_installer

    set_flag_terminal_restart_required
  fi

  local _composer_output=''
  if [[ ! -f "${devbox_root}/composer.lock" ]]; then
    show_success_message "Running initial composer install command."
    # locally catch the possible composer error without application stopping
    set +e && _composer_output=$(COMPOSER="${devbox_root}/composer.json" composer install --quiet) && set -e
  elif [[ "${composer_autoupdate}" == "1" && -n $(find "${devbox_root}/composer.lock" -mmin +604800) ]]; then
    show_success_message "Running composer update command to refresh packages. Last run was performed a week ago. Please wait a few seconds"
    set +e && _composer_output=$(COMPOSER="${devbox_root}/composer.json" composer update --quiet) && set -e
  fi

  if [[ $(echo ${_composer_output} | grep "Fatal error") ]]; then
    # PHP 8.0+ Compatibility fix, the following error or similar might occur during 'composer install' command.
    # PHP Fatal error:  Uncaught ArgumentCountError: array_merge() does not accept unknown named parameters in /usr/share/php/Composer/DependencyResolver/DefaultPolicy.php:84
    # "composer selfupdate" is errored as well. So we need to completely reinstall composer.
    show_warning_message "An error occurred during \"composer install\" operation."
    show_warning_message "This might be caused you are using PHP 8.0+ on the host system. We will try to update composer version to fix the errors."
    brew uninstall composer >/dev/null
    run_composer_installer
  fi

  return 0
}

function install_extra_packages() {
  if [[ -z "$(which openssl)" ]]; then
    brew install openssl >/dev/null
  fi

  if [[ -z "$(which gfind)" || -z "$(which realpath)" ]]; then
    brew install coreutils findutils >/dev/null
  fi
}

function register_devbox_scripts_globally() {
  sudo chmod ug+x "${devbox_root}/start-devbox.sh"
  sudo chmod ug+x "${devbox_root}/down-devbox.sh"
  sudo chmod ug+x "${devbox_root}/sync-actions.sh"

  add_directory_to_env_path "${devbox_root}"
}

function add_directory_to_env_path() {
  local _bin_dir=${1-''}

  if [[ -z "${_bin_dir}" || ! -d "${_bin_dir}" ]]; then
    show_error_message "Unable to update system PATH. Path to binaries is empty or does not exist '${_bin_dir}'."
  fi

  # add new binaries path to env variables of current shell
  if [[ -z $(echo "${PATH}" | grep "${_bin_dir}" ) ]]; then
    export PATH="${PATH}:${_bin_dir}"

    set_flag_terminal_restart_required
  fi

  # save new binaries path to permanent user env variables storage to avoid cleaning
  if [[ -z $(cat ~/.bash_profile | grep "export PATH=" | grep "${_bin_dir}") ]]; then
    printf '\n# Devbox Path \n' >> ~/.bash_profile
    echo 'export PATH="${PATH}:'${_bin_dir}'"' >> ~/.bash_profile

    set_flag_terminal_restart_required
  fi
}

function set_flag_terminal_restart_required() {
  export devbox_env_path_updated="1"
  exit
}

function unset_flag_terminal_restart_required() {
  unset devbox_env_path_updated
}

############################ Local functions end ############################
