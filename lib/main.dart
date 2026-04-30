import 'package:flutter/material.dart';
import 'package:ar_flutter_plugin/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin/models/ar_anchor.dart';
import 'package:ar_flutter_plugin/models/ar_node.dart';
import 'package:ar_flutter_plugin/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin/datatypes/node_types.dart';
// Hide Colors from vector_math to avoid conflict with Flutter's Colors
import 'package:vector_math/vector_math_64.dart' hide Colors;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: ARScreen());
  }
}

class ARScreen extends StatefulWidget {
  const ARScreen({super.key});

  @override
  State<ARScreen> createState() => _ARScreenState();
}

class _ARScreenState extends State<ARScreen> {
  ARSessionManager? arSessionManager;
  ARObjectManager? arObjectManager;
  ARAnchorManager? arAnchorManager;

  List<Vector3> points = [];
  List<ARNode> nodes = [];
  List<ARAnchor> anchors = [];

  double length = 0;
  double width = 0;
  double height = 0;
  double volume = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("AR Volume Measure"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: resetPoints,
          )
        ],
      ),
      body: Stack(
        children: [
          ARView(
            onARViewCreated: onARViewCreated,
            planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
          ),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Card(
              color: Colors.black.withOpacity(0.7),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStat("Length", length, "m"),
                        _buildStat("Width", width, "m"),
                        _buildStat("Height", height, "m"),
                      ],
                    ),
                    const Divider(color: Colors.white24),
                    Text(
                      "Volume: ${volume.toStringAsFixed(3)} m³",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getInstructionText(),
                      style: const TextStyle(color: Colors.cyanAccent),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, double value, String unit) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        Text(
          "${value.toStringAsFixed(2)} $unit",
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  String _getInstructionText() {
    if (points.isEmpty) return "Tap to set starting point (Point 1)";
    if (points.length == 1) return "Tap for Length (Point 2)";
    if (points.length == 2) return "Tap for Width (Point 3)";
    if (points.length == 3) return "Tap for Height (Point 4)";
    return "All points set! Tap refresh to start over.";
  }

  void resetPoints() {
    setState(() {
      points.clear();
      length = 0;
      width = 0;
      height = 0;
      volume = 0;
    });

    // Remove all nodes manually
    for (var node in nodes) {
      arObjectManager?.removeNode(node);
    }
    nodes.clear();

    // Remove all anchors manually
    for (var anchor in anchors) {
      arAnchorManager?.removeAnchor(anchor);
    }
    anchors.clear();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Points reset")),
    );
  }

  // Plugin v0.7.3 requires 4 parameters (includes ARLocationManager)
  void onARViewCreated(
    ARSessionManager sessionManager,
    ARObjectManager objectManager,
    ARAnchorManager anchorManager,
    ARLocationManager locationManager,
  ) {
    debugPrint("AR View Created");
    arSessionManager = sessionManager;
    arObjectManager = objectManager;
    arAnchorManager = anchorManager;

    arSessionManager!.onInitialize(
      showFeaturePoints: true,
      showPlanes: true,
      handleTaps: true,
    );
    arObjectManager!.onInitialize();
    arSessionManager!.onPlaneOrPointTap = onTap;
    debugPrint("AR Managers Initialized");
  }

  Future<void> onTap(List<ARHitTestResult> hits) async {
    debugPrint("Tap detected. Hits count: ${hits.length}");
    if (hits.isEmpty) {
      debugPrint("No hits detected on planes/points.");
      return;
    }

    if (points.length >= 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Max points reached. Reset to start over.")),
      );
      return;
    }

    try {
      final hit = hits.first;
      final position = hit.worldTransform.getTranslation();
      debugPrint("Placing point at: $position");

      var anchor = ARPlaneAnchor(transformation: hit.worldTransform);
      bool? added = await arAnchorManager?.addAnchor(anchor);

      if (added == true) {
        anchors.add(anchor);

        var node = ARNode(
          type: NodeType.webGLB,
          uri: "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/master/2.0/Duck/glTF-Binary/Duck.glb",
          scale: Vector3(0.005, 0.005, 0.005), // Scale down the duck so it looks like a dot
          position: Vector3(0, 0, 0),
        );

        bool? nodeAdded = await arObjectManager?.addNode(node, planeAnchor: anchor);
        
        if (nodeAdded == true) {
          nodes.add(node);
          setState(() {
            points.add(position);
            
            if (points.length == 2) {
              length = calcDistance(points[0], points[1]);
            } else if (points.length == 3) {
              width = calcDistance(points[1], points[2]);
            } else if (points.length == 4) {
              height = calcDistance(points[2], points[3]);
              volume = length * width * height;
            }
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Point ${points.length} marked!"),
              duration: const Duration(seconds: 1),
            ),
          );
        } else {
          debugPrint("Failed to add AR Node");
        }
      } else {
        debugPrint("Failed to add AR Anchor");
      }
    } catch (e) {
      debugPrint("Error in onTap: $e");
    }
  }

  double calcDistance(Vector3 a, Vector3 b) {
    return (a - b).length;
  }
}
