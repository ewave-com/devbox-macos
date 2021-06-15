#!/usr/bin/env bash

require_once "${devbox_root}/tools/system/constants.sh"
require_once "${devbox_root}/tools/system/output.sh"

############################ Public functions ############################

function get_docker_container_state() {
  local _container_name=${1-''}

  if [[ -z "$_container_name" ]]; then
    show_error_message "Unable to get docker container state. Container name cannot be empty."
    exit 1
  fi

  local _result
  _result="$(docker ps -a --filter='name=^${_container_name}$' --format='{{.State}}')"

  echo "${_result}"
}

function is_docker_container_running() {
  local _container_name=${1-''}
  local _find_exact_match=${2-'1'}

  if [[ -z "$_container_name" ]]; then
    show_error_message "Unable to check active docker container. Container name cannot be empty."
    exit 1
  fi

  if [[ "${_find_exact_match}" == "1" ]]; then
    _container_name="^${_container_name}$"
  fi

  if [[ ! -z $(docker ps -a --filter="name=${_container_name}" --filter="status=running" --format="{{.Names}}") ]]; then
    echo "1"
  else
    echo "0"
  fi
}

function is_docker_container_exist() {
  local _container_name=${1-''}
  local _find_exact_match=${2-'1'}

  if [[ -z "$_container_name" ]]; then
    show_error_message "Unable to check existing docker container. Container name cannot be empty."
    exit 1
  fi

  if [[ "${_find_exact_match}" == "1" ]]; then
    _container_name="^${_container_name}$"
  fi

  if [[ ! -z $(docker ps -a --filter="name=${_container_name}" --format="{{.Names}}") ]]; then
    echo "1"
  else
    echo "0"
  fi
}

function stop_container_by_name() {
  local _container_name=${1-''}
  local _find_exact_match=${2-'1'}

  if [[ -z "$_container_name" ]]; then
    show_error_message "Unable to stop docker container. Container name cannot be empty."
    exit 1
  fi

  if [[ "${_find_exact_match}" == "1" ]]; then
    _container_name="^${_container_name}$"
  fi

  docker stop $(docker ps -q --filter="name=${_container_name}") --time 10 >/dev/null
}

function kill_container_by_name() {
  local _container_name=${1-''}
  local _signal=${2-"SIGKILL"}
  local _find_exact_match=${3-'1'}

  if [[ -z "${_container_name}" ]]; then
    show_error_message "Unable to kill docker container. Container name cannot be empty."
    exit 1
  fi

  if [[ "${_find_exact_match}" == "1" ]]; then
    _container_name="^${_container_name}$"
  fi

  docker kill $(docker ps -aq --filter="name=${_container_name}") -s ${_signal} >/dev/null
}

function rm_container_by_name() {
  local _container_name=${1-''}
  local _force=${2-"0"}
  local _find_exact_match=${3-'1'}

  if [[ -z "$_container_name" ]]; then
    show_error_message "Unable to remove docker container. Container name cannot be empty."
    exit 1
  fi

  if [[ "${_find_exact_match}" == "1" ]]; then
    _container_name="^${_container_name}$"
  fi

  if [[ "${_force}" == "1" ]]; then
    docker rm $(docker ps -aq --filter="name=${_container_name}") --force >/dev/null 2>&1
  else
    docker rm $(docker ps -aq --filter="name=${_container_name}") >/dev/null 2>&1
  fi
}

function destroy_all_docker_services() {
  [[ -n $(docker ps -q) ]] && docker stop $(docker ps -q)
  [[ -n $(docker ps -q) ]] && docker kill $(docker ps -q)
  [[ -n $(docker ps -aq) ]] && docker rm $(docker ps -aq)
  docker volume prune --force
  docker system prune --force
}

############################ Public functions end ############################
