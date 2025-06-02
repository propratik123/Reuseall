import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'joined_call_screen.dart';
import 'call_service.dart';

class JoiningCallScreen extends StatefulWidget {
  final bool isVideoCall;
  final String channelId;
  final int callerUid;
  final int receiverUid;
  final String callerName;
  final String receiverName;
  final String callerUserId;   // Real Firebase Auth UID
  final String receiverUserId; // Real Firebase Auth UID

  const JoiningCallScreen({
    super.key,
    required this.isVideoCall,
    required this.channelId,
    required this.callerUid,
    required this.receiverUid,
    required this.callerName,
    required this.receiverName,
    required this.callerUserId,
    required this.receiverUserId,
  });

  @override
  State<JoiningCallScreen> createState() => _JoiningCallScreenState();
}

class _JoiningCallScreenState extends State<JoiningCallScreen> {
  bool _isJoined = false;
  bool _callStarted = false;
  String _status = "Initializing...";
  Timer? _statusCheckTimer;
  StreamSubscription<DocumentSnapshot>? _callStatusListener;

  @override
  void initState() {
    super.initState();
    print('=== JOINING CALL SCREEN INITIALIZED ===');
    print('Channel ID: ${widget.channelId}');
    print('Caller UID (Agora): ${widget.callerUid}');
    print('Receiver UID (Agora): ${widget.receiverUid}');
    print('Caller User ID (Firebase): ${widget.callerUserId}');
    print('Receiver User ID (Firebase): ${widget.receiverUserId}');
    print('Caller Name: ${widget.callerName}');
    print('Receiver Name: ${widget.receiverName}');
    print('Is Video Call: ${widget.isVideoCall}');
    _startCall();
  }

  @override
  void dispose() {
    print('=== JOINING CALL SCREEN DISPOSING ===');
    _statusCheckTimer?.cancel();
    _callStatusListener?.cancel();
    
    if (!_callStarted) {
      print('Cancelling call on dispose...');
      _cancelCall();
    }
    super.dispose();
  }

  Future<void> _startCall() async {
    try {
      print('🚀 STARTING CALL PROCESS');
      
      setState(() {
        _status = "Setting up call...";
      });

      final callService = CallService();
      await callService.initializeAgora();
      print('✅ Agora initialized');

      setState(() {
        _status = "Getting call token...";
      });

      final token = await callService.fetchToken(
        widget.channelId, 
        widget.callerUid.toString()
      );
      
      if (token == null) {
        print('❌ Failed to get token');
        setState(() {
          _status = "Failed to setup call";
        });
        _showErrorAndReturn("Failed to get call token");
        return;
      }
      print('✅ Token received');

      setState(() {
        _status = "Joining call...";
      });

      final joined = await callService.joinChannel(
        token, 
        widget.channelId, 
        widget.callerUid
      );

      if (!joined) {
        print('❌ Failed to join channel');
        _showErrorAndReturn("Failed to join call");
        return;
      }
      print('✅ Joined Agora channel successfully');

      setState(() {
        _status = "Notifying ${widget.receiverName}...";
      });

      // Create call document using REAL Firebase UID
      print('📝 Creating call document for receiver: ${widget.receiverUserId}');
      print('Document path: calls/${widget.receiverUserId}');

      final callData = {
        'channelId': widget.channelId,
        'callerUid': widget.callerUid,         // Agora UID (hashCode)
        'receiverUid': widget.receiverUid,     // Agora UID (hashCode)
        'callerUserId': widget.callerUserId,   // Real Firebase UID
        'receiverUserId': widget.receiverUserId, // Real Firebase UID
        'callerName': widget.callerName,
        'receiverName': widget.receiverName,
        'isVideoCall': widget.isVideoCall,
        'status': 'ringing',
        'timestamp': FieldValue.serverTimestamp(),
      };

      print('Call data: $callData');

      await FirebaseFirestore.instance
          .collection('calls')
          .doc(widget.receiverUserId) // Use REAL Firebase UID
          .set(callData);

      print('✅ Call document created successfully');

      // Verify document creation
      final verifyDoc = await FirebaseFirestore.instance
          .collection('calls')
          .doc(widget.receiverUserId)
          .get();
      
      print('✅ Document verification - Exists: ${verifyDoc.exists}');
      if (verifyDoc.exists) {
        print('Verified document data: ${verifyDoc.data()}');
      }

      setState(() {
        _isJoined = true;
        _status = "Calling ${widget.receiverName}...";
      });

      // Start listening for call status changes
      _listenForCallStatusChanges();

    } catch (e) {
      print('❌ Error starting call: $e');
      _showErrorAndReturn("Failed to start call: $e");
    }
  }

