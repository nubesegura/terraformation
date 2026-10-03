// UI strings in English (default) and Spanish, side by side so both stay in sync and are easy to review.
// Each member requires both translations, so a missing one is a compile error.
//
// Add a string: create a getter (or a method when it takes parameters) with its `en` and `es` text.
import 'package:flutter/widgets.dart';

enum AppLang {
  en('EN', 'English'),
  es('ES', 'Español');

  const AppLang(this.short, this.nativeName);

  /// Short label for the language button.
  final String short;
  final String nativeName;

  static AppLang fromCode(String? code) => AppLang.values.firstWhere((l) => l.name == code, orElse: () => AppLang.en);
}

class AppStrings {
  const AppStrings(this.lang);
  final AppLang lang;

  String _(String en, String es) => lang == AppLang.en ? en : es;

  String get account => _('Account', 'Cuenta');
  String get activeLocks => _('Active locks', 'Locks activos');
  String get activeLower => _('active', 'activo');
  String get activity14 => _('Activity (14 days)', 'Actividad 14 días');
  String get activityTitle => _('Activity (versions and locks per day)', 'Actividad (versiones y locks por día)');
  String agoDays(int n) => _('$n d ago', 'hace $n d');
  String agoHours(int n) => _('$n h ago', 'hace $n h');
  String agoMinutes(int n) => _('$n min ago', 'hace $n min');
  String get aiDisabled => _('The AI summary is disabled in this deployment.', 'El resumen con IA está desactivado en este despliegue.');
  String get alertTag => _('Alert', 'Alerta');
  String alertThreshold(int m) => _('An alert is raised when a lock lasts longer than $m min.', 'Se alerta cuando un lock supera $m min.');
  String get allLabel => _('All', 'Todos');
  String get allModules => _('All modules', 'Todos los módulos');
  String get appSubtitle => _('Terraform state viewer for S3', 'Visor de Terraform states en S3');
  String get attrKeyLabel => _('Attribute (key)', 'Atributo (clave)');
  String get attrValueLabel => _('Attribute (value contains)', 'Atributo (valor contiene)');
  String attributesCount(int n) => _('$n attributes', '$n atributos');
  String get authInvalidResponse => _('Invalid sign-in response', 'Respuesta de inicio de sesión no válida');
  String authTokenRejected(int status) => _('Cognito rejected the token request ($status)', 'Cognito rechazó la solicitud de token ($status)');
  String get awsFilterHint => _('Filter by name, identifier, type or Terraform resource', 'Filtrar por nombre, identificador, tipo o recurso de Terraform');
  String get backToProject => _('Back to project', 'Volver al proyecto');
  String get compare => _('Compare', 'Comparar');
  String compareVersionsTitle(String label) => _('Compare versions · $label', 'Comparar versiones · $label');
  String get currentTag => _('current', 'vigente');
  String get dataSourcesBlock => _('Data sources (read-only)', 'Data sources (solo lectura)');
  String get days14 => _('14 days', '14 días');
  String get dependenciesChanged => _('dependencies changed', 'dependencias modificadas');
  String get dependsOn => _('Depends on:', 'Depende de:');
  String get dependsOnTitle => _('Depends on', 'Depende de');
  String diffAdded(int n) => _('+$n added', '+$n agregados');
  String diffModified(int n) => _('~$n modified', '~$n modificados');
  String diffRemoved(int n) => _('−$n removed', '−$n eliminados');
  String diffUnchanged(int n) => _('$n unchanged', '$n sin cambios');
  String get filterAddressOrAttr => _('Filter by address or attribute', 'Filtrar por dirección o atributo');
  String get filterProjectsHint => _('Filter by project, workspace or state path', 'Filtrar por proyecto, workspace o ruta del state');
  String get filterResources => _('Filter resources', 'Filtrar recursos');
  String get fromOlder => _('From (older)', 'Desde (antigua)');
  String graphCounts(int nodes, int edges) => _('$nodes nodes · $edges dependencies', '$nodes nodos · $edges dependencias');
  String get graphNoResources => _('This state has no resources.', 'Este state no tiene recursos.');
  String graphTruncated(int n) => _('showing the first $n; filter by module', 'mostrando los primeros $n; filtra por módulo');
  String groupAdded(int n) => _('Added ($n)', 'Agregados ($n)');
  String groupModified(int n) => _('Modified ($n)', 'Modificados ($n)');
  String groupRemoved(int n) => _('Removed ($n)', 'Eliminados ($n)');
  String groupSubtitle(String ago, int n) => _('Modified $ago · $n resources in total', 'Modificado $ago · $n recursos en total');
  String get highlightHint => _('Highlight…', 'Resaltar…');
  String instancesTag(int n) => _('$n instances', '$n instancias');
  String get justNow => _('just now', 'hace instantes');
  String lastLockReleased(String who, String ago) => _('Last lock by $who, released $ago', 'Último lock de $who, liberado $ago');
  String get lastModified => _('Last modified', 'Última modificación');
  String lockAlertOver(int n, int m) => _('$n over $m min', '$n sobre $m min');
  String lockHistory(int n) => _('Lock history ($n)', 'Historial de locks ($n)');
  String get lockLocked => _('Locked', 'Bloqueado');
  String get lockLockedAlert => _('Locked (alert)', 'Bloqueado (alerta)');
  String get lockNoneDetected => _('No locking detected', 'Sin locking detectado');
  String get lockReleased => _('Released', 'Liberado');
  String get lockTipNoneDetected => _('A .tflock was never seen: use_lockfile may be missing', 'Nunca se vio un .tflock: posible falta de use_lockfile');
  String get lockTipReleased => _('Last lock released', 'Último lock liberado');
  String get lockedAlertByDuration => _('Locked — duration alert', 'Bloqueado — alerta por duración');
  String lockedCount(int n) => _('$n locked', '$n bloqueado(s)');
  String get lockedProjects => _('Locked projects', 'Proyectos bloqueados');
  String mapDegradedBanner(int n) => _('$n rule(s) in the map are invalid; the affected types appear as "Unmapped".', 'Hay $n regla(s) inválida(s) en el mapa; los tipos afectados aparecen como "Sin mapear".');
  String mapStaleBanner(int days, String date) => _('The map has not been reviewed for more than $days days (last review: $date). New types may be missing: check the "Unmapped" section.', 'El mapa lleva más de $days días sin revisarse (última revisión: $date). Pueden faltar tipos nuevos: revisa la sección "Sin mapear".');
  String get mapUnavailableBanner => _('The resource map could not be loaded: no resource can be associated with AWS and everything appears as "Unmapped".', 'El mapa de recursos no se pudo cargar: ningún recurso se puede asociar a AWS y todo aparece como "Sin mapear".');
  String modifiedAgo(String ago) => _('Modified $ago', 'Modificado $ago');
  String get moduleLabel => _('Module', 'Módulo');
  String get modulesTitle => _('Modules', 'Módulos');
  String get nameLabel => _('Name', 'Nombre');
  String get navDashboard => _('Dashboard', 'Dashboard');
  String get navLocks => _('Locks', 'Locks');
  String get navProjects => _('Projects', 'Proyectos');
  String get navSearch => _('Search', 'Búsqueda');
  String get needTwoReadable => _('At least two readable versions are needed to compare.', 'Se necesitan al menos dos versiones legibles para comparar.');
  String get noAwsResources => _('This state has no managed AWS resources.', 'Este state no contiene recursos AWS gestionados.');
  String get noData => _('No data', 'Sin datos');
  String get noDifferences => _('No differences.', 'Sin diferencias.');
  String get noLockEverSeen => _('No .tflock was ever seen for this state. use_lockfile = true may be missing in the backend.', 'Nunca se vio un .tflock para este state. Posible falta de use_lockfile = true en el backend.');
  String get noLocksRecorded => _('No locks were recorded. If you use the S3 backend, check that `use_lockfile = true`.', 'No se registraron locks. Si usas el backend S3, revisa que `use_lockfile = true`.');
  String get noProjectLocked => _('No project is locked.', 'Ningún proyecto está bloqueado.');
  String get noProjectsYet => _('No projects yet. Run the backfill or wait for S3 events.', 'No hay proyectos todavía. Ejecuta el backfill o espera eventos de S3.');
  String get noResults => _('No results.', 'Sin resultados.');
  String get othersSubtitle => _('They do not create AWS resources: random passwords, waits, data sources, etc.', 'No crean recursos AWS: contraseñas aleatorias, esperas, data sources, etc.');
  String get othersTitle => _('Terraform utilities and data', 'Utilidades y datos de Terraform');
  String outputsTitle(int n) => _('Outputs ($n)', 'Outputs ($n)');
  String get pickTwoVersions => _('Select two versions to compare them (or use “vs previous”).', 'Selecciona dos versiones para compararlas (o usa “vs anterior”).');
  String get projectLabel => _('Project', 'Proyecto');
  String get projectsSubtitle => _('Each project groups the states (*.tfstate) it contains, ordered by last modification', 'Cada proyecto agrupa los states (*.tfstate) que contiene, ordenados por última modificación');
  String projectsWithStates(int n) => _('Projects ($n states)', 'Proyectos ($n states)');
  String get providerVersionNote => _('The state does not record each provider\'s version; showing the providers in use.', 'El state no registra la versión de cada provider; se muestran los providers en uso.');
  String get providersInUse => _('Providers in use', 'Providers en uso');
  String get provisionalTag => _('provisional rule', 'regla provisional');
  String get reasonAmbiguous => _('Matches more than one parent resource', 'Coincide con más de un recurso padre');
  String get reasonInvalidEntry => _('Invalid rule in the map', 'Regla inválida en el mapa');
  String get reasonMapUnavailable => _('The map could not be loaded', 'El mapa no se pudo cargar');
  String get reasonMissingIdentity => _('No usable identifier', 'Sin identificador utilizable');
  String get reasonMissingParentRef => _('No reference to its parent resource', 'Sin referencia a su recurso padre');
  String get reasonNoRule => _('Type has no rule in the map', 'Tipo sin regla en el mapa');
  String get reasonNonAws => _('Provider other than AWS', 'Proveedor distinto de AWS');
  String get reasonOrphan => _('Its parent resource is not in this state', 'Su recurso padre no está en este state');
  String get recentlyModified => _('Recently modified', 'Modificados recientemente');
  String get resources => _('Resources', 'Recursos');
  String get resourcesByModule => _('Resources by module', 'Recursos por módulo');
  String get resourcesByProject => _('Resources by project', 'Recursos por proyecto');
  String get resourcesByProvider => _('Resources by provider', 'Recursos por provider');
  String get resourcesByType => _('Resources by type', 'Recursos por tipo');
  String resourcesCount(int n) => _('$n resources', '$n recursos');
  String resourcesTitle(int n) => _('Resources ($n)', 'Recursos ($n)');
  String resultsCount(int n) => _('$n results', '$n resultados');
  String resultsCountMore(int n) => _('$n results (more available; refine the filters)', '$n resultados (hay más; afina los filtros)');
  String get retry => _('Retry', 'Reintentar');
  String get searchButton => _('Search', 'Buscar');
  String get searchNeedFilter => _('Enter at least one filter', 'Indica al menos un filtro');
  String get searchSubtitle => _('On the current version of each state. Type and name are exact matches.', 'Sobre la versión vigente de cada state. Tipo y nombre son exactos.');
  String get searchTitle => _('Resource search', 'Búsqueda de recursos');
  String get sensitiveOrDepsNote => _('A sensitive value or the dependencies changed (values are not shown).', 'Cambió un valor sensible o las dependencias (los valores no se muestran).');
  String get sensitiveTag => _('sensitive', 'sensible');
  String get sensitiveValueChanged => _('sensitive value changed', 'valor sensible modificado');
  String get sessionActive => _('Signed in', 'Sesión activa');
  String showingFirst400(int total) => _('Showing 400 of $total; use the filter to narrow down.', 'Mostrando 400 de $total; usa el filtro para acotar.');
  String get sideBySide => _('Side by side', 'Lado a lado');
  String get signIn => _('Sign in', 'Iniciar sesión');
  String get signOut => _('Sign out', 'Cerrar sesión');
  String startupFailed(String detail) => _('The application could not start: $detail', 'No se pudo iniciar la aplicación: $detail');
  String get statAwsResources => _('AWS resources', 'Recursos AWS');
  String get statMapped => _('Terraform elements mapped', 'Elementos de Terraform mapeados');
  String statMappedValue(int a, int b) => _('$a of $b', '$a de $b');
  String get statUnmapped => _('Unmapped', 'Sin mapear');
  String get stateDeleted => _('state deleted', 'state eliminado');
  String get stateVersionLabel => _('State version', 'Versión del state');
  String statesCount(int n) => _('$n states', '$n states');
  String get summarizeWithAi => _('Summarize with AI', 'Resumir con IA');
  String get swap => _('Swap', 'Intercambiar');
  String get tabAws => _('AWS resources', 'Recursos AWS');
  String get tabGraph => _('Graph', 'Grafo');
  String get tabOverview => _('Overview', 'Resumen');
  String get tabTerraform => _('Terraform', 'Terraform');
  String get tabTimeline => _('Timeline', 'Línea de tiempo');
  String terraformElements(int n) => _('$n Terraform element(s)', '$n elemento(s) de Terraform');
  String terraformShort(String v) => _('TF $v', 'TF $v');
  String terraformVersion(String v) => _('Terraform $v', 'Terraform $v');
  String get terraformVersionsInUse => _('Terraform versions in use', 'Versiones de Terraform en uso');
  String get timelineDeleteMarker => _('State deleted (delete marker)', 'State eliminado (delete marker)');
  String timelineLockAcquired(String who) => _('Lock acquired by $who', 'Lock adquirido por $who');
  String get timelineLockReleased => _('Lock released', 'Lock liberado');
  String timelineLockReleasedAfter(String duration) => _('Lock released ($duration)', 'Lock liberado ($duration)');
  String timelineVersion(int serial, String tf) => _('Serial $serial · Terraform $tf', 'Serial $serial · Terraform $tf');
  String get tipAlertLocks => _('Locks with alerts', 'Locks con alerta');
  String get tipChangeTheme => _('Change theme', 'Cambiar tema');
  String get tipLanguage => _('Language', 'Idioma');
  String get tipRefresh => _('Refresh', 'Actualizar');
  String get toNewer => _('To (newer)', 'Hasta (nueva)');
  String get twoSelected => _('Two versions selected', 'Dos versiones seleccionadas');
  String get typeLabel => _('Type (aws_s3_bucket)', 'Tipo (aws_s3_bucket)');
  String get unified => _('Unified', 'Unificado');
  String get unknownDate => _('unknown', 'desconocida');
  String get unmappedSubtitle => _('Resources the map could not associate with an AWS resource with certainty. They are never guessed by name.', 'Recursos que el mapa no pudo asociar con certeza a un recurso AWS. No se adivinan por nombre.');
  String get usedByTitle => _('Used by', 'Usado por');
  String get utilitiesBlock => _('Utilities (random, time, null, tls…)', 'Utilidades (random, time, null, tls…)');
  String versionProjects(String version, int n) => _('$version · $n proj.', '$version · $n proy.');
  String get versions => _('Versions', 'Versiones');
  String versionsCount(int n) => _('$n versions', '$n versiones');
  String get view => _('View', 'Ver');
  String get vsPrevious => _('vs previous', 'vs anterior');
  String whoSince(String who, String op, String ago) => _('$who · $op · since $ago', '$who · $op · desde $ago');
  String whoSinceDuration(String who, String op, String since, String duration) => _('$who · $op · since $since ($duration)', '$who · $op · desde $since ($duration)');

  /// Reason code returned by the API for resources the map could not associate with an AWS resource.
  String unmappedReason(String code) => switch (code) {
        'no_rule' => reasonNoRule,
        'non_aws_provider' => reasonNonAws,
        'missing_identity' => reasonMissingIdentity,
        'missing_parent_ref' => reasonMissingParentRef,
        'orphan_child' => reasonOrphan,
        'ambiguous_parent' => reasonAmbiguous,
        'invalid_map_entry' => reasonInvalidEntry,
        'map_unavailable' => reasonMapUnavailable,
        _ => code,
      };
}

/// Provides the active [AppStrings] to the widget tree; widgets rebuild when the language changes.
class AppStringsScope extends InheritedWidget {
  const AppStringsScope({super.key, required this.strings, required super.child});
  final AppStrings strings;

  static AppStrings of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppStringsScope>();
    return scope?.strings ?? const AppStrings(AppLang.en);
  }

  @override
  bool updateShouldNotify(AppStringsScope old) => old.strings.lang != strings.lang;
}

extension AppStringsContext on BuildContext {
  AppStrings get s => AppStringsScope.of(this);
}
