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
