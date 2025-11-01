import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const String PUSHER_API_KEY =
    const String.fromEnvironment('PUSHER_API_KEY', defaultValue: '');
const String PUSHER_CLUSTER =
    const String.fromEnvironment('PUSHER_CLUSTER', defaultValue: '');
const String PUSHER_HOST =
    const String.fromEnvironment('PUSHER_HOST', defaultValue: '');
const String PUSHER_CHANNEL =
    const String.fromEnvironment('PUSHER_CHANNEL', defaultValue: '');
const String PUSHER_EVENT =
    const String.fromEnvironment('PUSHER_EVENT', defaultValue: 'client-event');
const String PUSHER_DATA =
    const String.fromEnvironment('PUSHER_DATA', defaultValue: 'test');
const String PUSHER_PORT =
    const String.fromEnvironment('PUSHER_PORT', defaultValue: '443');
const String PUSHER_ENCRYPTED =
    const String.fromEnvironment('PUSHER_ENCRYPTED', defaultValue: 'true');
const String PUSHER_AUTH_ENDPOINT =
    const String.fromEnvironment('PUSHER_AUTH_ENDPOINT', defaultValue: '');

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  WebSocketChannel? _channel;
  bool _isConnected = false;
  final _apiKey = TextEditingController(text: PUSHER_API_KEY);
  final _cluster = TextEditingController(text: PUSHER_CLUSTER);
  final _port = TextEditingController(text: PUSHER_PORT);
  bool _useTLS = PUSHER_ENCRYPTED == 'true';
  final _authEndpoint = TextEditingController(text: PUSHER_AUTH_ENDPOINT);
  final _host = TextEditingController(text: PUSHER_HOST);
  final _channelName = TextEditingController(text: PUSHER_CHANNEL);
  final _eventName = TextEditingController(text: PUSHER_EVENT);
  final _data = TextEditingController(text: PUSHER_DATA);
  final _channelFormKey = GlobalKey<FormState>();
  final _eventFormKey = GlobalKey<FormState>();

  String _log = '';

  void log(String text) {
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceFirst('T', ' ')
        .split('.')
        .first;
    final logEntry = "[$timestamp] $text";
    print("LOG: $logEntry");
    setState(() {
      _log = "$logEntry\n$_log";
    });
  }

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  void onDisconnectPressed() {
    if (_channel == null) return;
    try {
      _channel!.sink.close();
    } catch (e) {
      log("ERROR closing channel: $e");
    } finally {
      _channel = null;
      _isConnected = false;
      setState(() {});
      log("Disconnected");
    }
  }

  void onConnectPressed() async {
    if (!_channelFormKey.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).requestFocus(FocusNode());
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString("host", _host.text);
    prefs.setString("port", _port.text);
    prefs.setBool("useTLS", _useTLS);

    final scheme = _useTLS ? 'wss' : 'ws';
    final host = _host.text.isNotEmpty ? _host.text : 'localhost';
    final portSegment = (_port.text.isNotEmpty) ? ':${_port.text}' : '';
    final uri = Uri.parse("$scheme://$host$portSegment");

    log("Connecting to $uri...");
    try {
      _channel = WebSocketChannel.connect(uri);
      _isConnected = true;
      _channel!.stream.listen(
        (message) {
          log("onEvent: $message");
        },
        onError: (error) {
          log("onError: $error");
          _isConnected = false;
          setState(() {});
        },
        onDone: () {
          log("Connection closed by remote");
          _isConnected = false;
          setState(() {});
        },
      );
      log("Connected to $uri");
      setState(() {});
    } catch (e) {
      log("ERROR: $e");
      _isConnected = false;
      _channel = null;
      setState(() {});
    }
  }

  void onSubscribePressed() {
    log("Subscribe requested (POC)");
  }

  void onUnsubscribePressed() {
    log("Unsubscribe requested (POC)");
  }

  void onTriggerEventPressed() {
    if (_channel != null && _isConnected) {
      try {
        _channel!.sink.add(_data.text);
        log("Sent: ${_data.text}");
      } catch (e) {
        log("Failed to send message: $e");
      }
    } else {
      log("Cannot send message. Not connected.");
    }
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKey.text = prefs.getString("apiKey") ?? _apiKey.text;
      _cluster.text = prefs.getString("cluster") ?? _cluster.text;
      _host.text = prefs.getString("host") ?? _host.text;
      _channelName.text = prefs.getString("channelName") ?? _channelName.text;
      _eventName.text = prefs.getString("eventName") ?? _eventName.text;
      _data.text = prefs.getString("data") ?? _data.text;
      _port.text = prefs.getString("port") ?? _port.text;
      _useTLS = prefs.getBool("useTLS") ?? _useTLS;
      _authEndpoint.text =
          prefs.getString("authEndpoint") ?? _authEndpoint.text;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      home: Scaffold(
        appBar: AppBar(
          title: Text(_isConnected ? _channelName.text : 'WebSocket POC'),
        ),
        body: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      StateIndicator(
                        label: "Disconnected",
                        color: !_isConnected ? Colors.red : Colors.grey[800]!,
                      ),
                      StateIndicator(
                        label: "Connecting",
                        color: Colors.grey[800]!,
                      ),
                      StateIndicator(
                        label: "Connected",
                        color: _isConnected ? Colors.green : Colors.grey[800]!,
                      ),
                    ],
                  ),
                ),
                _isConnected ? _buildConnectedForm() : _buildDisconnectedForm(),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: _buildButtons(),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: SelectableText.rich(
                      TextSpan(
                        children: _log
                            .split('\n')
                            .map((line) => WidgetSpan(
                                  child: GestureDetector(
                                    onTap: () {
                                      Clipboard.setData(
                                          ClipboardData(text: line));
                                      scaffoldMessengerKey.currentState
                                          ?.showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                'Copied to clipboard: $line')),
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 2.0),
                                      child: Text(
                                        line,
                                        style: const TextStyle(
                                            fontFamily: 'monospace'),
                                      ),
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  ),
                )
              ],
            )),
      ),
    );
  }

  Widget _buildButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!_isConnected)
          ElevatedButton(
            onPressed: onConnectPressed,
            child: const Text('Connect'),
          ),
        if (_isConnected)
          ElevatedButton(
            onPressed: onDisconnectPressed,
            child: const Text('Disconnect'),
          ),
        if (_isConnected)
          ElevatedButton(
            onPressed: onTriggerEventPressed,
            child: const Text('Send Message'),
          ),
      ],
    );
  }

  Form _buildConnectedForm() {
    return Form(
      key: _eventFormKey,
      child: Column(children: <Widget>[
        TextFormField(
          controller: _data,
          decoration: const InputDecoration(
            labelText: 'Message',
          ),
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _channelName,
          decoration: const InputDecoration(
            labelText: 'Channel (not used in POC)',
          ),
        ),
      ]),
    );
  }

  Form _buildDisconnectedForm() {
    return Form(
      key: _channelFormKey,
      child: Column(children: <Widget>[
        TextFormField(
          controller: _host,
          decoration: const InputDecoration(
            labelText: 'Host (e.g. ws.localhost.strokefocus.net)',
          ),
        ),
        TextFormField(
          controller: _port,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Port (default: 443)',
          ),
        ),
        SwitchListTile(
          title: const Text('Use TLS'),
          value: _useTLS,
          onChanged: (v) => setState(() => _useTLS = v),
        ),
      ]),
    );
  }
}

class Led extends StatelessWidget {
  final Color color;
  final double size;

  const Led({Key? key, required this.color, this.size = 24}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bool isOff = color == Colors.grey[800];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: isOff
            ? []
            : [
                BoxShadow(
                  color: color.withOpacity(0.6),
                  blurRadius: 10,
                  spreadRadius: 3,
                ),
              ],
      ),
    );
  }
}

class StateIndicator extends StatelessWidget {
  final String label;
  final Color color;

  const StateIndicator({Key? key, required this.label, required this.color})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Led(color: color),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
