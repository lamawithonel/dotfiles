# ~/.bash_logout: executed by bash(1) when login shell exits.


ssh-agent -k > /dev/null 2>&1

# when leaving the console clear the screen to increase privacy
if [ $SHLVL -eq 1 ]; then
	# First try Debian clear_console(1)
	if [ -x /usr/bin/clear_console ] && /usr/bin/clear_console -q; then
		return
	else
		# If that doesn't work, use clear(1) to clear the screen.  If
		# it's available, use chvt(1) to clear the scrollback buffer by
		# switching to tty63 and back.
		case "$(tty)" in
			/dev/tty[0-9])
				t=$(v=`tty` ; echo ${v##*ty})
				clear
				[ -x /bin/chvt -o -x /usr/bin/chvt ] && chvt 63; chvt "$t"
				;;

			/dev/tty[0-9][0-9])
				t=$(v=`tty` ; echo ${v##*ty})
				clear
				[ -x /bin/chvt -o -x /usr/bin/chvt ] && chvt 63; chvt "$t"
				;;

			*)
				;;
		esac
	fi
fi

# vi:ts=4:sw=4:noexpandtab:ft=sh
