import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'joining_call_screen.dart';

class CallScreen extends StatefulWidget {
  final String userName;
  final String profileImageUrl;
  final String userId;

  const CallScreen({
    super.key,
    required this.userName,
    required this.profileImageUrl,
    required this.userId,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  String _currentUserName = "You";

  @override
  void initState() {
    super.initState();
    _getCurrentUserName();
  }

  Future<void> _getCurrentUserName() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get();
        
        if (userDoc.exists) {
          setState(() {
            _currentUserName = userDoc.data()?['name'] ?? "You";
          });
        }
      }
    } catch (e) {
      print('Error getting current user name: $e');
    }
  }

  // Get current logged-in user ID
  String get currentUserId {
    final currentUser = FirebaseAuth.instance.currentUser;
    return currentUser?.uid ?? 'unknown_user';
  }

  void _startCall(BuildContext context, bool isVideoCall) {
    // Create shorter, more compatible channel ID
    final channelId = _generateChannelId(currentUserId, widget.userId);
    
    print('Starting call with channel ID: $channelId');
    print('Caller UID: ${currentUserId.hashCode}');
    print('Receiver UID: ${widget.userId.hashCode}');
    print('Caller Name: $_currentUserName');
    print('Receiver Name: ${widget.userName}');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => JoiningCallScreen(
          isVideoCall: isVideoCall,
          channelId: channelId,
          callerUid: currentUserId.hashCode,
          receiverUid: widget.userId.hashCode,
          callerName: _currentUserName,
          receiverName: widget.userName,
          callerUserId: currentUserId,     // Real Firebase UID
          receiverUserId: widget.userId,   // Real Firebase UID
        ),
      ),
    );
  }

  // Generate shorter, compatible channel ID
  String _generateChannelId(String uid1, String uid2) {
    final sortedIds = [uid1, uid2]..sort();
    // Create a shorter hash-based channel ID
    final combinedId = '${sortedIds[0]}_${sortedIds[1]}';
    final hash = combinedId.hashCode.abs().toString();
    // Ensure channel ID is not too long and contains only alphanumeric characters
    final channelId = 'ch_$hash';
    // Safely limit to 20 characters or the actual length if shorter
    return channelId.length > 20 ? channelId.substring(0, 20) : channelId;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          "Call ${widget.userName}",
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Profile image with border
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24, width: 4),
              ),
              child: CircleAvatar(
                radius: 80,
                backgroundImage: widget.profileImageUrl.isNotEmpty 
                    ? NetworkImage(widget.profileImageUrl)
                    : null,
                backgroundColor: Colors.grey[300],
                child: widget.profileImageUrl.isEmpty 
                  ? Text(
                      widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : 'U',
                      style: const TextStyle(fontSize: 40, color: Colors.white),
                    )
                  : null,
              ),
            ),
            
            const SizedBox(height: 30),
            
            // User name
            Text(
              widget.userName,
              style: const TextStyle(
                color: Colors.white, 
                fontSize: 28,
                fontWeight: FontWeight.w500,
              ),
            ),
            
            const SizedBox(height: 10),
            
            // Status text
            const Text(
              "Tap to start calling",
              style: TextStyle(
                color: Colors.grey, 
                fontSize: 16,
              ),
            ),
            
            const SizedBox(height: 60),
            
            // Call buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Audio Call Button
                Column(
                  children: [
                    GestureDetector(
                      onTap: () => _startCall(context, false),
                      child: Container(
                        padding: const EdgeInsets.all(25),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withOpacity(0.3),
                              blurRadius: 15,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.call,
                          color: Colors.white,
                          size: 35,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "Voice Call",
                      style: TextStyle(
                        color: Colors.white, 
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                
                // Video Call Button
                Column(
                  children: [
                    GestureDetector(
                      onTap: () => _startCall(context, true),
                      child: Container(
                        padding: const EdgeInsets.all(25),
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withOpacity(0.3),
                              blurRadius: 15,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.videocam,
                          color: Colors.white,
                          size: 35,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "Video Call",
                      style: TextStyle(
                        color: Colors.white, 
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 40),
            
            // Additional info
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                "Make sure you have a stable internet connection for the best call quality.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}