import 'package:flutter/material.dart';
import 'package:smart_finder/USER.dart';
// Import your User page

class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF04364F),
      body: SafeArea(
        child: Stack(
          children: [
            Align(
              alignment: Alignment.bottomCenter,
              child: Image.asset(
                'assets/images/apartment.png',
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),

            // Main content
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 32.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  RichText(
                    text: const TextSpan(
                      children: [
                        TextSpan(
                          text: 'Find ',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        TextSpan(
                          text: 'Luxury\n',
                          style: TextStyle(
                            fontSize: 28,
                            fontStyle: FontStyle.italic,
                            color: Colors.white,
                          ),
                        ),
                        TextSpan(
                          text: 'Apartment ',
                          style: TextStyle(
                            fontSize: 28,
                            color: Colors.cyan,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextSpan(
                          text: 'one click',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Now you can find your dream apartment quickly, easily, and affordably - all in one place',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      // Navigate to the User Page
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const User()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyan,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Get Started',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
