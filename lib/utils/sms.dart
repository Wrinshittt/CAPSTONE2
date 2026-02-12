import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

Future<bool> openSmsApp({
  required String phone, // e.g. +63917XXXXXXX
  String? body, // optional prefilled text
}) async {
  if (kIsWeb) return false; // not supported on web

  final encodedBody = Uri.encodeComponent(body ?? '');
  // iOS accepts "sms:&body="; Android accepts "?body="
  final uri = Platform.isIOS
      ? Uri.parse('sms:$phone&body=$encodedBody')
      : Uri.parse('sms:$phone?body=$encodedBody');

  if (await canLaunchUrl(uri)) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
  return false;
}
