#!/bin/sh
#
# Can pi see its OpenRouter credential in THIS execution context?
#
# This is the case that catches most "pi doesn't work" reports.  The
# host sandbox policy can deny OPENROUTER_API_KEY, and when the sandbox
# silently fails open the same command succeeds instead.  One command,
# two outcomes, depending on a setting nobody was looking at.

set -o nounset

command -v pi > /dev/null 2>&1 || {
	echo 'pi absent; nothing to authenticate'
	exit 77
}

if [ -n "${OPENROUTER_API_KEY:-}" ]; then
	echo "OPENROUTER_API_KEY visible here (${#OPENROUTER_API_KEY} chars)."
	echo 'If another context reports pi failing to authenticate, the'
	echo 'sandbox is enforced there and not here -- compare contexts,'
	echo 'not commands.'
	exit 0
fi

echo 'OPENROUTER_API_KEY is unset in this context.'
echo
echo 'pi cannot authenticate to OpenRouter, so every openrouter/* model'
echo 'is unreachable.  Expect an auth error, not a missing-CLI error.'
echo
echo 'Likely cause: the sandbox credential policy denies this variable.'
echo 'Check, in order:'
echo '  1. the sandbox.credentials.envVars entry for this variable, and'
echo '     whether its mode is deny (removed) or mask (wrong value) --'
echo '     both break authentication, differently;'
echo '  2. allowUnsandboxedCommands, which decides whether credential'
echo '     rules apply to this command at all.  A context where it is'
echo '     true sees the real value and one where it is false does not,'
echo '     from identical policy;'
echo '  3. whether the sandbox settings file parsed at all -- an invalid'
echo '     one can be discarded wholesale, leaving the sandbox open.'
exit 1
