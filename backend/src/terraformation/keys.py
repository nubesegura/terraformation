"""Convención de claves S3: proyecto, workspace y ruta del state a partir del key del objeto.

* Proyecto = primer segmento del key (cada key de la raíz del bucket es un proyecto).
* State = cualquier ``*.tfstate`` a cualquier profundidad dentro del proyecto; su ruta relativa
  (incluye el nombre del archivo) identifica el state dentro del proyecto.
* Workspaces de Terraform: ``env:/<workspace>/<proyecto>/<ruta>``.
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
    """Identifica un state: (proyecto, workspace, ruta dentro del proyecto)."""

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
    """Devuelve el StateRef si ``key`` es un archivo de state (``*.tfstate``).

    Los ``.tflock`` (``<archivo>.tfstate.tflock``) no coinciden nunca con este patrón.
    """
    if not key.endswith(STATE_SUFFIX):
        return None
    parts = key.split("/")
    if any(not p for p in parts):
        return None
    if parts[0] == WORKSPACE_PREFIX:
        if len(parts) < 4:  # env: / workspace / proyecto / archivo
            return None
        return StateRef(parts[2], parts[1], "/".join(parts[3:]))
    if len(parts) < 2:  # un state en la raíz del bucket no pertenece a ningún proyecto
        return None
    return StateRef(parts[0], DEFAULT_WORKSPACE, "/".join(parts[1:]))


def parse_lock_key(key: str) -> StateRef | None:
    if not key.endswith(LOCK_SUFFIX):
        return None
    return parse_key(key[: -len(LOCK_SUFFIX)])


def split_sid(sid: str) -> StateRef:
    project, workspace, path = sid.split("#", 2)
    return StateRef(project, workspace, path)
