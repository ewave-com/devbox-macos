#!/usr/bin/env bash
# info: actions with env file

require_once "${devbox_root}/tools/docker/docker.sh"
require_once "${devbox_root}/tools/system/constants.sh"
require_once "${devbox_root}/tools/system/output.sh"
require_once "${devbox_root}/tools/system/file.sh"
require_once "${devbox_root}/tools/system/dotenv.sh"
require_once "${devbox_root}/tools/system/free-port.sh"
require_once "${devbox_root}/tools/project/docker-up-configs.sh"

############################ Public functions ############################

# prepare generated project .env file in docker-up dir and export all variables
function prepare_project_dotenv_variables() {
  local _force=${1-"0"}

  prepare_project_dotenv_file "${_force}"
  dotenv_export_variables "${project_up_dir}/.env"
}

############################ Public functions end ############################

############################ Local functions ############################

# copy project .env file into docker-up dir and prepare it before work
function prepare_project_dotenv_file() {
  local _force=${1-"0"}

  # last docker run was crashed, files may be created as directory
  if [[ -d "${project_up_dir}/.env" ]]; then
    cleanup_project_docker_up_configs
    rm -rf "${project_up_dir}/.env"
  fi

  if [[ ! -f "${project_dir}/.env" ]]; then
    show_error_message "File .ENV not found! Please put configuration file exists at path '${project_dir}/.env' and try again."
    exit 1
  fi

  if [[ -f "${project_up_dir}/.env" && "${_force}" == "0" ]]; then
    return 0
  fi

  mkdir -p "${project_up_dir}"
  cp -r "${project_dir}/.env" "${project_up_dir}/.env"
  echo '' >>"${project_up_dir}/.env"

  replace_file_line_endings "${project_up_dir}/.env"

  current_env_filepath="${project_up_dir}/.env"

  apply_backward_compatibility_transformations "${project_up_dir}/.env"
  merge_defaults "${project_up_dir}/.env"
  add_computed_params "${project_up_dir}/.env"
  evaluate_expression_values "${project_up_dir}/.env"
  add_internal_generated_prams "${project_up_dir}/.env"

  current_env_filepath=""
}

