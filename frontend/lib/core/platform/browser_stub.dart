import 'browser_interface.dart';

/// In-memory implementation (tests / platforms without a browser).
class MemoryBrowser implements Browser {
  MemoryBrowser({Uri? uri}) : currentUri = uri ?? Uri.parse('https://example.test/');

  final Map<String, String> _store = {};
  final Map<String, String> _local = {};
  String? documentLang;
  String? lastRedirect;

  @override
  Uri currentUri;

  @override
  String? getSession(String key) => _store[key];

  @override
  void setSession(String key, String value) => _store[key] = value;

  @override
  String? getLocal(String key) => _local[key];

  @override
  void setLocal(String key, String value) => _local[key] = value;

  @override
  void setDocumentLang(String code) => documentLang = code;

  @override
  void removeSession(String key) => _store.remove(key);

  @override
  void redirect(String url) => lastRedirect = url;

  @override
  void replaceUrl(String path) => currentUri = currentUri.replace(query: '');
}

Browser createBrowser() => MemoryBrowser();
