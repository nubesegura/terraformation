abstract class Browser {
  String? getSession(String key);
  void setSession(String key, String value);
  void removeSession(String key);

  /// URL actual (con query, sin hash).
  Uri get currentUri;

  /// Redirige la pestaña completa a [url].
  void redirect(String url);

  /// Reemplaza la URL visible sin recargar (para quitar `?code=`).
  void replaceUrl(String path);
}
