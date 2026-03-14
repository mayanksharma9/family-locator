import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:background_locator_2/background_locator.dart';
import 'package:background_locator_2/location_dto.dart';
import 'package:background_locator_2/settings/android_settings.dart';
import 'package:background_locator_2/settings/ios_settings.dart';
import 'package:background_locator_2/settings/locator_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'location_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackgroundLocator.initialize();
  runApp(const FamilyLocatorApp());
}

class FamilyLocatorApp extends StatelessWidget {
  const FamilyLocatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Family Locator',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF245CFF)),
        useMaterial3: true,
      ),
      home: const FamilyLocatorHomePage(),
    );
  }
}

class FamilyMember {
  const FamilyMember({
    required this.id,
    required this.name,
    required this.location,
    required this.lastUpdated,
    required this.isSharing,
    required this.accuracy,
    this.isCurrentUser = false,
  });

  final String id;
  final String name;
  final LatLng? location;
  final DateTime? lastUpdated;
  final bool isSharing;
  final double? accuracy;
  final bool isCurrentUser;

  factory FamilyMember.fromJson(Map<String, dynamic> json, {required String currentUserId}) {
    final lat = (json['lat'] as num?)?.toDouble();
    final lng = (json['lng'] as num?)?.toDouble();
    return FamilyMember(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      location: lat == null || lng == null ? null : LatLng(lat, lng),
      lastUpdated: json['updatedAt'] == null ? null : DateTime.tryParse(json['updatedAt'] as String),
      isSharing: json['isSharing'] as bool? ?? false,
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      isCurrentUser: (json['id'] as String? ?? '') == currentUserId,
    );
  }
}

extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _ConnectionIntent {
  const _ConnectionIntent({
    required this.name,
    required this.roomCode,
    required this.serverUrl,
  });

  final String name;
  final String roomCode;
  final String serverUrl;
}

class FamilyLocatorHomePage extends StatefulWidget {
  const FamilyLocatorHomePage({super.key});

  @override
  State<FamilyLocatorHomePage> createState() => _FamilyLocatorHomePageState();
}

class _FamilyLocatorHomePageState extends State<FamilyLocatorHomePage> {
  final MapController _mapController = MapController();
  final TextEditingController _nameController = TextEditingController(text: 'Leo');
  final TextEditingController _roomController = TextEditingController(text: 'HOME123');
  final TextEditingController _serverController = TextEditingController(text: 'ws://192.168.4.64:8081');

  WebSocketChannel? _channel;
  StreamSubscription? _socketSubscription;
  ReceivePort? _port;
  Timer? _pingTimer;
  Timer? _reconnectTimer;

  bool _sharingEnabled = false;
  bool _isConnected = false;
  bool _isJoining = false;
  bool _autoReconnectEnabled = false;
  int _reconnectAttempts = 0;

  String? _status = 'Enter a visible family code and connect to your relay.';
  String? _roomCode;
  String? _memberId;
  geo.Position? _currentPosition;
  List<FamilyMember> _members = const [];
  _ConnectionIntent? _lastIntent;
  String? _selectedMemberId;

  @override
  void initState() {
    super.initState();
    _initBackgroundLocator();
  }

