import 'package:flutter/foundation.dart';

void appLog(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}
