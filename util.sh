#!/bin/bash

function trim_string() {
    echo "${1}" | sed -e 's/^ *//g' -e 's/ *$//g'
}

function is_empty_string() {
    if [[ "$(trim_string ${1})" = '' ]]; then
        echo 'true'
    else
        echo 'false'
    fi
}

function notify() {
    echo -e "\033[1;32m\[NOTICE\] ${1}\033[0m" 1>&2
}

function warn() {
    echo -e "\033[1;33m\[WARNNING\] ${1}\033[0m" 1>&2
}

function error() {
    echo -e "\033[1;31m\[ERROR\] ${1}\033[0m" 1>&2
}

function validate_url() {
    if [[ $(wget -S --spider $1 2>&1 | grep 'HTTP/1.1 200 OK') ]]; then
        echo 'true'
    else
        echo 'false'
    fi
}
