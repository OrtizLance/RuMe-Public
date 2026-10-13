import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:rume/firebase/firebase_options.dart';
import 'package:rume/go_router.dart';
import 'package:rume/paymongo/deep_link_service.dart';
import 'package:rume/seeker_module/property_search/places_API/places_api.dart';
import 'package:rume/auth_notifier.dart';



Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print('Handling a background message: ${message.messageId}');
}


late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;


late AndroidNotificationChannel channel;

bool isFlutterLocalNotificationsInitialized = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  
  await Firebase.initializeApp(name: "rume", options: DefaultFirebaseOptions.currentPlatform);
  await PlacesApi.initialize();

  
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  authStateNotifier.initialize();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final DeepLinkService _deepLinkService = DeepLinkService();

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _deepLinkService.init(context);
    });

    
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user != null) {
        
        _requestPermissionAndSaveToken(user.uid);
      }
    });

    
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      print("🔄 New FCM Token: $newToken");
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _saveTokenToFirestore(newToken, user.uid);
      }
    });

    
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;
      if (notification != null && android != null) {
        flutterLocalNotificationsPlugin.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              channel.id,
              channel.name,
              channelDescription: channel.description,
              icon: '@mipmap/launcher_icon', 
            ),
          ),
        );
      }
    });
  }

  Future<void> _setupFlutterNotifications() async {
    if (isFlutterLocalNotificationsInitialized) {
      return;
    }
    channel = const AndroidNotificationChannel(
      'high_importance_channel', 
      'High Importance Notifications', 
      description:
          'This channel is used for important notifications.', 
      importance: Importance.high,
    );

    flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    isFlutterLocalNotificationsInitialized = true;
  }

  Future<void> _saveTokenToFirestore(String? token, String userId) async {
    if (token == null) return;
    await FirebaseFirestore.instance.collection('users').doc(userId).set({
      'fcmToken': token,
      'lastTokenUpdate': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _requestPermissionAndSaveToken(String userId) async {
    await _setupFlutterNotifications();
    NotificationSettings settings = await FirebaseMessaging.instance
        .requestPermission();

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      String? token = await FirebaseMessaging.instance.getToken();
      await _saveTokenToFirestore(token, userId);
    } else {
      print('🚫 User declined or has not accepted notification permission');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'RuMe App',
      theme: ThemeData(
        primaryColor: Colors.blueAccent,
        fontFamily: 'Poppins',
      ),
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
    );
  }
}
