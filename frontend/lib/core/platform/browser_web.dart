import 'package:web/web.dart' as web;

import 'browser_interface.dart';

class WebBrowser implements Browser {
  @override
  String? getSession(String key) {
    try {
      return web.window.sessionStorage.getItem(key);
    } catch (_) {
      return null;
    }
  }

  @override
  void setSession(String key, String value) {
    try {
      web.window.sessionStorage.setItem(key, value);
    } catch (_) {}
  }

  @override
  void removeSession(String key) {
    try {
      web.window.sessionStorage.removeItem(key);
    } catch (_) {}
  }

  @override
  Uri get currentUri => Uri.parse(web.window.location.href);

  @override
  void redirect(String url) => web.window.location.assign(url);

  @override
  void replaceUrl(String path) => web.window.history.replaceState(null, '', path);
}

Browser createBrowser() => WebBrowser();
