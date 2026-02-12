import 'package:flutter/material.dart';
import 'package:smart_finder/LANDLORD/AVAILABLEROOM.dart';
import 'package:smart_finder/LANDLORD/DASHBOARD.dart';
import 'package:smart_finder/LANDLORD/LOGIN.dart';
import 'package:smart_finder/TENANT/TAPARTMENT.dart';
import 'package:smart_finder/TENANT/TLOGIN.dart';
import 'package:smart_finder/TENANT/TREGISTER.dart';
import 'package:smart_finder/TOUR.dart';
import 'package:smart_finder/WELCOME.dart';
import 'package:smart_finder/splash_screen.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url:
        'https://vvvkosldcbdgnxovstwj.supabase.co', // Replace with your Supabase URL
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ2dmtvc2xkY2JkZ254b3ZzdHdqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTY0NzU2OTksImV4cCI6MjA3MjA1MTY5OX0.HrW42OpeA954q7yBAxtqQ4ftRtnjpY_cekN02cLGNOs', // Replace with your public anon key
  );
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});


  @override
  Widget build(BuildContext context) {
    return const MaterialApp(debugShowCheckedModeBanner: false, home: Welcome());
  }
}

//MY EDITTING AREA                        