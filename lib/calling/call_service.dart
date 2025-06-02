import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:agora_rtc_engine/agora_rtc_engine.dart';

class CallService {
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;

  CallService._internal();

  final String appId = 'e699bb8476824950a5e0c382274bde54';
  final String tokenServerUrl = 'https://us-central1-reuse-45929.cloudfunctions.net/generateAgoraToken';
  RtcEngine? _engine;
  String? _currentToken;
  String? _currentChannelId;

  Future<void> initializeAgora() async {
    if (_engine != null) {
      print('Agora already initialized');
      return;
    }

    try {
      _engine = createAgoraRtcEngine();
      await _engine?.initialize(RtcEngineContext(appId: appId));
      
      // Enable video by default (can be disabled for audio-only calls)
      await _engine?.enableVideo();
      await _engine?.enableAudio();
      
      print('Agora initialized successfully');
    } catch (e) {
      print('Agora initialization error: $e');
      throw Exception('Failed to initialize Agora: $e');
    }
  }

  RtcEngine? get engine => _engine;
  String? get currentChannelId => _currentChannelId;

  Future<String?> fetchToken(String channelName, String uid) async {
    try {
      print('Fetching token for channel: $channelName, uid: $uid');
      
      // Try different parameter formats that your server might expect
      final requestBody = {
        'channelName': channelName,
        'channel': channelName,  // Alternative field name
        'uid': uid,
        'userId': uid,           // Alternative field name
        'role': 1,               // Publisher role
      };
      
      print('Request body: ${jsonEncode(requestBody)}');
      
      final response = await http.post(
        Uri.parse(tokenServerUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Try different possible token field names
        _currentToken = data['token'] ?? data['accessToken'] ?? data['rtcToken'];
        
        if (_currentToken != null) {
          print('Token fetched successfully');
          return _currentToken;
        } else {
          print('Token not found in response: $data');
          return null;
        }
      } else {
        print('Failed to fetch token: ${response.statusCode}');
        print('Response: ${response.body}');
        
        // Try alternative request format
        return await _fetchTokenAlternative(channelName, uid);
      }
    } catch (e) {
      print('Token fetch error: $e');
      return await _fetchTokenAlternative(channelName, uid);
    }
  }

  // Alternative token fetch method with different parameter structure
  Future<String?> _fetchTokenAlternative(String channelName, String uid) async {
    try {
      print('Trying alternative token fetch method...');
      
      final alternativeBody = {
        'channel': channelName,
        'uid': int.tryParse(uid) ?? uid,
        'role': 'publisher',
      };
      
      print('Alternative request body: ${jsonEncode(alternativeBody)}');
      
      final response = await http.post(
        Uri.parse(tokenServerUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(alternativeBody),
      );

      print('Alternative response status: ${response.statusCode}');
      print('Alternative response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _currentToken = data['token'] ?? data['accessToken'] ?? data['rtcToken'];
        
        if (_currentToken != null) {
          print('Token fetched successfully with alternative method');
          return _currentToken;
        }
      }
      
      print('Both token fetch methods failed');
      return null;
    } catch (e) {
      print('Alternative token fetch error: $e');
      return null;
    }
  }

  Future<bool> joinChannel(String token, String channelName, int uid) async {
    try {
      if (_engine == null) {
        print('Engine not initialized');
        return false;
      }

      print('Joining channel: $channelName with uid: $uid');
      
      await _engine?.joinChannel(
        token: token,
        channelId: channelName,
        uid: uid,
        options: const ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );

      _currentChannelId = channelName;
      print('Successfully joined channel: $channelName');
      return true;
    } catch (e) {
      print('Join channel error: $e');
      return false;
    }
  }

  Future<void> leaveChannel() async {
    try {
      if (_engine != null && _currentChannelId != null) {
        print('Leaving channel: $_currentChannelId');
        await _engine?.leaveChannel();
        _currentChannelId = null;
        print('Left channel successfully');
      }
    } catch (e) {
      print('Leave channel error: $e');
    }
  }

  Future<void> enableVideo() async {
    await _engine?.enableVideo();
  }

  Future<void> disableVideo() async {
    await _engine?.disableVideo();
  }

  Future<void> muteLocalAudio(bool muted) async {
    await _engine?.muteLocalAudioStream(muted);
  }

  Future<void> muteLocalVideo(bool muted) async {
    await _engine?.muteLocalVideoStream(muted);
  }

  Future<void> switchCamera() async {
    await _engine?.switchCamera();
  }

  void destroy() {
    try {
      print('Destroying Agora engine');
      _engine?.release();
      _engine = null;
      _currentToken = null;
      _currentChannelId = null;
      print('Agora engine destroyed');
    } catch (e) {
      print('Error destroying engine: $e');
    }
  }

  // Clean up method to be called when app is disposed
  void dispose() {
    destroy();
  }

  // Test method to check token server compatibility
  Future<void> testTokenServer() async {
    print('=== Testing Token Server ===');
    
    final testChannel = 'test_channel_123';
    final testUid = '12345';
    
    // Test different request formats
    final formats = [
      {
        'channelName': testChannel,
        'uid': testUid,
      },
      {
        'channel': testChannel,
        'uid': testUid,
        'role': 1,
      },
      {
        'channelName': testChannel,
        'userId': testUid,
        'role': 'publisher',
      },
      {
        'channel': testChannel,
        'uid': int.parse(testUid),
      },
    ];
    
    for (int i = 0; i < formats.length; i++) {
      print('--- Testing format ${i + 1} ---');
      try {
        final response = await http.post(
          Uri.parse(tokenServerUrl),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(formats[i]),
        );
        
        print('Format ${i + 1} - Status: ${response.statusCode}');
        print('Format ${i + 1} - Body: ${response.body}');
        
        if (response.statusCode == 200) {
          print('✅ Format ${i + 1} WORKS!');
          print('Successful format: ${jsonEncode(formats[i])}');
          break;
        }
      } catch (e) {
        print('Format ${i + 1} - Error: $e');
      }
    }
    
    print('=== Token Server Test Complete ===');
  }
}