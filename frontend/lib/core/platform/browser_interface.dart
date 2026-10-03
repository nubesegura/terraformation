abstract class Browser {
  String? getSession(String key);
  void setSession(String key, String value);
  void removeSession(String key);

  /// Persistent storage (localStorage), used for preferences that must survive the session.
  String? getLocal(String key);
  void setLocal(String key, String value);

  /// Sets the `lang` attribute of the HTML document (accessibility and translation tools).
  void setDocumentLang(String code);

  /// Current URL (with query, without hash).
  Uri get currentUri;

  /// Redirects the whole tab to [url].
  void redirect(String url);

  /// Replaces the visible URL without reloading (to remove `?code=`).
  void replaceUrl(String path);
}
