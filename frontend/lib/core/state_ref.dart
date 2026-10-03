/// Identidad de un state: proyecto + workspace + ruta dentro del proyecto.
typedef StateRef = ({String project, String workspace, String path});

const defaultStatePath = 'terraform.tfstate';

/// Ruta de la UI hacia un state (`/projects/<p>[/sub]?workspace=&path=&...`).
String stateLocation(StateRef r, {String sub = '', Map<String, String> extra = const {}}) {
  final q = <String, String>{
    'workspace': r.workspace,
    if (r.path != defaultStatePath) 'path': r.path,
    ...extra,
  };
  final query = q.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
  return '/projects/${Uri.encodeComponent(r.project)}${sub.isEmpty ? '' : '/$sub'}?$query';
}

/// Etiqueta legible: `proyecto[:workspace][/ruta]` (omite `default` y `terraform.tfstate`).
String stateLabel(StateRef r) {
  final ws = r.workspace == 'default' ? '' : ':${r.workspace}';
  final path = r.path == defaultStatePath ? '' : '/${r.path}';
  return '${r.project}$ws$path';
}
