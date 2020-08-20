import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geojson/geojson.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geopoint/geopoint.dart';
import 'package:paris_masque/geofencing.dart';

void main() {
  runApp(App());
}

class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Paris Masque',
      theme: ThemeData(
        fontFamily: 'Montserrat',
        // Describes the contrast of a theme or color palette.
        // Dark will require a light text color to achieve readable contrast.
        brightness: Brightness.dark,
        primaryColor: Color(0x0055A4).withOpacity(1),
        accentColor: Color(0xef4135).withOpacity(1),
        // This makes the visual density adapt to the platform that you run
        // the app on. For desktop platforms, the controls will be smaller and
        // closer together (more dense) than on mobile platforms.
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

enum _HomePageStatus { initial, loading, success }

class _HomePageState extends State<HomePage> {
  List<GeoJsonFeature> _matchedMaskLocations = [];
  _HomePageStatus _status = _HomePageStatus.initial;

  // https://stackoverflow.com/a/61595553/7573460
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkShouldWearMask());
  }

  static Future<String> _loadGeoJSON() async {
    return await rootBundle.loadString(
        'assets/data/coronavirus-port-du-masque-obligatoire-lieux-places-et-marches.geojson');
  }

  Future<GeoPoint> _getCurrentPosition() async {
    final position = await Geolocator()
        .getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
    debugPrint("user accepted to share positon: $position");
    return GeoPoint(latitude: position.latitude, longitude: position.longitude);
  }

  Future<void> _checkShouldWearMask() async {
    setState(() {
      _matchedMaskLocations = [];
      _status = _HomePageStatus.loading;
    });

    final position = await _getCurrentPosition();
    final geofencing = await Geofencing.fromString(await _loadGeoJSON());
    final matchedMaskLocations = await geofencing.contains(position);

    debugPrint("should user wear mask ? $matchedMaskLocations");

    setState(() {
      _matchedMaskLocations = matchedMaskLocations;
      _status = _HomePageStatus.success;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).primaryColor,
              Theme.of(context).primaryColor.withOpacity(.6),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0.0, 0.9],
          ),
        ),
        child: Center(
          child: RefreshIndicator(
            onRefresh: _checkShouldWearMask,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ListView(),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    if (this._status == _HomePageStatus.loading)
                      Text(
                        "Vérification en cours... ⌛",
                        style: TextStyle(fontSize: 20),
                      ),
                    if (this._status == _HomePageStatus.success)
                      ShouldWearMask(this._matchedMaskLocations),
                    SizedBox(height: 16),
                    if (this._status == _HomePageStatus.success)
                      Text("Glisser l'écran vers le bas pour actualiser")
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ShouldWearMask extends StatelessWidget {
  final List<GeoJsonFeature> _matchedMaskLocations;

  ShouldWearMask(this._matchedMaskLocations);

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 50);
    final shouldWearMask = _matchedMaskLocations.isNotEmpty;
    final maskZoneName = shouldWearMask
        ? _matchedMaskLocations.first.properties["nom_long"]
        : "";

    return Column(children: [
      Text(shouldWearMask ? "Oui 😷" : "Non 🎉", style: style),
      SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.only(right: 8, left: 8),
        child: Text(
          shouldWearMask
              ? "Le masque est obligatoire dans le secteur\n« $maskZoneName »"
              : "Profitez bien, mais faîtes quand même attention 🙏",
          style: TextStyle(fontSize: 18),
          softWrap: true,
          textAlign: TextAlign.center,
        ),
      )
    ]);
  }
}
