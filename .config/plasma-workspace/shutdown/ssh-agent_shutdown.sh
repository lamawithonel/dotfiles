#!/bin/sh

if [ -x "$(which ssh-agent)" ]; then
    ssh_agent_status() {
        ps -Ao uid,pid,comm | egrep -q "^[[:blank:]]*$(id -ru)[[:blank:]]+${SSH_AGENT_PID}[[:blank:]]+ssh-agent$"
        return $?
    }

    [ -n "$SSH_AGENT_PID" ] && ssh_agent_status && ssh-agent -k
fi

unset -f ssh_agent_status
