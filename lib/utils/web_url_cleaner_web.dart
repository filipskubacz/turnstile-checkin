// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

void cleanBrowserUrl() {
  final uri = Uri.base;
  html.window.history.replaceState(null, '', '${uri.origin}${uri.path}');
}

void openBrowserTab(String url) {
  html.window.open(url, '_blank');
}