# apply backward compatibility transformations
function apply_backward_compatibility_transformations() {
  local _env_filepath=${1-"${project_up_dir}/.env"}

  # copy value of deprecated WEBSITE_DOCUMENT_ROOT into new params if empty
  if [[ "$(dotenv_has_param 'WEBSITE_DOCUMENT_ROOT')" == "1" && "$(dotenv_get_param_value 'WEBSITE_SOURCES_ROOT')" == "" ]]; then
    dotenv_set_param_value 'WEBSITE_SOURCES_ROOT' "$(dotenv_get_param_value 'WEBSITE_DOCUMENT_ROOT')"
  fi
  if [[ "$(dotenv_has_param 'WEBSITE_DOCUMENT_ROOT')" == "1" && "$(dotenv_get_param_value 'WEBSITE_APPLICATION_ROOT')" == "" ]]; then
    dotenv_set_param_value 'WEBSITE_APPLICATION_ROOT' "$(dotenv_get_param_value 'WEBSITE_DOCUMENT_ROOT')"
  fi

  # append php version to image name for madebyewave image
  local _web_image
  _web_image=$(dotenv_get_param_value 'CONTAINER_WEB_IMAGE')
  local _php_version
  _php_version=$(dotenv_get_param_value 'PHP_VERSION')
  if [[ "${_web_image}" == 'madebyewave/devbox-nginx-php' ]]; then
    dotenv_set_param_value 'CONTAINER_WEB_IMAGE' "${_web_image}${_php_version}"
  fi

  # config params *ELASTIC* were renamed to *ELASTICSEARCH*, copy all params with new names
  if [[ "$(dotenv_has_param 'ELASTIC_ENABLE')" == "1" && "$(dotenv_has_param 'ELASTICSEARCH_ENABLE')" == "0" ]]; then
    dotenv_set_param_value 'ELASTICSEARCH_ENABLE' "$(dotenv_get_param_value 'ELASTIC_ENABLE')"
  fi
  if [[ "$(dotenv_has_param 'CONTAINER_ELASTIC_NAME')" == "1" && "$(dotenv_has_param 'CONTAINER_ELASTICSEARCH_NAME')" == "0" ]]; then
    dotenv_set_param_value 'CONTAINER_ELASTICSEARCH_NAME' "$(dotenv_get_param_value 'CONTAINER_ELASTIC_NAME')"
  fi
  if [[ "$(dotenv_has_param 'CONTAINER_ELASTIC_IMAGE')" == "1" && "$(dotenv_has_param 'CONTAINER_ELASTICSEARCH_IMAGE')" == "0" ]]; then
    dotenv_set_param_value 'CONTAINER_ELASTICSEARCH_IMAGE' "$(dotenv_get_param_value 'CONTAINER_ELASTIC_IMAGE')"
  fi
  if [[ "$(dotenv_has_param 'CONTAINER_ELASTIC_VERSION')" == "1" && "$(dotenv_has_param 'CONTAINER_ELASTICSEARCH_VERSION')" == "0" ]]; then
    dotenv_set_param_value 'CONTAINER_ELASTICSEARCH_VERSION' "$(dotenv_get_param_value 'CONTAINER_ELASTIC_VERSION')"
  fi
  if [[ "$(dotenv_has_param 'CONFIGS_PROVIDER_ELASTIC')" == "1" && "$(dotenv_has_param 'CONFIGS_PROVIDER_ELASTICSEARCH')" == "0" ]]; then
    dotenv_set_param_value 'CONFIGS_PROVIDER_ELASTICSEARCH' "$(dotenv_get_param_value 'CONFIGS_PROVIDER_ELASTIC')"
  fi

  if [[ "$(dotenv_has_param 'CONFIGS_PROVIDER_UNISON')" == "1" && "$(dotenv_get_param_value 'CONFIGS_PROVIDER_WEBSITE_DOCKER_SYNC')" == "" ]]; then
    dotenv_set_param_value 'CONFIGS_PROVIDER_WEBSITE_DOCKER_SYNC' "$(dotenv_get_param_value 'CONFIGS_PROVIDER_UNISON')"
  fi

  # force disable previous unison config as it is replaced with docker-sync
  dotenv_set_param_value 'USE_UNISON_SYNC' "0"
}

# merge existed .env file with project-defaults.env to collect all required parameters
function merge_defaults() {
  local _env_filepath=${1-"${project_up_dir}/.env"}
  if [[ ! -f ${_env_filepath} ]]; then
    show_error_message "Unable to apply .env defaults. Project .env file doesn't exist at path '${_env_filepath}'."
    exit 1
  fi

  printf "\n\n" >>"${_env_filepath}"
  echo "########## Default params ##########" >>"${_env_filepath}"
  printf "# The following params are evaluated or imported from defaults file: '%s'\n" "${dotenv_defaults_filepath}" >>"${_env_filepath}"

  # | sed -e 's/.*=//g'
  for _param_line in $(cat "${dotenv_defaults_filepath}" | grep -Ev "^$" | grep -v '^#'); do
    local _param_name
    _param_name=$(echo "${_param_line}" | awk -F= '{print $1}')

    local _param_presented
    _param_presented=$(dotenv_has_param "${_param_name}" "${_env_filepath}")
    if [[ "${_param_presented}" == "0" ]]; then
      local _param_default_value
      _param_default_value=$(echo "${_param_line}" | awk -F= '{print $2}')
      printf "%s=%s\n" "${_param_name}" "${_param_default_value}" >>"${_env_filepath}"
    fi
  done
}

