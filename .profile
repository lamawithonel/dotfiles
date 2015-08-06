# ~/.profile
#
# This file is read by POSIX-compliant shells when invoked as login shells.
# In the case of Bash, if either ~/.bash_profile or ~/.bash_login exist it
# will read the first one it encounters and ignore the rest.
# See the INVOCATION section of the bash(1) man page for more information.

# if running bash
if [ -n "${BASH_VERSION}" ]; then
	# include .bashrc if it exists
	if [ -f "${HOME}/.bashrc" ]; then
	. "${HOME}/.bashrc"
	fi
fi

# The defult umask is set in /etc/profile or using pam_umask(8), but we
# set it here, too, to ensure a secure default.  You can change it if you
# want.
if [ $(id -ru) -gt 999 ] && [ "$(id -gn)" = "$(id -un)" ]; then
	umask 0027
else
	umask 0022
fi

# Add RVM to PATH for scripting
if [ -d "${HOME}/.rvm/bin" ] && ! $(echo $PATH | egrep -q "${HOME}/\.rvm/bin" 2>&1); then
	PATH="${HOME}/.rvm/bin:${PATH}"
fi

# Add the private /bin directory to $PATH
if [ -d "${HOME}/bin" ] && ! $(echo $PATH | egrep -q "${HOME}/bin" 2>&1); then
	PATH="${HOME}/bin:${PATH}"
fi

export PATH

# Load RVM into a shell session *as a function*
[ -s "${HOME}/.rvm/scripts/rvm" ] && . "${HOME}/.rvm/scripts/rvm"

# Setup the gnupg environment
if [ -f "${HOME}/.gpg-agent-info" ]; then
	ps xao pid | grep $(sed -n -e 's/^.*gpg-agent:\([[:digit:]]*\).*$/\1/p' ~/.gpg-agent-info) > /dev/null ; agent_status=$?
fi

if [ "${agent_status}" = '0' ]; then
	. "${HOME}/.gpg-agent-info"
	export GPG_AGENT_INFO SSH_AUTH_SOCK SSH_AGENT_PID
elif which gpg-agent >/dev/null 2>&1; then
	eval $(gpg-agent --daemon --enable-ssh-support --write-env-file "${HOME}/.gpg-agent-info")
	export GPG_AGENT_INFO SSH_AUTH_SOCK SSH_AGENT_PID
fi
unset agent_status
