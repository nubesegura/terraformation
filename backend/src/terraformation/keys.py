"""S3 key convention: project, workspace and state path derived from the object key.

* Project = first segment of the key (every key at the bucket root is a project).
* State = any ``*.tfstate`` at any depth inside the project; its relative path
  (including the file name) identifies the state within the project.
* Terraform workspaces: ``env:/<workspace>/<project>/<path>``.
"""

from __future__ import annotations

from dataclasses import dataclass

WORKSPACE_PREFIX = "env:"
DEFAULT_WORKSPACE = "default"
DEFAULT_PATH = "terraform.tfstate"
STATE_SUFFIX = ".tfstate"
LOCK_SUFFIX = ".tflock"


@dataclass(frozen=True)
class StateRef:
    """Identifies a state: (project, workspace, path inside the project)."""

    project: str
    workspace: str = DEFAULT_WORKSPACE
    path: str = DEFAULT_PATH

    @property
    def sid(self) -> str:
        return f"{self.project}#{self.workspace}#{self.path}"

    @property
    def pk(self) -> str:
        return f"PROJECT#{self.sid}"

    @property
    def state_key(self) -> str:
        if self.workspace == DEFAULT_WORKSPACE:
            return f"{self.project}/{self.path}"
        return f"{WORKSPACE_PREFIX}/{self.workspace}/{self.project}/{self.path}"

    @property
    def lock_key(self) -> str:
        return self.state_key + LOCK_SUFFIX


def parse_key(key: str) -> StateRef | None:
    """Returns the StateRef if ``key`` is a state file (``*.tfstate``).

    ``.tflock`` files (``<file>.tfstate.tflock``) never match this pattern.
    """
    if not key.endswith(STATE_SUFFIX):
        return None
    parts = key.split("/")
    if any(not p for p in parts):
        return None
    if parts[0] == WORKSPACE_PREFIX:
        if len(parts) < 4:  # env: / workspace / project / file
            return None
        return StateRef(parts[2], parts[1], "/".join(parts[3:]))
    if len(parts) < 2:  # a state at the bucket root does not belong to any project
        return None
    return StateRef(parts[0], DEFAULT_WORKSPACE, "/".join(parts[1:]))


def parse_lock_key(key: str) -> StateRef | None:
    if not key.endswith(LOCK_SUFFIX):
        return None
    return parse_key(key[: -len(LOCK_SUFFIX)])


def split_sid(sid: str) -> StateRef:
    project, workspace, path = sid.split("#", 2)
    return StateRef(project, workspace, path)
