import 'package:flutter/material.dart';
import 'screens/main_screen.dart';

void main() {
  // Flutter motoru ile native katman arasındaki köprülerin
  // güvenli kurulduğundan emin oluyoruz.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DuyguAnaliziApp());
}

class DuyguAnaliziApp extends StatelessWidget {
  const DuyguAnaliziApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Duygu Analizi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.orange,
        primaryColor: Colors.orange,
        scaffoldBackgroundColor: Colors.grey[50],
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: true,
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
        ),
      ),
      home: const MainScreen(),
    );
  }
}