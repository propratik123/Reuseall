import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'call_service.dart';

class JoinedCallScreen extends StatefulWidget {
  final RtcEngine engine;
  final bool isVideoCall;
  final String channelId;
  final int localUid;
  final bool isCaller;
  final String callerName;
  final String receiverName;

  const JoinedCallScreen({
    super.key,
    required this.engine,
    required this.isVideoCall,
    required this.channelId,
    required this.localUid,
    required this.isCaller,
    required this.callerName,
    required this.receiverName,
  });

  @override
  State<JoinedCallScreen> createState() => _JoinedCallScreenState();
}

class _JoinedCallScreenState extends State<JoinedCallScreen> {
  int? _remoteUid;
  bool _localUserJoined = false;
  bool _isVideoMuted = false;
  bool _isAudioMuted = false;
  bool _isSpeakerOn = false;
  String _callStatus = "Connecting...";
  DateTime? _callStartTime;
  String _callDuration = "00:00";

  @override
  void initState() {
    super.initState();
    _setup();
    _startCallTimer();
  }

  @override
  void dispose() {
    _endCall();
    super.dispose();
  }

  Future<void> _setup() async {
    // Request permissions
    await [Permission.microphone, Permission.camera].request();

    // Configure video settings if video call
    if (widget.isVideoCall) {
      await widget.engine.enableVideo();
      await widget.engine.startPreview();
    } else {
      await widget.engine.disableVideo();
    }

    // Set up event handlers
    widget.engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          setState(() {
            _localUserJoined = true;
            _callStatus = widget.isCaller ? "Calling..." : "Connected";
          });
          print('Local user joined channel successfully');
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          setState(() {
            _remoteUid = remoteUid;
            _callStatus = "Connected";
            _callStartTime = DateTime.now();
          });
          print('Remote user $remoteUid joined');
        },
        onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
          setState(() {
            _remoteUid = null;
            _callStatus = "Call ended";
          });
          print('Remote user $remoteUid left channel');
          _showCallEndedAndReturn();
        },
        onConnectionStateChanged: (RtcConnection connection, ConnectionStateType state, ConnectionChangedReasonType reason) {
          print('Connection state changed: $state, reason: $reason');
          if (state == ConnectionStateType.connectionStateFailed) {
            _showErrorAndReturn("Connection failed");
          }
        },
        onRemoteVideoStateChanged: (RtcConnection connection, int remoteUid, RemoteVideoState state, RemoteVideoStateReason reason, int elapsed) {
          print('Remote video state changed: $state');
        },
        onRemoteAudioStateChanged: (RtcConnection connection, int remoteUid, RemoteAudioState state, RemoteAudioStateReason reason, int elapsed) {
          print('Remote audio state changed: $state');
        },
      ),
    );
  }

  void _startCallTimer() {
    Stream.periodic(const Duration(seconds: 1)).listen((_) {
      if (_callStartTime != null && mounted) {
        final duration = DateTime.now().difference(_callStartTime!);
        setState(() {
          _callDuration = _formatDuration(duration);
        });
      }
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      String hours = twoDigits(duration.inHours);
      return "$hours:$minutes:$seconds";
    }
    return "$minutes:$seconds";
  }

  void _showCallEndedAndReturn() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pop(context);
      }
    });
  }

  void _showErrorAndReturn(String error) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.red,
        ),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _endCall() async {
    try {
      final callService = CallService();
      await callService.leaveChannel();
    } catch (e) {
      print('Error ending call: $e');
    }
    
    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _toggleVideo() async {
    setState(() {
      _isVideoMuted = !_isVideoMuted;
    });
    await widget.engine.muteLocalVideoStream(_isVideoMuted);
  }

  Future<void> _toggleAudio() async {
    setState(() {
      _isAudioMuted = !_isAudioMuted;
    });
    await widget.engine.muteLocalAudioStream(_isAudioMuted);
  }

  Future<void> _switchCamera() async {
    await widget.engine.switchCamera();
  }

  Future<void> _toggleSpeaker() async {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });
    await widget.engine.setEnableSpeakerphone(_isSpeakerOn);
  }

  Widget _renderVideo() {
    if (_remoteUid != null) {
      return AgoraVideoView(
        controller: VideoViewController.remote(
          rtcEngine: widget.engine,
          canvas: VideoCanvas(uid: _remoteUid),
          connection: RtcConnection(channelId: widget.channelId),
        ),
      );
    } else {
      return Container(
        color: Colors.black87,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.isVideoCall ? Icons.videocam_off : Icons.person,
                color: Colors.white54,
                size: 80,
              ),
              const SizedBox(height: 20),
              Text(
                _callStatus,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _renderLocalPreview() {
    if (widget.isVideoCall && !_isVideoMuted) {
      return AgoraVideoView(
        controller: VideoViewController(
          rtcEngine: widget.engine,
          canvas: const VideoCanvas(uid: 0),
        ),
      );
    } else {
      return Container(
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Icon(
            Icons.videocam_off,
            color: Colors.white54,
            size: 40,
          ),
        ),
      );
    }
  }

  Widget _buildCallControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withOpacity(0.7),
            Colors.black.withOpacity(0.9),
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Audio toggle
          _buildControlButton(
            icon: _isAudioMuted ? Icons.mic_off : Icons.mic,
            color: _isAudioMuted ? Colors.red : Colors.white,
            backgroundColor: _isAudioMuted ? Colors.white : Colors.grey[700]!,
            onTap: _toggleAudio,
          ),
          
          // Video toggle (only for video calls)
          if (widget.isVideoCall)
            _buildControlButton(
              icon: _isVideoMuted ? Icons.videocam_off : Icons.videocam,
              color: _isVideoMuted ? Colors.red : Colors.white,
              backgroundColor: _isVideoMuted ? Colors.white : Colors.grey[700]!,
              onTap: _toggleVideo,
            ),
          
          // Speaker toggle (only for audio calls)
          if (!widget.isVideoCall)
            _buildControlButton(
              icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
              color: Colors.white,
              backgroundColor: _isSpeakerOn ? Colors.blue : Colors.grey[700]!,
              onTap: _toggleSpeaker,
            ),
          
          // Camera switch (only for video calls)
          if (widget.isVideoCall)
            _buildControlButton(
              icon: Icons.cameraswitch,
              color: Colors.white,
              backgroundColor: Colors.grey[700]!,
              onTap: _switchCamera,
            ),
          
          // End call
          _buildControlButton(
            icon: Icons.call_end,
            color: Colors.white,
            backgroundColor: Colors.red,
            onTap: _endCall,
            isLarge: true,
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    required Color backgroundColor,
    required VoidCallback onTap,
    bool isLarge = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(isLarge ? 20 : 15),
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: color,
          size: isLarge ? 30 : 25,
        ),
      ),
    );
  }

  Widget _buildCallInfo() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            widget.isCaller ? widget.receiverName : widget.callerName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _callStatus,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
            ),
          ),
          if (_callStartTime != null) ...[
            const SizedBox(height: 4),
            Text(
              _callDuration,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Main video/audio area
            if (widget.isVideoCall) ...[
              // Remote video (full screen)
              Positioned.fill(
                child: _renderVideo(),
              ),
              
              // Local video preview (small overlay)
              Positioned(
                top: 60,
                right: 20,
                child: Container(
                  width: 120,
                  height: 160,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24, width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _renderLocalPreview(),
                  ),
                ),
              ),
            ] else ...[
              // Audio call interface
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.blue.withOpacity(0.3),
                        Colors.black,
                      ],
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.2),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.blue, width: 3),
                          ),
                          child: const Icon(
                            Icons.call,
                            color: Colors.blue,
                            size: 70,
                          ),
                        ),
                        const SizedBox(height: 30),
                        _buildCallInfo(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            
            // Top info (for video calls)
            if (widget.isVideoCall)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.7),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: _buildCallInfo(),
                ),
              ),
            
            // Bottom controls
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildCallControls(),
            ),
          ],
        ),
      ),
    );
  }
}