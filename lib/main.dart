import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_screen.dart';
import 'home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // Firebase initialization

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter App with Auth Persistence',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: AuthWrapper(), // Use AuthWrapper instead of direct LoginScreen
      debugShowCheckedModeBanner: false,
    );
  }
}

// AuthWrapper to check if user is already logged in
class AuthWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Show loading spinner while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Loading...',
                    style: TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
          );
        }
        
        // If user is logged in, go to HomeScreen
        if (snapshot.hasData && snapshot.data != null) {
          print('User already logged in: ${snapshot.data!.email}');
          return HomeScreen();
        }
        
        // If user is not logged in, go to LoginScreen
        print('User not logged in, showing LoginScreen');
        return LoginScreen();
      },
    );
  }
}