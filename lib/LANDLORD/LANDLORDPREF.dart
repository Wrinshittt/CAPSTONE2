import 'package:flutter/material.dart';
import 'package:smart_finder/LANDLORD/LOGIN.dart';

class LandlordPref extends StatefulWidget {
  const LandlordPref({super.key});

  @override
  State<LandlordPref> createState() => _LandlordPrefState();
}

class _LandlordPrefState extends State<LandlordPref> {
  final Color bgColor = const Color(0xFF00324E);
  final Color cardColor = Colors.grey.shade200;

  Map<String, String> preferences = {
    "Pet-Friendly": "Yes",
    "Open to all": "Yes",
    "Common CR": "Yes",
    "Occupation": "Student Only",
    "Smoking": "Non-Smoker Only",
    "Location": "Near UM",
    "WiFi": "Yes",
  };

  final Map<String, IconData> icons = {
    "Pet-Friendly": Icons.pets,
    "Open to all": Icons.people,
    "Common CR": Icons.bathroom,
    "Occupation": Icons.work,
    "Smoking": Icons.smoking_rooms,
    "Location": Icons.location_on,
    "WiFi": Icons.wifi,
  };

  final Map<String, List<String>> dropdownOptions = {
    "Pet-Friendly": ["Yes", "No"],
    "Open to all": ["Yes", "No"],
    "Common CR": ["Yes", "No"],
    "Occupation": ["Student Only", "Professional Only", "Others"],
    "Smoking": ["Non-Smoker Only", "Smoker Allowed"],
    "Location": ["Near UM", "Near SM Eco", "Near Mapua", "Near DDC"],
    "WiFi": ["Yes", "No"],
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  "LANDLORD PREFERENCES",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 60),
              const Text(
                "Hi Anthony Gandeza,\n",
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
              const Text(
                "To help us match you with the most suitable tenants, could you kindly share your preferences. Knowing what kind of tenant you’re looking for helps us filter applications better and ensure a smooth rental experience for both parties.",
                style: TextStyle(fontSize: 14, color: Colors.white),
              ),
              const SizedBox(height: 20),
              const Text(
                "Here are some examples to consider:",
                style: TextStyle(fontSize: 14, color: Colors.white),
              ),
              const SizedBox(height: 20),

              // Generate preference cards
              ...preferences.entries.map((entry) {
                String key = entry.key;
                String value = entry.value;

                return Container(
                  margin: const EdgeInsets.only(bottom: 15),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: bgColor,
                        child: Icon(icons[key], color: Colors.white),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Text(
                          key,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: SizedBox(
                          width: 140, // Fixed dropdown width
                          child: DropdownButton<String>(
                            value: value,
                            isExpanded: true,
                            underline: const SizedBox(),
                            borderRadius: BorderRadius.circular(8),
                            dropdownColor: Colors.white,
                            items: dropdownOptions[key]!
                                .map<DropdownMenuItem<String>>((String option) {
                                  return DropdownMenuItem<String>(
                                    value: option,
                                    child: Text(
                                      option,
                                      style: const TextStyle(fontSize: 14),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                })
                                .toList(),
                            onChanged: (String? newValue) {
                              setState(() {
                                preferences[key] = newValue!;
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 40),

              // ✅ Continue Button
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
                    onPressed: () {
                      // ✅ Navigate to LoginT (or your tenant login screen)
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const Login()),
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
