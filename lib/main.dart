import 'package:flutter/material.dart';
import 'screens/main_screen.dart'; // Bir önceki adımda oluşturduğumuz UI dosyası

void main() {
  // Flutter motoru ile native katman arasındaki köprülerin 
  // güvenli bir şekilde kurulduğundan emin oluyoruz.
  WidgetsFlutterBinding.ensureInitialized();
  
  runApp(const DuyguAnaliziApp());
}

class DuyguAnaliziApp extends StatelessWidget {
  const DuyguAnaliziApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Duygu Analizi',
      debugShowCheckedModeBanner: false, // Sağ üstteki "DEBUG" yazısını kaldırır
      theme: ThemeData(
        // Psikoloji literatürüne uygun enerji ve pozitiflik teması
        primarySwatch: Colors.orange,
        primaryColor: Colors.orange,
        scaffoldBackgroundColor: Colors.grey[50],
        fontFamily: 'Roboto', // Veya projende tercih ettiğin başka bir font
        
        // AppBar genel tasarımı
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
        
        // Butonların genel tasarımı
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
      // Uygulama açıldığında doğrudan bizim yazdığımız arayüze yönlendiriyoruz
      home: const MainScreen(),
    );
  }
}