  void _listenForCallStatusChanges() {
    print('👂 Setting up call status listener');
    
    // Listen to the call document for status changes using REAL Firebase UID
    _callStatusListener = FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.receiverUserId) // Use REAL Firebase UID
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
      
      print('=== CALL STATUS SNAPSHOT RECEIVED ===');
      print('Document exists: ${snapshot.exists}');
      print('Is from cache: ${snapshot.metadata.isFromCache}');
      
      if (!mounted) {
        print('Widget not mounted, ignoring snapshot');
        return;
      }
      
      if (!snapshot.exists) {
        print('📴 Call document deleted - call was cancelled/rejected');
        setState(() {
          _status = "Call ended";
        });
        _showErrorAndReturn("Call was rejected or cancelled");
        return;
      }

      final data = snapshot.data()!;
      final status = data['status'] as String;
      print('📞 Call status updated: $status');

      switch (status) {
        case 'ringing':
          setState(() {
            _status = "Calling ${widget.receiverName}...";
          });
          break;
        
        case 'accepted':
          print('🎉 CALL ACCEPTED! Navigating to joined call screen');
          setState(() {
            _status = "Call accepted! Connecting...";
          });
          _navigateToJoinedCall();
          break;
        
        case 'rejected':
          print('❌ Call rejected by receiver');
          setState(() {
            _status = "Call rejected";
          });
          _showErrorAndReturn("${widget.receiverName} rejected the call");
          break;
        
        case 'ended':
          print('📴 Call ended');
          setState(() {
            _status = "Call ended";
          });
          _showErrorAndReturn("Call was ended");
          break;
      }
    }, onError: (error) {
      print('❌ Call status listener error: $error');
    });

    // Timeout timer
    _statusCheckTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && !_callStarted) {
        print('⏰ Call timeout');
        setState(() {
          _status = "Call timeout";
        });
        _showErrorAndReturn("No response from ${widget.receiverName}");
      }
    });
    
    print('✅ Call status listener setup complete');
  }

  void _navigateToJoinedCall() {
    if (!mounted || _callStarted) {
      return;
    }
    
    setState(() {
      _callStarted = true;
    });

    final callService = CallService();
    
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => JoinedCallScreen(
          engine: callService.engine!,
          isVideoCall: widget.isVideoCall,
          channelId: widget.channelId,
          localUid: widget.callerUid,
          isCaller: true,
          callerName: widget.callerName,
          receiverName: widget.receiverName,
        ),
      ),
    );
  }

  Future<void> _cancelCall() async {
    try {
      print('🚫 CANCELLING CALL');
      
      // Update call status using REAL Firebase UID
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(widget.receiverUserId)
          .update({'status': 'ended'});
      
      // Delete after delay
      Timer(const Duration(seconds: 2), () async {
        try {
          await FirebaseFirestore.instance
              .collection('calls')
              .doc(widget.receiverUserId)
              .delete();
          print('✅ Call document deleted');
        } catch (e) {
          print('❌ Error deleting call document: $e');
        }
      });
      
      if (_isJoined) {
        final callService = CallService();
        await callService.leaveChannel();
      }
    } catch (e) {
      print('❌ Error canceling call: $e');
    }
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

  void _endCall() async {
    await _cancelCall();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Status bar
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              child: Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
              ),
            ),
            
            // Main content
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Call icon
                    Container(
                      padding: const EdgeInsets.all(30),
                      decoration: BoxDecoration(
                        color: widget.isVideoCall ? Colors.blue : Colors.green,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (widget.isVideoCall ? Colors.blue : Colors.green)
                                .withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Icon(
                        widget.isVideoCall ? Icons.videocam : Icons.call,
                        color: Colors.white,
                        size: 60,
                      ),
                    ),
                    
                    const SizedBox(height: 30),
                    
                    Text(
                      widget.receiverName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    
                    const SizedBox(height: 10),
                    
                    Text(
                      widget.isVideoCall ? "Video Call" : "Voice Call",
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                    
                    const SizedBox(height: 40),
                    
                    if (!_callStarted) ...[
                      const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                      const SizedBox(height: 20),
                    ],

                    if (_status.contains("Calling")) ...[
                      const Text(
                        "Ringing...",
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            
            // End call button
            Container(
              padding: const EdgeInsets.all(30),
              child: GestureDetector(
                onTap: _endCall,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.call_end,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}