  void _initBackgroundLocator() {
    _port = ReceivePort();
    IsolateNameServer.registerPortWithName(_port!.sendPort, LocationService.isolateName);
    _port!.listen((dynamic data) {
      if (data != null && _isConnected && _sharingEnabled) {
        final loc = LocationDto.fromJson(data as Map<String, dynamic>);
        // Update local map position
        _currentPosition = geo.Position(
          longitude: loc.longitude,
          latitude: loc.latitude,
          timestamp: DateTime.now(),
          accuracy: loc.accuracy,
          altitude: loc.altitude,
          altitudeAccuracy: 0.0,
          heading: loc.heading,
          headingAccuracy: 0.0,
          speed: loc.speed,
          speedAccuracy: loc.speedAccuracy,
        );
        _moveMapTo(loc.latitude, loc.longitude);
      }
    });

    BackgroundLocator.isServiceRunning().then((isRunning) {
      if (isRunning) {
        setState(() {
          _status = 'Background location service is still running from previous session.';
        });
      }
    });
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _socketSubscription?.cancel();
    IsolateNameServer.removePortNameMapping(LocationService.isolateName);
    _port?.close();
    _channel?.sink.close();
    _nameController.dispose();
    _roomController.dispose();
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _connectAndJoin({bool isReconnect = false}) async {
    FocusScope.of(context).unfocus();
    final name = _nameController.text.trim();
    final roomCode = _roomController.text.trim().toUpperCase();
    final serverUrl = _serverController.text.trim();

    if (name.isEmpty || roomCode.isEmpty || serverUrl.isEmpty) {
      setState(() {
        _status = 'Name, family code, and relay URL are all required.';
      });
      return;
    }

    _lastIntent = _ConnectionIntent(name: name, roomCode: roomCode, serverUrl: serverUrl);
    _autoReconnectEnabled = true;
    _reconnectTimer?.cancel();

    setState(() {
      _isJoining = true;
      _status = isReconnect ? 'Reconnecting to relay…' : 'Checking permission and connecting…';
    });

    final permissionReady = await _ensureLocationReady();
    if (!permissionReady) {
      setState(() {
        _isJoining = false;
      });
      return;
    }

    await _disconnect(clearState: false, allowReconnect: false);

    try {
      final channel = WebSocketChannel.connect(Uri.parse(serverUrl));
      _channel = channel;
      _socketSubscription = channel.stream.listen(
        _handleSocketMessage,
        onError: (Object error) => _handleDisconnect('Relay connection failed: $error'),
        onDone: () => _handleDisconnect('Relay disconnected.'),
      );

      channel.sink.add(jsonEncode({
        'type': 'join',
        'name': name,
        'roomCode': roomCode,
        'isSharing': _sharingEnabled || !isReconnect,
      }));

      setState(() {
        _sharingEnabled = true;
        _roomCode = roomCode;
        _isConnected = true;
        _status = 'Connected. Waiting for room state…';
        _reconnectAttempts = 0;
      });

      _startPingLoop();
      await _publishCurrentLocation(); // Get immediate First fix for UI
      await _startLocationService(name, roomCode, serverUrl); // Start persistent background worker
    } catch (error) {
      _handleDisconnect('Could not connect to relay: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isJoining = false;
        });
      }
    }
  }

  void _handleDisconnect(String message) {
    if (!mounted) return;
    setState(() {
      _isConnected = false;
      _status = message;
    });
    _pingTimer?.cancel();
    if (_autoReconnectEnabled) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_lastIntent == null || _isConnected || _isJoining) {
      return;
    }
    _reconnectTimer?.cancel();
    final delaySeconds = (_reconnectAttempts < 5 ? _reconnectAttempts + 1 : 5) * 2;
    _reconnectAttempts += 1;
    setState(() {
      _status = 'Relay offline. Retrying in ${delaySeconds}s…';
    });
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (mounted && _autoReconnectEnabled) {
        _connectAndJoin(isReconnect: true);
      }
    });
  }

  Future<bool> _ensureLocationReady() async {
    final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _status = 'Location services are off. Turn them on first.';
      });
      return false;
    }

    var permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }

    if (permission == geo.LocationPermission.denied || permission == geo.LocationPermission.deniedForever) {
      setState(() {
        _status = 'Permission not granted. This app only shares location with consent.';
      });
      return false;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      if (permission == geo.LocationPermission.whileInUse) {
        setState(() {
          _status = 'Connected with foreground location access. For better background updates, enable Always access in system settings if you want that behavior.';
        });
      }
    }

    return true;
  }

  geo.LocationSettings _locationSettings() {
    if (Platform.isAndroid) {
      return geo.AndroidSettings(
        accuracy: geo.LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 4),
        foregroundNotificationConfig: const geo.ForegroundNotificationConfig(
          notificationTitle: 'Family Locator is sharing location',
          notificationText: 'Your live location is being shared with your family.',
          enableWakeLock: true,
        ),
      );
    }
    if (Platform.isIOS) {
      return geo.AppleSettings(
        accuracy: geo.LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    }
    return const geo.LocationSettings(
      accuracy: geo.LocationAccuracy.best,
      distanceFilter: 5,
    );
  }

  Future<void> _publishCurrentLocation() async {
    try {
      final position = await geo.Geolocator.getCurrentPosition(locationSettings: _locationSettings());
      _currentPosition = position;
      _sendLocation(position);
      _moveMapTo(position.latitude, position.longitude);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _status = 'Connected, but the first location fix is still pending.';
      });
    }
  }

  Future<void> _startLocationService(String name, String roomCode, String serverUrl) async {
    // Save info for background isolate
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fl_name', name);
    await prefs.setString('fl_roomCode', roomCode);
    await prefs.setString('fl_serverUrl', serverUrl);
    await prefs.setBool('fl_isSharing', _sharingEnabled || !(_lastIntent == null));

    await BackgroundLocator.registerLocationUpdate(
      LocationService.callback,
      iosSettings: const IOSSettings(
        accuracy: LocationAccuracy.NAVIGATION,
        distanceFilter: 5.0,
        showsBackgroundLocationIndicator: true,
      ),
      autoStop: false,
      androidSettings: const AndroidSettings(
        accuracy: LocationAccuracy.NAVIGATION,
        interval: 4,
        distanceFilter: 5.0,
        client: LocationClient.google,
        androidNotificationSettings: AndroidNotificationSettings(
          notificationChannelName: 'Location tracking',
          notificationTitle: 'Family Locator is active',
          notificationMsg: 'Sharing location in background',
          notificationBigMsg: 'Background location is on to keep the family locator map updated.',
          notificationIconColor: Colors.blue,
          notificationTapCallback: LocationService.notificationCallback,
        ),
      ),
    );
  }

  void _startPingLoop() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (_isConnected) {
        _channel?.sink.add(jsonEncode({'type': 'ping'}));
      }
    });
  }

  void _sendLocation(geo.Position position) {
    _channel?.sink.add(jsonEncode({
      'type': 'location',
      'lat': position.latitude,
      'lng': position.longitude,
      'accuracy': position.accuracy,
      'isSharing': _sharingEnabled,
    }));
    if (!mounted) return;
    setState(() {
      _status = 'Sharing live location to family code ${_roomCode ?? '-'}. Last fix ±${position.accuracy.round()}m.';
    });
  }

  void _handleSocketMessage(dynamic raw) {
    final message = jsonDecode(raw as String) as Map<String, dynamic>;
    switch (message['type']) {
      case 'welcome':
        setState(() {
          _status = 'Relay connected. Joining room…';
        });
        break;
      case 'joined':
        setState(() {
          _memberId = message['memberId'] as String?;
          _roomCode = message['roomCode'] as String?;
          _status = 'Joined family code ${_roomCode ?? '-'}.';
        });
        break;
      case 'room_state':
        final currentId = _memberId ?? '';
        final members = (message['members'] as List<dynamic>)
            .map((entry) => FamilyMember.fromJson(Map<String, dynamic>.from(entry as Map), currentUserId: currentId))
            .toList();
        setState(() {
          _members = members;
          _status = 'Live room synced with ${members.length} member(s).';
        });
        final selected = members.where((member) => member.isCurrentUser && member.location != null).firstOrNull ??
            members.where((member) => member.location != null).firstOrNull;
        if (selected?.location case final location?) {
          _moveMapTo(location.latitude, location.longitude);
        }
        break;
      case 'pong':
        break;
      case 'error':
        setState(() {
          _status = 'Relay error: ${message['message']}';
        });
        break;
    }
  }

  Future<void> _toggleSharing(bool enabled) async {
    setState(() {
      _sharingEnabled = enabled;
    });
    // Send to UI socket and save to prefs for Background Isolate
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('fl_isSharing', enabled);
    _channel?.sink.add(jsonEncode({'type': 'sharing', 'isSharing': enabled}));
    
    if (enabled) {
      await _publishCurrentLocation();
    } else {
      setState(() {
        _status = 'Sharing paused on this device.';
      });
    }
  }

  Future<void> _manualRefresh() async {
    setState(() {
      _status = 'Refreshing location now…';
    });
    await _publishCurrentLocation();
  }

  void _recenterToBestMember() {
    final selected = _members.where((member) => member.isCurrentUser && member.location != null).firstOrNull ??
        _members.where((member) => member.location != null).firstOrNull;
    final location = selected?.location;
    if (location != null) {
      _moveMapTo(location.latitude, location.longitude);
      setState(() {
        _status = 'Map recentered to ${selected!.name}.';
      });
    }
  }

  Future<void> _openLocationSettings() async {
    await geo.Geolocator.openAppSettings();
  }

  Future<void> _disconnect({bool clearState = true, bool allowReconnect = false}) async {
    _autoReconnectEnabled = allowReconnect;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    await _socketSubscription?.cancel();
    await BackgroundLocator.unRegisterLocationUpdate();
    await _channel?.sink.close();
    _socketSubscription = null;
    _channel = null;
    if (!mounted) return;
    setState(() {
      _isConnected = false;
      _sharingEnabled = false;
      if (clearState) {
        _members = const [];
        _memberId = null;
        _roomCode = null;
        _status = 'Disconnected from relay.';
      }
    });
  }

  void _moveMapTo(double lat, double lng) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.move(LatLng(lat, lng), 15);
    });
  }

  void _selectMember(FamilyMember member) {
    if (member.location == null) return;
    
    setState(() {
      _selectedMemberId = member.id;
    });
    
    _moveMapTo(member.location!.latitude, member.location!.longitude);
  }

  Future<void> _inviteFamilyMember() async {
    final code = _roomCode ?? _roomController.text.trim().toUpperCase();
    if (code.isEmpty) return;
    
    final message = 'Join my family group on Family Locator! My code is $code';
    await Share.share(message);
  }

  Widget _buildSettingsCard(BuildContext context) {
    return Card(
      elevation: 4,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            'Connection Settings',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(_isConnected ? 'Connected to $_roomCode' : 'Not connected'),
          initiallyExpanded: !_isConnected,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Visible, consent-based family sharing',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _serverController,
                    decoration: const InputDecoration(
                      labelText: 'Relay URL',
                      hintText: 'ws://192.168.4.64:8081',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Your name',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _roomController,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Family code',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Everyone must knowingly install the app and join the same family code. This project does not support hidden tracking.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: _isJoining ? null : _connectAndJoin,
                        icon: const Icon(Icons.link),
                        label: Text(_isConnected ? 'Reconnect now' : 'Connect & share'),
                      ),
                      if (_isConnected)
                        OutlinedButton.icon(
                          onPressed: () => _toggleSharing(!_sharingEnabled),
                          icon: Icon(_sharingEnabled ? Icons.pause_circle : Icons.play_circle),
                          label: Text(_sharingEnabled ? 'Pause sharing' : 'Resume sharing'),
                        ),
                      OutlinedButton.icon(
                        onPressed: _openLocationSettings,
                        icon: const Icon(Icons.settings),
                        label: const Text('App settings'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        _isConnected ? Icons.cloud_done : Icons.cloud_off,
                        color: _isConnected ? Colors.green : Colors.orange,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_status ?? '', style: Theme.of(context).textTheme.bodySmall)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMembersBottomSheet(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.35,
      minChildSize: 0.15,
      maxChildSize: 0.5,
      builder: (BuildContext context, ScrollController scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: const Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                spreadRadius: 2,
              )
            ],
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Family Members (${_members.length})',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    TextButton.icon(
                      onPressed: _inviteFamilyMember,
                      icon: const Icon(Icons.person_add),
                      label: const Text('Invite'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _members.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Text(
                            _isConnected
                                ? 'Waiting for others to join...'
                                : 'Connect to a family code to see members.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _members.length,
                        itemBuilder: (context, index) {
                          final member = _members[index];
                          final isSelected = member.id == _selectedMemberId;
                          return ListTile(
                            onTap: () => _selectMember(member),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: isSelected 
                                ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)
                                : BorderSide.none,
                            ),
                            tileColor: isSelected
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context).colorScheme.surfaceContainerHighest,
                            leading: CircleAvatar(child: Text(member.name.isEmpty ? '?' : member.name.characters.first)),
                            title: Text(member.name),
                            subtitle: Text(
                              '${member.isCurrentUser ? 'You' : 'Family'} • ${member.isSharing ? 'Sharing' : 'Paused'}${member.lastUpdated == null ? '' : ' • ${_formatAgo(member.lastUpdated!)}'}',
                            ),
                            trailing: member.accuracy == null
                                ? null
                                : Text('±${member.accuracy!.round()}m', style: Theme.of(context).textTheme.bodySmall),
                          );
                        },
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleMembers = _members.where((member) => member.isSharing && member.location != null).toList();
    final initialCenter = visibleMembers.firstOrNull?.location ??
        (_currentPosition == null
            ? const LatLng(37.7749, -122.4194)
            : LatLng(_currentPosition!.latitude, _currentPosition!.longitude));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Family Locator'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Theme.of(context).colorScheme.surface.withOpacity(0.8)),
          ),
        ),
        actions: [
          IconButton(
            onPressed: _manualRefresh,
            icon: const Icon(Icons.my_location),
            tooltip: 'Refresh my location',
          ),
          IconButton(
            onPressed: _recenterToBestMember,
            icon: const Icon(Icons.center_focus_strong),
            tooltip: 'Recenter map',
          ),
          if (_isConnected)
            IconButton(
              onPressed: () => _disconnect(),
              icon: const Icon(Icons.link_off),
              tooltip: 'Disconnect',
            ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Background Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: initialCenter, initialZoom: 13),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.family_locator',
              ),
              MarkerLayer(
                markers: visibleMembers.map((member) {
                  final location = member.location!;
                  final isSelected = member.id == _selectedMemberId;
                  return Marker(
                    point: location,
                    width: 120,
                    height: 80,
                    child: GestureDetector(
                      onTap: () => _selectMember(member),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.orangeAccent
                                  : (member.isCurrentUser
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.secondaryContainer),
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: isSelected
                                  ? [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))]
                                  : null,
                            ),
                            child: Text(
                              member.name,
                              style: TextStyle(
                                color: (isSelected || member.isCurrentUser)
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Theme.of(context).colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Icon(
                            Icons.location_pin,
                            size: isSelected ? 36 : 28,
                            color: isSelected 
                              ? Colors.orangeAccent 
                              : (member.isCurrentUser ? Colors.redAccent : Colors.blueAccent),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          
          // Foreground Settings Card
          SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: _buildSettingsCard(context),
              ),
            ),
          ),
          
          // Bottom Sheet for Members
          _buildMembersBottomSheet(context),
        ],
      ),
    );
  }

  String _formatAgo(DateTime timestamp) {
    final delta = DateTime.now().difference(timestamp);
    if (delta.inSeconds < 10) {
      return 'just now';
    }
    if (delta.inMinutes < 1) {
      return '${delta.inSeconds}s ago';
    }
    if (delta.inHours < 1) {
      return '${delta.inMinutes}m ago';
    }
    return '${delta.inHours}h ago';
  }
}
