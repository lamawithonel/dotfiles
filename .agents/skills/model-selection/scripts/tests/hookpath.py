#!/usr/bin/env python3
"""Locate an installed hook for the hook tests, in the staging or live layout.

The staging tree mirrors $HOME, so its hooks sit in R/.claude/hooks; a
live install keeps them in ~/.claude/hooks.  MODEL_SELECTION_HOOK_DIR, when
set, is the only place searched.
"""

import os
from collections.abc import Mapping
from pathlib import Path
from typing import Final

ENV_VAR: Final = "MODEL_SELECTION_HOOK_DIR"
STAGING_HOOKS: Final = Path(__file__).resolve().parents[5] / ".claude" / "hooks"


def find_hook(
    name: str,
    env: Mapping[str, str] | None = None,
    *,
    staging: Path = STAGING_HOOKS,
    home: Path | None = None,
) -> Path | None:
    env = os.environ if env is None else env
    if env.get(ENV_VAR):
        dirs = [Path(env[ENV_VAR])]
    else:
        dirs = [staging, (home or Path.home()) / ".claude" / "hooks"]
    return next((d / name for d in dirs if (d / name).is_file()), None)