# check if dynamic ports are available to be exposed, used on simplified start with existing .env
function ensure_exposed_container_ports_are_available() {
  local _env_filepath=${1-"${project_up_dir}/.env"}

  current_env_filepath="${_env_filepath}"

  local _project_name="$(dotenv_get_param_value 'PROJECT_NAME')"

  # ensure mysql external port is available to be exposed or compute a free one
  local _mysql_enable
  _mysql_enable=$(dotenv_get_param_value 'MYSQL_ENABLE')
  if [[ "${_mysql_enable}" == 'yes' ]]; then
    local _configured_mysql_port
    _configured_mysql_port=$(dotenv_get_param_value 'CONTAINER_MYSQL_PORT')
    if [[ -n ${_configured_mysql_port} ]]; then
      local _mysql_container_name="${_project_name}_$(dotenv_get_param_value 'CONTAINER_MYSQL_NAME')"
      ensure_mysql_port_is_available "${_configured_mysql_port}" "${_mysql_container_name}"
    fi
  fi

  # ensure elasticsearch external port is available to be exposed or compute a free one
  local _es_enable
  _es_enable=$(dotenv_get_param_value 'ELASTICSEARCH_ENABLE')
  if [[ "${_es_enable}" == "yes" ]]; then
    local _configured_es_port
    _configured_es_port=$(dotenv_get_param_value 'CONTAINER_ELASTICSEARCH_PORT')
    if [[ -n ${_configured_es_port} ]]; then
      local _es_container_name="${_project_name}_$(dotenv_get_param_value 'CONTAINER_ELASTICSEARCH_NAME')"
      ensure_elasticsearch_port_is_available "${_configured_es_port}" "${_es_container_name}"
    fi
  fi

  # ensure opensearch external port is available to be exposed or compute a free one
  local _opensearch_enable
  _opensearch_enable=$(dotenv_get_param_value 'OPENSEARCH_ENABLE')
  if [[ "${_opensearch_enable}" == "yes" ]]; then
    local _configured_opensearch_port
    _configured_opensearch_port=$(dotenv_get_param_value 'CONTAINER_OPENSEARCH_PORT')
    if [[ -n ${_configured_opensearch_port} ]]; then
      local _opensearch_container_name="${_project_name}_$(dotenv_get_param_value 'CONTAINER_OPENSEARCH_NAME')"
      ensure_opensearch_port_is_available "${_configured_opensearch_port}" "${_opensearch_container_name}"
    fi
  fi    

  # ensure rabbitmq external port is available to be exposed or compute a free one
  local _rabbitmq_enable
  _rabbitmq_enable=$(dotenv_get_param_value 'RABBITMQ_ENABLE')
  if [[ "${_rabbitmq_enable}" == "yes" ]]; then
    local _configured_rabbitmq_port
    _configured_rabbitmq_port=$(dotenv_get_param_value 'CONTAINER_RABBITMQ_PORT')
    if [[ -n ${_configured_rabbitmq_port} ]]; then
      local _rabbitmq_container_name="${_project_name}_$(dotenv_get_param_value 'CONTAINER_RABBITMQ_NAME')"
      ensure_rabbitmq_port_is_available "${_configured_rabbitmq_port}" "${_rabbitmq_container_name}"
    fi
  fi  

  # ensure website ssh external port is available to be exposed or compute a free one
  local _configured_ssh_port
  _configured_ssh_port=$(dotenv_get_param_value 'CONTAINER_WEB_SSH_PORT')
  if [[ -n ${_configured_ssh_port} ]]; then
    local _web_container_name="${_project_name}_$(dotenv_get_param_value 'CONTAINER_WEB_NAME')"
    ensure_website_ssh_port_is_available "${_configured_ssh_port}" "${_web_container_name}"
  fi

  current_env_filepath=""
}

