import 'browser_interface.dart';

/// Implementación en memoria (pruebas / plataformas sin navegador).
class MemoryBrowser implements Browser {
  MemoryBrowser({Uri? uri}) : currentUri = uri ?? Uri.parse('https://example.test/');

  final Map<String, String> _store = {};
  String? lastRedirect;

  @override
  Uri currentUri;

  @override
  String? getSession(String key) => _store[key];

  @override
  void setSession(String key, String value) => _store[key] = value;

  @override
  void removeSession(String key) => _store.remove(key);

  @override
  void redirect(String url) => lastRedirect = url;

  @override
  void replaceUrl(String path) => currentUri = currentUri.replace(query: '');
}

Browser createBrowser() => MemoryBrowser();
