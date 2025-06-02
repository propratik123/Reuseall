import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'call_service.dart';
import 'joined_call_screen.dart';

class IncomingCallScreen extends StatelessWidget {
  final String channelId;
  final int callerUid;
  final int receiverUid;
  final bool isVideoCall;
  final String callerName;
  final String receiverName;

  const IncomingCallScreen({
    super.key,
    required this.channelId,
    required this.callerUid,
    required this.receiverUid,
    required this.isVideoCall,
    this.callerName = 'Unknown Caller',
    this.receiverName = 'You',
  });

  // Get current user's real Firebase UID
  String get _currentUserUID {
    final currentUser = FirebaseAuth.instance.currentUser;
    return currentUser?.uid ?? '';
  }

  void _acceptCall(BuildContext context) async {
    try {
      print('=== ACCEPTING CALL ===');
      print('Current user UID: $_currentUserUID');
      print('Channel ID: $channelId');
      print('Caller UID (Agora): $callerUid');
      print('Receiver UID (Agora): $receiverUid');

      if (_currentUserUID.isEmpty) {
        _showError(context, "User not logged in");
        return;
      }

      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );

      // Update call status to accepted using REAL Firebase UID
      print('📝 Updating call document: calls/$_currentUserUID');
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(_currentUserUID) // Use REAL Firebase UID
          .update({'status': 'accepted'});

      print('✅ Call status updated to accepted');

      final callService = CallService();
      await callService.initializeAgora();

      final token = await callService.fetchToken(channelId, receiverUid.toString());
      if (token == null) {
        Navigator.pop(context); // Remove loading dialog
        _showError(context, "Failed to get call token");
        return;
      }

      print('✅ Token received for joining channel');

      final joined = await callService.joinChannel(token, channelId, receiverUid);
      if (!joined) {
        Navigator.pop(context); // Remove loading dialog
        _showError(context, "Failed to join call");
        return;
      }

      print('✅ Successfully joined Agora channel');

      // Remove loading dialog
      Navigator.pop(context);

      // Navigate to joined call screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => JoinedCallScreen(
            engine: callService.engine!,
            isVideoCall: isVideoCall,
            channelId: channelId,
            localUid: receiverUid,
            isCaller: false,
            callerName: callerName,
            receiverName: receiverName,
          ),
        ),
      );
    } catch (e) {
      print('❌ Error accepting call: $e');
      Navigator.pop(context); // Remove loading dialog if still showing
      _showError(context, "Failed to accept call: $e");
    }
  }

  void _rejectCall(BuildContext context) async {
    try {
      print('=== REJECTING CALL ===');
      print('Current user UID: $_currentUserUID');

      if (_currentUserUID.isEmpty) {
        Navigator.pop(context);
        return;
      }

      // Update call status to rejected using REAL Firebase UID
      print('📝 Updating call status to rejected: calls/$_currentUserUID');
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(_currentUserUID) // Use REAL Firebase UID
          .update({'status': 'rejected'});

      print('✅ Call rejected successfully');

      // Delete the call document after a short delay
      Future.delayed(const Duration(seconds: 2), () async {
        try {
          await FirebaseFirestore.instance
              .collection('calls')
              .doc(_currentUserUID)
              .delete();
          print('✅ Call document deleted');
        } catch (e) {
          print('❌ Error deleting call document: $e');
        }
      });

      Navigator.pop(context);
    } catch (e) {
      print('❌ Error rejecting call: $e');
      Navigator.pop(context);
    }
  }

  void _showError(BuildContext context, String message) {
    print('💥 SHOWING ERROR: $message');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Debug info
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Colors.blue.withOpacity(0.1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Debug: Current UID = $_currentUserUID",
                    style: TextStyle(color: Colors.blue, fontSize: 10),
                  ),
                  Text(
                    "Channel: $channelId",
                    style: TextStyle(color: Colors.blue, fontSize: 10),
                  ),
                ],
              ),
            ),
            
            // Top section with caller info
            Expanded(
              flex: 2,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Incoming call text
                    const Text(
                      "Incoming Call",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Caller avatar/icon
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.grey[700],
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24, width: 3),
                      ),
                      child: Icon(
                        Icons.person,
                        color: Colors.white54,
                        size: 60,
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Caller name
                    Text(
                      callerName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    const SizedBox(height: 10),
                    
                    // Call type
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isVideoCall ? Icons.videocam : Icons.call,
                          color: Colors.white70,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isVideoCall ? "Video Call" : "Voice Call",
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            // Bottom section with call controls
            Expanded(
              flex: 1,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(30),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Ringing indicator
                    const Text(
                      "Ringing...",
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 30),
                    
                    // Call action buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Reject button
                        GestureDetector(
                          onTap: () => _rejectCall(context),
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
                        
                        // Accept button
                        GestureDetector(
                          onTap: () => _acceptCall(context),
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.call,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Button labels
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Text(
                          "Decline",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          "Accept",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}