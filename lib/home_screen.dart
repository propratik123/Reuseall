import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'login_screen.dart';
import 'calling/call_screen.dart';
import 'calling/incoming_call_screen.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<DocumentSnapshot>? _callListener;
  StreamSubscription<User?>? _authListener;
  bool _isIncomingCallShowing = false;
  String _currentUserId = '';
  String _debugStatus = 'Initializing...';

  final List<String> profileImages = [
    "https://upload.wikimedia.org/wikipedia/en/2/2f/Jerry_Mouse.png",
    "https://static.wikia.nocookie.net/mugen/images/3/39/Tom_be2af94.png/revision/latest/scale-to-width-down/230?cb=20211113004348",
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupAuthListener();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callListener?.cancel();
    _authListener?.cancel();
    super.dispose();
  }

  void _setupAuthListener() {
    print('Setting up auth listener...');
    
    // Listen to auth state changes
    _authListener = _auth.authStateChanges().listen((User? user) {
      print('=== AUTH STATE CHANGED ===');
      print('User: $user');
      
      if (user != null) {
        print('User logged in: ${user.uid}');
        print('User email: ${user.email}');
        _currentUserId = user.uid;
        
        setState(() {
          _debugStatus = 'Logged in as: ${user.email}';
        });
        
        // Setup incoming call listener
        _setupIncomingCallListener();
      } else {
        print('User logged out');
        _currentUserId = '';
        
        setState(() {
          _debugStatus = 'Not logged in';
        });
        
        // Cancel call listener
        _callListener?.cancel();
        _callListener = null;
        
        // Redirect to login
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => LoginScreen()),
        );
      }
    });
  }

  void _setupIncomingCallListener() {
    if (_currentUserId.isEmpty) {
      print('Cannot setup call listener: User ID is empty');
      return;
    }

    print('Setting up call listener for user: $_currentUserId');
    
    // Cancel existing listener
    _callListener?.cancel();

    // Listen for incoming calls
    _callListener = _firestore
        .collection('calls')
        .doc(_currentUserId) // Use real Firebase Auth UID
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
      
      print('=== CALL SNAPSHOT RECEIVED ===');
      print('Document path: calls/$_currentUserId');
      print('Document exists: ${snapshot.exists}');
      print('Is from cache: ${snapshot.metadata.isFromCache}');
      
      setState(() {
        _debugStatus = 'Last update: ${DateTime.now().toString().substring(11, 19)}';
      });
      
      if (snapshot.exists && mounted && !_isIncomingCallShowing) {
        final callData = snapshot.data()!;
        print('Call data received: $callData');
        
        final status = callData['status'] as String?;
        print('Call status: $status');
        
        if (status == 'ringing') {
          print('🔔 SHOWING INCOMING CALL SCREEN');
          _showIncomingCallScreen(callData);
        }
      } else if (!snapshot.exists && _isIncomingCallShowing) {
        print('Call document deleted, resetting flag');
        _isIncomingCallShowing = false;
      }
    }, onError: (error) {
      print('❌ CALL LISTENER ERROR: $error');
      setState(() {
        _debugStatus = 'Listener error: $error';
      });
    });

    print('✅ Call listener setup complete for: $_currentUserId');
  }

  void _showIncomingCallScreen(Map<String, dynamic> callData) {
    if (_isIncomingCallShowing) {
      print('Incoming call screen already showing');
      return;
    }

    _isIncomingCallShowing = true;
    
    final channelId = callData['channelId'] as String;
    final callerUid = callData['callerUid'] as int;
    final receiverUid = callData['receiverUid'] as int;
    final isVideoCall = callData['isVideoCall'] as bool? ?? false;
    final callerName = callData['callerName'] as String? ?? 'Unknown Caller';
    final receiverName = callData['receiverName'] as String? ?? 'You';

    print('📱 NAVIGATING TO INCOMING CALL');
    print('Channel: $channelId');
    print('Caller: $callerName ($callerUid)');
    print('Receiver: $receiverName ($receiverUid)');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => IncomingCallScreen(
          channelId: channelId,
          callerUid: callerUid,
          receiverUid: receiverUid,
          isVideoCall: isVideoCall,
          callerName: callerName,
          receiverName: receiverName,
        ),
      ),
    ).then((_) {
      print('Returned from incoming call screen');
      _isIncomingCallShowing = false;
    });
  }

  void _handleLogout() async {
    await _callListener?.cancel();
    await _authListener?.cancel();
    await _auth.signOut();
  }

  // Test method using REAL current user ID
  void _testIncomingCall() async {
    if (_currentUserId.isEmpty) {
      print('❌ Cannot test: No user logged in');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: No user logged in'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    print('Creating test call for user: $_currentUserId');
    
    try {
      await _firestore
          .collection('calls')
          .doc(_currentUserId) // Use REAL current user ID
          .set({
        'channelId': 'test_channel_${DateTime.now().millisecondsSinceEpoch}',
        'callerUid': 12345,
        'receiverUid': _currentUserId.hashCode,
        'callerName': 'Test Caller',
        'receiverName': 'You',
        'isVideoCall': false,
        'status': 'ringing',
        'timestamp': FieldValue.serverTimestamp(),
      });
      
      print('✅ Test call created successfully');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Test call created'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('❌ Error creating test call: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _debugCurrentUser() {
    final user = _auth.currentUser;
    print('=== CURRENT USER DEBUG ===');
    print('User: $user');
    print('UID: ${user?.uid}');
    print('Email: ${user?.email}');
    print('_currentUserId: $_currentUserId');
    print('========================');
    
    setState(() {
      _debugStatus = user != null 
          ? 'UID: ${user.uid}' 
          : 'No user';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Welcome"),
        actions: [
          // Logout
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: _handleLogout,
            tooltip: "Logout",
          ),
        ],
      ),
      body: _currentUserId.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text("Loading user data..."),
                ],
              ),
            )
          : StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('users').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text("Error loading users: ${snapshot.error}"),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(child: Text("No users found"));
                }

                List<DocumentSnapshot> users = snapshot.data!.docs;

                return ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    String uid = users[index].id;

                    // Skip current user
                    if (uid == _currentUserId) {
                      return SizedBox.shrink();
                    }

                    String name = users[index]['name'] ?? 'Unknown';
                    String profileImageUrl = profileImages[index % profileImages.length];

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage: NetworkImage(profileImageUrl),
                          backgroundColor: Colors.grey[300],
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text("Tap to call"),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => CallScreen(
                                userName: name,
                                profileImageUrl: profileImageUrl,
                                userId: uid,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}