# add comupted params like dynamic ports or hosts
function add_computed_params() {
  local _env_filepath=${1-"${project_up_dir}/.env"}

  local _project_name=$(dotenv_get_param_value 'PROJECT_NAME')

  # ensure mysql external port is available to be exposed or compute a free one
  local _mysql_enable
  _mysql_enable=$(dotenv_get_param_value 'MYSQL_ENABLE')
  if [[ "${_mysql_enable}" == 'yes' ]]; then
    local _mysql_container_name
    _mysql_container_name="${_project_name}_$(dotenv_get_param_value 'CONTAINER_MYSQL_NAME')"
    local _configured_mysql_port
    _configured_mysql_port=$(dotenv_get_param_value 'CONTAINER_MYSQL_PORT')

    if [[ -n ${_configured_mysql_port} ]]; then
      ensure_mysql_port_is_available "${_configured_mysql_port}" "${_mysql_container_name}"
    else
      local _computed_mysql_port
      local _mysql_container_state
      _mysql_container_state=$(get_docker_container_state "${_mysql_container_name}")
      if [[ ! -z "${_mysql_container_state}" ]]; then
        _computed_mysql_port=$(get_mysql_port_from_existing_container "${_mysql_container_name}")
        if [[ "${_mysql_container_state}" != "running" ]]; then
          ensure_mysql_port_is_available "${_computed_mysql_port}" "${_mysql_container_name}"
        fi
      else
        _computed_mysql_port=$(get_available_mysql_port)
      fi

      dotenv_set_param_value 'CONTAINER_MYSQL_PORT' "${_computed_mysql_port}"
    fi
  fi

  # ensure elasticsearch external port is available to be exposed or compute a free one
  local _es_enable
  _es_enable=$(dotenv_get_param_value 'ELASTICSEARCH_ENABLE')
  if [[ "${_es_enable}" == "yes" ]]; then
    local _es_container_name
    _es_container_name="${_project_name}_$(dotenv_get_param_value 'CONTAINER_ELASTICSEARCH_NAME')"
    local _configured_es_port
    _configured_es_port=$(dotenv_get_param_value 'CONTAINER_ELASTICSEARCH_PORT')

    if [[ -n ${_configured_es_port} ]]; then
      ensure_elasticsearch_port_is_available "${_configured_es_port}" "${_es_container_name}"
    else
      local _computed_es_port
      local _es_container_state
      _es_container_state=$(get_docker_container_state "${_es_container_name}")
      if [[ ! -z "${_es_container_state}" ]]; then
        _computed_es_port=$(get_elasticsearch_port_from_existing_container "${_es_container_name}")
        if [[ "${_es_container_state}" != "running" ]]; then
          ensure_elasticsearch_port_is_available "${_computed_es_port}" "${_es_container_name}"
        fi
      else
        _computed_es_port=$(get_available_elasticsearch_port)
      fi

      dotenv_set_param_value 'CONTAINER_ELASTICSEARCH_PORT' "${_computed_es_port}"
    fi
  fi

  # ensure opensearch external port is available to be exposed or compute a free one
  local _opensearch_enable
  _opensearch_enable=$(dotenv_get_param_value 'OPENSEARCH_ENABLE')
  if [[ "${_opensearch_enable}" == "yes" ]]; then
    local _opensearch_container_name
    _opensearch_container_name="${_project_name}_$(dotenv_get_param_value 'CONTAINER_OPENSEARCH_NAME')"
    local _configured_opensearch_port
    _configured_opensearch_port=$(dotenv_get_param_value 'CONTAINER_OPENSEARCH_PORT')

    if [[ -n ${_configured_opensearch_port} ]]; then
      ensure_opensearch_port_is_available "${_configured_opensearch_port}" "${_opensearch_container_name}"
    else
      local _computed_opensearch_port
      local _opensearch_container_state
      _opensearch_container_state=$(get_docker_container_state "${_opensearch_container_name}")
      if [[ ! -z "${_opensearch_container_state}" ]]; then
        _computed_opensearch_port=$(get_opensearch_port_from_existing_container "${_opensearch_container_name}")
        if [[ "${_opensearch_container_state}" != "running" ]]; then
          ensure_opensearch_port_is_available "${_computed_opensearch_port}" "${_opensearch_container_name}"
        fi
      else
        _computed_opensearch_port=$(get_available_opensearch_port)
      fi

      dotenv_set_param_value 'CONTAINER_OPENSEARCH_PORT' "${_computed_opensearch_port}"
    fi
  fi      

  # ensure rabbitmq external port is available to be exposed or compute a free one
  local _rabbitmq_enable
  _rabbitmq_enable=$(dotenv_get_param_value 'RABBITMQ_ENABLE')
  if [[ "${_rabbitmq_enable}" == "yes" ]]; then
    local _rabbitmq_container_name
    _rabbitmq_container_name="${_project_name}_$(dotenv_get_param_value 'CONTAINER_RABBITMQ_NAME')"
    local _configured_rabbitmq_port
    _configured_rabbitmq_port=$(dotenv_get_param_value 'CONTAINER_RABBITMQ_PORT')
    if [[ -n ${_configured_rabbitmq_port} ]]; then
      ensure_rabbitmq_port_is_available "${_configured_rabbitmq_port}" "${_rabbitmq_container_name}"
    else
      local _computed_rabbitmq_port
      local _rabbitmq_container_state
      _rabbitmq_container_state=$(get_docker_container_state "${_rabbitmq_container_name}")
      if [[ ! -z "${_rabbitmq_container_state}" ]]; then
        _computed_rabbitmq_port=$(get_rabbitmq_port_from_existing_container "${_rabbitmq_container_name}")
        if [[ "${_rabbitmq_container_state}" != "running" ]]; then
          ensure_rabbitmq_port_is_available "${_computed_rabbitmq_port}" "${_rabbitmq_container_name}"
        fi
      else
        _computed_rabbitmq_port=$(get_available_rabbitmq_port)
      fi

      dotenv_set_param_value 'CONTAINER_RABBITMQ_PORT' "${_computed_rabbitmq_port}"
    fi
  fi

  # ensure website ssh external port is available to be exposed or compute a free one
  local _web_container_name
  _web_container_name="${_project_name}_$(dotenv_get_param_value 'CONTAINER_WEB_NAME')"
  local _configured_ssh_port
  _configured_ssh_port=$(dotenv_get_param_value 'CONTAINER_WEB_SSH_PORT')
  if [[ -n ${_configured_ssh_port} ]]; then
    ensure_website_ssh_port_is_available "${_configured_ssh_port}" "${_web_container_name}"
  else
    local _computed_ssh_port
    local _web_container_state
    _web_container_state=$(get_docker_container_state "${_web_container_name}")

    if [[ ! -z "${_web_container_state}" ]]; then
      _computed_ssh_port=$(get_website_ssh_port_from_existing_container "${_web_container_name}")
      if [[ "${_es_container_state}" != "running" ]]; then
        ensure_website_ssh_port_is_available "${_computed_ssh_port}" "${_web_container_name}"
      fi
    else
      _computed_ssh_port=$(get_available_website_ssh_port)
    fi

    dotenv_set_param_value 'CONTAINER_WEB_SSH_PORT' "${_computed_ssh_port}"
  fi

  # fill WEBSITE_PHP_XDEBUG_HOST if empty
  local _configured_xdebug_host
  _configured_xdebug_host=$(dotenv_get_param_value 'WEBSITE_PHP_XDEBUG_HOST')
  if [[ -z "${_configured_xdebug_host}" ]]; then
    local _computed_xdebug_host
    if [[ "${os_type}" == "macos" ]]; then
      local _computed_xdebug_host="host.docker.internal"
    elif [[ "${os_type}" == "linux" ]]; then
      _computed_xdebug_host=$(ip addr show docker0 | grep -Po 'inet \K[\d.]+')
      if [[ -z "${_computed_xdebug_host}" ]]; then
        _computed_xdebug_host='172.17.0.1' # common internal docker ip
      fi
    fi
    dotenv_set_param_value 'WEBSITE_PHP_XDEBUG_HOST' "${_computed_xdebug_host}"
  fi

  # set OS mysql docker-sync type if 'default' chosen
  local _mysql_docker_sync_provider
  _mysql_docker_sync_provider=$(dotenv_get_param_value 'CONFIGS_PROVIDER_MYSQL_DOCKER_SYNC')
  if [[ "${_mysql_docker_sync_provider}" == "default" ]]; then
    if [[ "${os_type}" == "macos" ]]; then
      _mysql_docker_sync_provider="native"
    elif [[ "${os_type}" == "linux" ]]; then
      _mysql_docker_sync_provider="native"
    fi
    dotenv_set_param_value 'CONFIGS_PROVIDER_MYSQL_DOCKER_SYNC' "${_mysql_docker_sync_provider}"
  fi

  # set OS elasticsearch docker-sync type if 'default' chosen
  local _es_docker_sync_provider
  _es_docker_sync_provider=$(dotenv_get_param_value 'CONFIGS_PROVIDER_ELASTICSEARCH_DOCKER_SYNC')
  if [[ "${_es_docker_sync_provider}" == "default" ]]; then
    if [[ "${os_type}" == "macos" ]]; then
      _es_docker_sync_provider="native"
    elif [[ "${os_type}" == "linux" ]]; then
      _es_docker_sync_provider="native"
    fi
    dotenv_set_param_value 'CONFIGS_PROVIDER_ELASTICSEARCH_DOCKER_SYNC' "${_es_docker_sync_provider}"
  fi

  # set OS opensearch docker-sync type if 'default' chosen
  local _opensearch_docker_sync_provider
  _opensearch_docker_sync_provider=$(dotenv_get_param_value 'CONFIGS_PROVIDER_OPENSEARCH_DOCKER_SYNC')
  if [[ "${_opensearch_docker_sync_provider}" == "default" ]]; then
    if [[ "${os_type}" == "macos" ]]; then
      _opensearch_docker_sync_provider="native"
    elif [[ "${os_type}" == "linux" ]]; then
      _opensearch_docker_sync_provider="native"
    fi
    dotenv_set_param_value 'CONFIGS_PROVIDER_OPENSEARCH_DOCKER_SYNC' "${_opensearch_docker_sync_provider}"
  fi
}

