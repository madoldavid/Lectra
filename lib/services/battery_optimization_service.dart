import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BatteryOptimizationService {
  static const MethodChannel _channel =
      MethodChannel('lectra/battery_optimization');

  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (kIsWeb || !Platform.isAndroid) {
      return true;
    }
    try {
      final result = await _channel.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (kIsWeb || !Platform.isAndroid) {
      return true;
    }
    try {
      final result = await _channel.invokeMethod<bool>(
        'requestIgnoreBatteryOptimizations',
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openBatteryOptimizationSettings() async {
    if (kIsWeb || !Platform.isAndroid) {
      return true;
    }
    try {
      final result = await _channel.invokeMethod<bool>(
        'openBatteryOptimizationSettings',
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}
