#!/bin/sh

if [ -x "$(which ssh-agent)" ]; then
    ssh_agent_status() {
        ps -Ao uid,pid,comm | egrep -q "^[[:blank:]]*$(id -ru)[[:blank:]]+${SSH_AGENT_PID}[[:blank:]]+ssh-agent$"
        return $?
    }

    if [ ! -S "${SSH_AUTH_SOCK}" ] || ! ssh_agent_status; then
        [ -f "${HOME}/.ssh-agent-info" ] && . "${HOME}/.ssh-agent-info"
        if [ ! -S "${SSH_AUTH_SOCK}" ] || ! ssh_agent_status; then
            eval "$(ssh-agent | head -n 2 | tee "${HOME}/.ssh-agent-info")"
        fi
    fi
fi

unset -f ssh_agent_status