# add static dir paths required for docker-sync mounting
function add_internal_generated_prams() {
  local _env_filepath=${1-"${project_up_dir}/.env"}

  if [[ -z "$(dotenv_get_param_value 'DEVBOX_PROJECT_DIR')" ]]; then
    dotenv_set_param_value 'DEVBOX_PROJECT_DIR' "${project_dir}"
  fi

  if [[ -z "$(dotenv_get_param_value 'DEVBOX_PROJECT_UP_DIR')" ]]; then
    dotenv_set_param_value 'DEVBOX_PROJECT_UP_DIR' "${project_up_dir}"
  fi

  if [[ -z "$(dotenv_get_param_value 'COMPOSER_CACHE_DIR')" ]]; then
    _composer_cache_dir=''
    if [[ "$(dotenv_get_param_value 'CONFIGS_PROVIDER_COMPOSER_CACHE_DOCKER_SYNC')" == "global" ]]; then
      _composer_cache_dir=$(composer config --global cache-dir 2>/dev/null)
    elif [[ "$(dotenv_get_param_value 'CONFIGS_PROVIDER_COMPOSER_CACHE_DOCKER_SYNC')" == "local" ]]; then
      _composer_cache_dir="${project_dir}/sysdumps/composer/"
    fi

    dotenv_set_param_value 'COMPOSER_CACHE_DIR' "${_composer_cache_dir}"
  fi

  # evaluate relative app path inside sources root to configure sync properly
  if [[ -z "$(dotenv_get_param_value 'APP_REL_PATH')" ]]; then
    if [[ "$(dotenv_get_param_value 'WEBSITE_SOURCES_ROOT')" != "$(dotenv_get_param_value 'WEBSITE_APPLICATION_ROOT')" ]]; then
      local _app_relative_path
      _sources_root="$(dotenv_get_param_value 'WEBSITE_SOURCES_ROOT')"
      _app_root="$(dotenv_get_param_value 'WEBSITE_APPLICATION_ROOT')"
      _app_relative_path=$(echo "${_app_root}" | sed "s|${_sources_root}||" | sed "s|^/||" | sed "s|/$||")

      if [[ -n "${_app_relative_path}" ]]; then
        dotenv_set_param_value 'APP_REL_PATH' "${_app_relative_path}/"
      fi
    fi
  fi

  # evaluate relative node_modules path inside sources root to configure sync properly
  if [[ -z "$(dotenv_get_param_value 'NODE_MODULES_REL_PATH')" ]]; then
    if [[ -n "$(dotenv_get_param_value 'WEBSITE_NODE_MODULES_ROOT')" ]]; then
      local _node_modules_relative_path
      _sources_root="$(dotenv_get_param_value 'WEBSITE_SOURCES_ROOT')"
      _node_modules_root="$(dotenv_get_param_value 'WEBSITE_NODE_MODULES_ROOT')"
      _node_modules_relative_path=$(echo "${_node_modules_root}" | sed "s|${_sources_root}||" | sed "s|^/||" | sed "s|/$||")

      if [[ -n "${_node_modules_relative_path}" ]]; then
        dotenv_set_param_value 'NODE_MODULES_REL_PATH' "${_node_modules_relative_path}/"
      fi
    fi
  fi

  # define used docker-sync docker image for unison
  if [[ -z "$(dotenv_get_param_value 'DOCKER_SYNC_UNISON_IMAGE')" ]]; then
    if [[ ${arch_type} == 'arm64' ]]; then
      dotenv_set_param_value 'DOCKER_SYNC_UNISON_IMAGE' "madebyewave/unison:2.51.3-4.12.0"
    else
      dotenv_set_param_value 'DOCKER_SYNC_UNISON_IMAGE' "madebyewave/unison:2.51.3-4.12.0"
    fi
  fi
}

