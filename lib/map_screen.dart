import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Campus Map Test")),
      body: FlutterMap(
        options: MapOptions(
          center: LatLng(26.30680, -98.17392), // utrgv
          zoom: 16,
          onTap: (tapPosition, latLng) {
            print("Tapped at $latLng");
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(26.30677, -98.17393),
                width: 40,
                height: 40,
                child: Icon(Icons.location_pin, color: Colors.red),
              ),
            ],
          ),
        ],
      ),
    );
  }
}