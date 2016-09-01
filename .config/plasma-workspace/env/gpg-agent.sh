#!/bin/sh

if [ -x "$(which gpg-agent)" ]; then
    gpg_agent_status() {
        ps -Ao uid,pid,comm | egrep -q "^[[:blank:]]*$(id -ru)[[:blank:]]+${GPG_AGENT_PID}[[:blank:]]+gpg-agent$"
        return $?
    }

    GPG_AGENT_PID=$(echo "${GPG_AGENT_INFO}" | cut -f2 -d:); export GPG_AGENT_PID
    if ! gpg_agent_status; then
        [ -f "${HOME}/.gpg-agent-info" ] && . "${HOME}/.gpg-agent-info"
        export GPG_AGENT_INFO
        GPG_AGENT_PID=$(echo "${GPG_AGENT_INFO}" | cut -f2 -d:); export GPG_AGENT_PID
        if ! gpg_agent_status ]; then
            eval "$(gpg-agent --daemon --write-env-file "${HOME}/.gpg-agent-info")"
            GPG_AGENT_PID=$(echo "${GPG_AGENT_INFO}" | cut -f2 -d:); export GPG_AGENT_PID
        fi
    fi

    GPG_TTY=$(tty); export GPG_TTY
fi

unset -f gpg_agent_status
