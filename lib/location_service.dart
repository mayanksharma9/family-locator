import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';

import 'package:background_locator_2/location_dto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class LocationService {
  static const String isolateName = 'LocatorIsolate';
  static WebSocketChannel? _channel;
  static bool _isSharing = false;

  @pragma('vm:entry-point')
  static void callback(LocationDto locationDto) async {
    final SendPort? send = IsolateNameServer.lookupPortByName(isolateName);
    send?.send(locationDto.toJson());

    // Headless execution logic (when app is killed)
    await _sendToRelay(locationDto);
  }

  @pragma('vm:entry-point')
  static void notificationCallback() {
    print('User clicked on the notification');
  }

  @pragma('vm:entry-point')
  static void initCallback(dynamic _) {
    print('Plugin initialization');
  }

  @pragma('vm:entry-point')
  static void disposeCallback() {
    _channel?.sink.close();
    _channel = null;
    print('Plugin disposed');
  }

  static Future<void> _sendToRelay(LocationDto locationDto) async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('fl_name');
    final roomCode = prefs.getString('fl_roomCode');
    final serverUrl = prefs.getString('fl_serverUrl');
    _isSharing = prefs.getBool('fl_isSharing') ?? true;

    if (name == null || roomCode == null || serverUrl == null || !_isSharing) {
      // Missing intent or sharing paused, don't send
      return;
    }

    if (_channel == null) {
      try {
        _channel = WebSocketChannel.connect(Uri.parse(serverUrl));
        // We join as the same user to avoid duplicates, but with isSharing flag
        _channel!.sink.add(jsonEncode({
          'type': 'join',
          'name': name,
          'roomCode': roomCode,
          'isSharing': true,
        }));
      } catch (e) {
        print('Background socket connection failed: $e');
        return;
      }
    }

    try {
      _channel!.sink.add(jsonEncode({
        'type': 'location',
        'lat': locationDto.latitude,
        'lng': locationDto.longitude,
        'accuracy': locationDto.accuracy,
        'isSharing': true,
      }));
    } catch (e) {
      // If socket died, clear it so we reconnect next tick
      _channel = null;
    }
  }
}
