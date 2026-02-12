// tpreference.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // <-- ADD
import 'TLOGIN.dart';

class TenantPref extends StatefulWidget {
  const TenantPref({super.key});

  @override
  State<TenantPref> createState() => _TenantPrefState();
}

class _TenantPrefState extends State<TenantPref> {
  final Color bgColor = const Color(0xFF00324E);
  final Color cardColor = Colors.grey.shade200;

  // DEFAULTS (same as before)
  Map<String, String> preferences = {
    "Pet-Friendly": "Yes",
    "Open to all": "Yes",
    "Common CR": "Yes",
    "Occupation": "Student Only",
    "Smoking": "Non-Smoker Only",
    "Location": "Near UM",
    "WiFi": "Yes",
  };

  final Map<String, int> weights = {
    "Location": 3,
    "WiFi": 2,
    "Pet-Friendly": 2,
    "Occupation": 1,
    "Smoking": 1,
    "Open to all": 1,
    "Common CR": 1,
  };

  // ... (icons, dropdownOptions, scoreRoom, getters unchanged)

  Future<void> _saveToSupabase() async {
    final sb = Supabase.instance.client;
    final user = sb.auth.currentUser;
    if (user == null) {
      // if not logged in, just continue (or navigate to login)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please login first.')));
      return;
    }

    final payload = {
      'user_id': user.id,
      'prefs': preferences,
      'weights': weights,
    };

    // upsert by primary key (user_id)
    await sb.from('tenant_preferences').upsert(payload);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Preferences saved ✅')));
  }

  @override
  Widget build(BuildContext context) {
    // ... (UI unchanged above)

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            // ... (cards unchanged)
            children: [
              // ... (cards)
              const SizedBox(height: 40),
              Center(
                child: SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[300],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () async {
                      await _saveToSupabase(); // <-- SAVE
                      // proceed (you can route anywhere you want)
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const LoginT()),
                      );
                    },
                    child: const Text(
                      'CONTINUE',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