# evaluate .env param value expressions, for example 'PARAM_1=${PARAM_2}_$PARAM_3' will be evaluated based on PARAM_2 and PARAM_3 from same file
function evaluate_expression_values() {
  local _env_filepath=${1-"${project_up_dir}/.env"}
  # find all variables with $ which should be expanded
  for _param_line in $(cat "${_env_filepath}" | grep -Ev "^$" | grep -v '^#' | grep '\$'); do
    local _param_value=$(echo "${_param_line}" | awk -F'=' '{ print $2 }')
    local _evaluated_param_value="${_param_value}"
    # if value has patterns "${_some_word_}" it should be evaluated
    if [[ $(echo "${_param_value}" | grep -E '\$\{?[A-Za-z0-9_-]*\}?') ]]; then
      for _param_pattern in $(echo "${_param_value}" | grep -oE '\$\{?([A-Za-z0-9_-]*)\}?'); do
        _eval_param_name=$(echo "${_param_pattern}" | tr -d '${}')
        local _evaluated_value=$(dotenv_get_param_value "${_eval_param_name}")
        _evaluated_param_value=$(echo "${_evaluated_param_value}" | sed "s|${_param_pattern}|${_evaluated_value}|g")
      done
    fi

    if [[ "${_evaluated_param_value}" != "${_param_value}" ]]; then
      local _param_name=$(echo "${_param_line}" | awk -F'=' '{ print $1 }')
      dotenv_set_param_value "${_param_name}" "${_evaluated_param_value}"
    fi
  done
}

############################ Local functions end ############################
