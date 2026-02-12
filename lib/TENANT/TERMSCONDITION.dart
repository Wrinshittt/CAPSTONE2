import 'package:flutter/material.dart';

class TermsAndCondition extends StatefulWidget {
  const TermsAndCondition({super.key});

  @override
  State<TermsAndCondition> createState() => _TermsAndConditionState();
}

class _TermsAndConditionState extends State<TermsAndCondition> {
  bool _isAgreed = false; // state for checkbox

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF003B5C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF003B5C),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        centerTitle: true,
        title: const Text(
          "TERMS & CONDITION",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 25,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Terms and Conditions – Smart Finder",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "Welcome to Smart Finder! By using our mobile application, you agree to the following terms and conditions. Please read them carefully before continuing.",
                style: TextStyle(fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 15),
              const Text(
                "1. Overview\n"
                "Smart Finder is a mobile application designed to help users find available apartments for rent. The app allows users to view images of the property through a Photo Tour feature and use Google Maps to locate and navigate to the apartment's physical address.",
                style: TextStyle(fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 15),
              const Text(
                "2. Use of the App\n"
                "• You must be at least 18 years old to use this app.\n"
                "• The content provided, including apartment listings, images, and map locations, is for informational purposes only.\n"
                "• Users agree not to misuse the app or use it for unlawful purposes.",
                style: TextStyle(fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 15),
              const Text(
                "3. Photo Tour Content\n"
                "• All images shown in the Photo Tour are submitted by landlords or verified property owners.\n"
                "• Smart Finder is not responsible for any discrepancies between the posted images and the actual apartment.",
                style: TextStyle(fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 15),
              const Text(
                "4. Google Maps Integration\n"
                "Our app uses Google Maps to help users locate apartments. By using this feature, you agree to comply with Google Maps’ Terms of Service.",
                style: TextStyle(fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 15),
              const Text(
                "5. Liability Disclaimer\n"
                "Smart Finder does not own or manage any listed property and is not liable for any transaction or agreement made between tenants and landlords. We encourage users to exercise caution and verify property details before entering into any rental agreement.",
                style: TextStyle(fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 15),
              const Text(
                "6. Privacy\n"
                "By using Smart Finder, you also agree to our [Privacy Policy], which explains how we collect and use your data.",
                style: TextStyle(fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 15),
              const Text(
                "7. Changes to Terms\n"
                "We may update these Terms and Conditions at any time. Continued use of the app after updates means you accept the revised terms.",
                style: TextStyle(fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 25),

              // ✅ Checkbox + Text
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Checkbox(
                    value: _isAgreed,
                    activeColor: Colors.blue,
                    onChanged: (value) {
                      setState(() {
                        _isAgreed = value ?? false;
                      });
                    },
                  ),
                  const Flexible(
                    child: Text(
                      "I Agree with the terms & conditions",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
