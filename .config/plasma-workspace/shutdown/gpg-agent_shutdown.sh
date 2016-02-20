#!/bin/sh

if [ -x "$(which gpg-agent)" ]; then
    gpg_agent_status() {
        ps -Ao uid,pid,comm | egrep -q "^[[:blank:]]*$(id -ru)[[:blank:]]+${GPG_AGENT_PID}[[:blank:]]+gpg-agent$"
        return $?
    }

    [ -n "$GPG_AGENT_PID" ] && gpg_agent_status && kill $GPG_AGENT_PID
fi

unset -f gpg_agent_status
