import 'package:flutter/material.dart';
import 'package:panorama/panorama.dart'; // ✅ use panorama plugin

class EditTour extends StatefulWidget {
  const EditTour({super.key});

  @override
  State<EditTour> createState() => _EditTourState();
}

class _EditTourState extends State<EditTour> {
  // Currently displayed panorama
  String _selectedImage = "assets/images/roompano.png";

  // Hotspots grouped by panorama
  final Map<String, List<Map<String, dynamic>>> _hotspotsByImage = {};

  // Available panorama images
  final List<String> _availableImages = [
    "assets/images/roompano.png",
    "assets/images/roompano2.png",
    "assets/images/roompano3.png",
  ];

  // Track selected hotspot for slider adjustment
  int? _selectedHotspotIdx;

  @override
  Widget build(BuildContext context) {
    final currentHotspots = _hotspotsByImage[_selectedImage] ?? [];
    final hasSelection =
        _selectedHotspotIdx != null &&
        _selectedHotspotIdx! >= 0 &&
        _selectedHotspotIdx! < currentHotspots.length;
    final selectedSpot = hasSelection
        ? currentHotspots[_selectedHotspotIdx!]
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFF003B5C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF04354B),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "LABELED HOTSPOT",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: 0.8,
          ),
        ),
      ),
      body: Column(
        children: [
          // PANORAMA VIEWER
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Panorama(
                    sensorControl: SensorControl.Orientation,
                    animSpeed: 0.5,
                    child: Image.asset(_selectedImage),
                    hotspots: [
                      for (int i = 0; i < currentHotspots.length; i++)
                        Hotspot(
                          latitude: (currentHotspots[i]["lat"] as num)
                              .toDouble(),
                          longitude: (currentHotspots[i]["lon"] as num)
                              .toDouble(),
                          width: 60,
                          height: 60,
                          widget: GestureDetector(
                            onTap: () {
                              setState(() => _selectedHotspotIdx = i);
                            },
                            onDoubleTap: () {
                              final target =
                                  currentHotspots[i]["target"] as String?;
                              if (target != null &&
                                  _availableImages.contains(target)) {
                                setState(() {
                                  _selectedImage = target;
                                  _selectedHotspotIdx = null;
                                });
                              }
                            },
                            child: Icon(
                              Icons.place,
                              color: _selectedHotspotIdx == i
                                  ? Colors.amber
                                  : Colors.redAccent,
                              size: 40,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Add Hotspot button
                Positioned(
                  bottom: 20,
                  right: 20,
                  child: FloatingActionButton(
                    backgroundColor: Colors.blue,
                    onPressed: _addHotspot,
                    child: const Icon(Icons.add, size: 30, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),

          // --- Slider controls for selected hotspot ---
          if (hasSelection)
            Container(
              color: const Color(0xFF6B8591),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.tune, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        'Adjust "${(selectedSpot!["label"] as String).isNotEmpty ? selectedSpot["label"] : "Hotspot ${_selectedHotspotIdx! + 1}"}"',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => _editHotspot(selectedSpot),
                        icon: const Icon(Icons.edit, color: Colors.white),
                        label: const Text(
                          "Edit",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const SizedBox(
                        width: 90,
                        child: Text(
                          "Longitude",
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: (selectedSpot["lon"] as num).toDouble(),
                          min: -180,
                          max: 180,
                          divisions: 360,
                          label:
                              "${(selectedSpot["lon"] as num).toStringAsFixed(0)}°",
                          onChanged: (v) =>
                              setState(() => selectedSpot["lon"] = v),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const SizedBox(
                        width: 90,
                        child: Text(
                          "Latitude",
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: (selectedSpot["lat"] as num).toDouble(),
                          min: -90,
                          max: 90,
                          divisions: 180,
                          label:
                              "${(selectedSpot["lat"] as num).toStringAsFixed(0)}°",
                          onChanged: (v) =>
                              setState(() => selectedSpot["lat"] = v),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // --- Thumbnails ---
          Container(
            color: const Color(0xFF6B8591),
            padding: const EdgeInsets.all(10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _availableImages.map(_thumbnail).toList(),
            ),
          ),

          // --- Save button ---
          Container(
            width: double.infinity,
            color: const Color(0xFF6B8591),
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF003B5C),
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: () {
                debugPrint("Hotspots by image: $_hotspotsByImage");
              },
              child: const Text(
                "SAVE",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Add hotspot ----
  void _addHotspot() {
    setState(() {
      _hotspotsByImage.putIfAbsent(_selectedImage, () => []);
      _hotspotsByImage[_selectedImage]!.add({
        "lat": 0.0,
        "lon": 0.0,
        "label": "",
        "target": null,
      });
      _selectedHotspotIdx = _hotspotsByImage[_selectedImage]!.length - 1;
    });
  }

  // ---- Edit hotspot ----
  void _editHotspot(Map<String, dynamic> spot) {
    final controller = TextEditingController(text: spot["label"]);
    String? selectedTarget = spot["target"];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Edit Hotspot"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: "Enter label"),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              value: selectedTarget,
              decoration: const InputDecoration(
                labelText: "Navigate to",
                border: OutlineInputBorder(),
              ),
              items: _availableImages
                  .map(
                    (img) => DropdownMenuItem(
                      value: img,
                      child: Text(img.split("/").last),
                    ),
                  )
                  .toList(),
              onChanged: (v) => selectedTarget = v,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _hotspotsByImage[_selectedImage]?.remove(spot);
                _selectedHotspotIdx = null;
              });
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Delete"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                spot["label"] = controller.text;
                spot["target"] = selectedTarget;
              });
              Navigator.pop(context);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  // ---- Thumbnails ----
  Widget _thumbnail(String imagePath) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedImage = imagePath;
          _selectedHotspotIdx = null;
        });
      },
      child: Container(
        width: 120,
        height: 120,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: _selectedImage == imagePath ? Colors.amber : Colors.white,
            width: 3,
          ),
          image: DecorationImage(
            image: AssetImage(imagePath),
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}
