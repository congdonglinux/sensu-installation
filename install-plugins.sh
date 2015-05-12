# !/bin/bash

source bash-common-functions.sh
 
# Constants
sensu_embedded_ruby="/opt/sensu/embedded/bin"
taobao_gem_mirror="https://ruby.taobao.org/"

sensu_conf_dir="/etc/sensu"
handler_scripts_dir="/etc/sensu/handlers"
check_scripts_dir="/etc/sensu/plugins"
plugin_def_dir="/etc/sensu/conf.d"

# Variables
plugin_type=""
plugin_name=""
plugin_url=""
plugin_args=""
script_path=""

function set_ruby_env() {
    sed -i "/EMBEDDED_RUBY=/s/false/true/" /etc/default/sensu
    if [[ ! $PATH == *"$sensu_embedded_ruby"* ]]; then
        cat > /etc/profile.d/sensu-ruby-env.sh <<EOF
export PATH=$sensu_embedded_ruby:$PATH
EOF
    fi
}

function tweak_gem_source() {
    local official_gem_source="$(gem sources -l | tail -1)"
    # echo $official_gem_source
    if [[ ! $official_gem_source = $taobao_gem_mirror ]]; then
        gem sources --remove "$official_gem_source"
        gem sources -a $taobao_gem_mirror
        # gem sources -l
    fi
}

function get_plugin() {
    local plugin_url=$1

    echo $plugin_url

    # for file in $plugin_list; do
        local plugin_category="$(echo "$plugin_url" | awk -F "/" '{print $(NF-1)}')"
        echo $plugin_category

        if [[ $plugin_category = "plugins" ]] || [[ $plugins_category = "handlers" ]]; then
            plugin_category=""
            _plugin_type=$plugin_category
        else
            _plugin_type="$(echo "$plugin_url" | awk -F "/" '{print $(NF-2)}')"
        fi

        echo $_plugin_type

        if [[ $_plugin_type = "plugins" ]] && [[ ! $plugin_type = "check" ]]; then
            error 'this plugin is not a check, please verify'
            exit 1
        fi

        if [[ $_plugin_type = "handlers" ]] && [[ ! $plugin_type = "handler" ]]; then
            error 'this plugin is not a handler, please verify'
            exit 1
        fi

        local script_name="$(echo "$plugin_url" | awk -F "/" '{print $NF}')"
        echo $script_name
#        if [[ -f ${plugins_cache_dir}$script_name ]]; then
#            rm -f ${plugins_cache_dir}$script_name
#        fi

        if [[ $(is_empty_string "${plugin_category}") = 'true' ]]; then
            script_path="${sensu_conf_dir}/${_plugin_type}/${plugin_category}/${script_name}"
        else
            script_path="${sensu_conf_dir}/${_plugin_type}/${script_name}"
        fi

        echo $script_path

        wget -O $script_path $plugin_url
        # if there is a json configuration file, just download it too!

        if [[ ! $? == 0 ]]; then
            error "download $script_name failed, please check url"
        fi

        chmod 755 ${script_path}
    # done
}

function resolve_deps() {
    local plugin_name=$1
    grep -E "^require '.*'$" $plugin_name | while read -r line; do
        # local gem="$(echo $line | grep -o -E '\'.*\'')"
        local gem=$(echo $line | sed -e "s/'//g" -e "s/require//" | awk -F "/" '{print $1}')
        # echo $gem
        echo "Installing $gem ..."
        gem install $gem
    done
}

function config_plugin() {
    cat > check.sample <<EOF
{
  "checks": {
    "$plugin_name": {
      "handlers": [ "$handlers" ],
      "command": "$check_plugin $args",
      "interval": $interval,
      "subscribers": [ "$subscribers" ]
    }
  }
}
EOF

    cat > handler.sample <<EOF
{
  "handlers": {
    "$plugin_name": {
      "type": "pipe",
      "command": "$plugin_path $plugin_args"
    }
  } 
} 
EOF
}

function display_usage() {
    local script_name="$(basename "${BASH_SOURCE[0]}")"
    
    echo -e "\033[1;33m"
    echo    "SYNOPSIS :"
    echo    "    ${script_name} --type {handler | check} --name <name> --url <url_to_plugin_script>"
    echo -e "DESCRIPTION :"
    echo    "    --type    is this plugin a handler or a check, available value: handler, check"
    echo    "    --name    what will this plugin be called?"
    echo    "    --url     URL to this plugin on GitHub. For example, https://raw.githubusercontent.com/sensu/sensu-community-plugins/master/plugins/processes/check-procs.rb"
    echo    "    --args    arguments for this plugin to run, a string. For example, \"-p crond -C 1\""
    echo -e "\033[0m"

    exit ${1}
}

function main() {
    set_ruby_env

    tweak_gem_source

    working_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    source "${working_dir}/util.sh" || exit 1
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help)
                display_usage 0
            
                ;;

            --type)
                shift

                if [[ $# -gt 0 ]]; then
                    plugin_type="$(trim_string "${1}")"
                fi
                ;;
            --name)
                shift

                if [[ $# -gt 0 ]]; then
                    plugin_name="$(trim_string "${1}")"
                fi
                ;;
            --url)
                shift

                if [[ $# -gt 0 ]]; then
                    plugin_url="$(trim_string "${1}")"
                fi
                ;;
            --args)
                shift

                if [[ $# -gt 0 ]]; then
                    plugin_args="$(trim_string "${1}")"
                fi
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ "$(is_empty_string ${plugin_type})" = 'true' ]]; then
        error 'type parameter not found!'
        exit 1
    else
        if [[ ! ${plugin_type} = 'check' ]] && [[ ! ${plugin_type} = 'handler' ]]; then
            error 'invalid plugin type, only handler and check are valid'
            exit 1
        fi
    fi

    if [[ "$(is_empty_string ${plugin_name})" = 'true' ]]; then
        error 'name parameter not specified!'
        exit 1
    fi

    if [[ "$(is_empty_string ${plugin_url})" = 'true' ]]; then
        error 'url parameter not specified!'
        exit 1
    else
        if [[ "$(validate_url "${plugin_url}")" = 'false' ]]; then
            error 'invalid plugin url, please verify this url is valid'
            exit 1
        fi
    fi

    if [[ "$(is_empty_string ${plugin_args})" = 'true' ]]; then
        warn 'no arguments found!'
        # expect "this plugin donot need any arguments? (y/N)"
    fi 

    echo $plugin_url

    get_plugin "${plugin_url}"

    resolve_deps "${script_path}"
    
}

main "$@"
