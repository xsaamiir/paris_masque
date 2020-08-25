import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geojson/geojson.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geopoint/geopoint.dart';
import 'package:http/http.dart' as http;
import 'package:latlong/latlong.dart';
import 'package:package_info/package_info.dart';
import 'package:paris_masque/geofencing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:user_location/user_location.dart';

const privacy =
    "L'application ne collecte ni sauvegarde aucune de vos données. Votre position ne quitte jamais votre portable, tous les traitements sont fait sur votre appareil.";
const mapboxAccessToken =
    "pk.eyJ1Ijoic2hhcmt5emUiLCJhIjoiY2tlNDl3ZzhjMDJwczMycWdnMGhwdmRvYyJ9.wkVys6dgiAyPJ9nxFg5syQ";
const geoJSONDataUrl =
    "https://raw.githubusercontent.com/sharkyze/paris_masque/master/assets/data/coronavirus-port-du-masque-obligatoire-lieux-places-et-marches.geojson";

void main() {
  runApp(App());
}

class App extends StatelessWidget {
  Future<Geofencing> _loadGeoJSON() async {
    Directory tempDir = await getTemporaryDirectory();
    String tempPath = tempDir.path;
    File cacheFile = File("$tempPath/data.geojson");

    String data;
    if (await cacheFile.exists()) {
      debugPrint("loading data from cache file");
      data = await _loadGeoJSONLocally(cacheFile);
    } else {
      debugPrint("loading data from network");
      data = await _loadGeoJSONRemotely();
      cacheFile.writeAsString(data);
    }

    return Geofencing.fromString(data);
  }

  static Future<String> _loadGeoJSONRemotely() async {
    final res = await http.get(geoJSONDataUrl);

    if (res.statusCode == 200) {
      // If the server did return a 200 OK response,
      // then parse the JSON.
      return res.body;
    } else {
      // If the server did not return a 200 OK response,
      // then throw an exception.
      throw Exception('Failed to load geojson data from remote source');
    }
  }

  static Future<String> _loadGeoJSONLocally(File file) async {
    return file.readAsString();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Paris Masque',
      theme: ThemeData(
        fontFamily: 'Montserrat',
        // Describes the contrast of a theme or color palette.
        // Dark will require a light text color to achieve readable contrast.
        brightness: Brightness.dark,
        primaryColor: const Color(0x000055a4).withOpacity(1),
        accentColor: const Color(0x00ef4135).withOpacity(1),
        // This makes the visual density adapt to the platform that you run
        // the app on. For desktop platforms, the controls will be smaller and
        // closer together (more dense) than on mobile platforms.
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: FutureBuilder(
        future: _loadGeoJSON(),
        builder: (BuildContext context, AsyncSnapshot<dynamic> snapshot) {
          if (snapshot.hasData) {
            return HomePage(geofencing: snapshot.data);
          } else if (snapshot.hasError) {
            return ErrorPage();
          } else {
            return SplashPage();
          }
        },
      ),
    );
  }
}

class CenteredColumn extends StatelessWidget {
  final List<Widget> children;

  const CenteredColumn({Key key, @required this.children}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: this.children,
      ),
    );
  }
}

class SplashPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Layout(
      body: CenteredColumn(
        children: [
          SizedBox(
            child: Image.asset("assets/images/paris-masque-square.png"),
            height: MediaQuery.of(context).size.height * 0.3,
          ),
          SizedBox(height: 20),
          SizedBox(
            child: CircularProgressIndicator(),
            width: 40,
            height: 40,
          ),
        ],
      ),
    );
  }
}

class ErrorPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Layout(
      body: CenteredColumn(
        children: [
          Text(
            "Oups, une erreur est survenue 😢. Veuillez réessayer ultérieurement...",
            style: TextStyle(fontSize: 20),
            textAlign: TextAlign.center,
          )
        ],
      ),
    );
  }
}

class Layout extends StatelessWidget {
  final Widget body;
  final List<Widget> appBarActions;

  const Layout({Key key, @required this.body, this.appBarActions})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).primaryColor,
      appBar: AppBar(
        elevation: 0.0,
        bottomOpacity: 0.0,
        actions: this.appBarActions,
      ),
      body: this.body,
    );
  }
}

/// urlLauncher returns a function that when executed,
/// opens a given url in the web browser.
Future<void> Function() urlLauncher(String url) {
  Future<void> launcher() async {
    if (await canLaunch(url)) {
      await launch(url, forceSafariVC: false);
    } else {
      throw 'Could not launch $url';
    }
  }

  return launcher;
}

class HomePage extends StatefulWidget {
  final Geofencing geofencing;

  const HomePage({Key key, @required this.geofencing}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

enum _HomePageStatus { initial, loading, success, error_geolocation }

class _HomePageState extends State<HomePage> {
  List<GeoJsonFeature> _matchedMaskLocations = [];
  _HomePageStatus _status = _HomePageStatus.initial;

  // https://stackoverflow.com/a/61595553/7573460
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkShouldWearMask());
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

    var position;

    // In case the user doesn't allow access to the device's location.
    try {
      position = await _getCurrentPosition();
    } catch (e) {
      setState(() {
        _status = _HomePageStatus.error_geolocation;
      });
      return;
    }

    final matchedMaskLocations = await widget.geofencing.contains(position);

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
    return Layout(
      appBarActions: [
        IconButton(
          icon: const Icon(Icons.map),
          tooltip: 'Voir la carte',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MapPage(geofencing: widget.geofencing),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.help),
          tooltip: 'Aide',
          onPressed: () => showAboutDialog(context: context),
        ),
      ],
      body: Container(
        child: RefreshIndicator(
          onRefresh: _checkShouldWearMask,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ListView(),
              CenteredColumn(
                children: <Widget>[
                  if (this._status == _HomePageStatus.loading)
                    Text(
                      "Vérification en cours... ⌛",
                      style: TextStyle(fontSize: 20),
                    ),
                  if (this._status == _HomePageStatus.success)
                    ShouldWearMask(this._matchedMaskLocations),
                  SizedBox(height: 16),
                  if (this._status != _HomePageStatus.loading)
                    Text("Glisser l'écran vers le bas pour actualiser"),
                  if (this._status == _HomePageStatus.error_geolocation)
                    Column(
                      children: [
                        Text(
                          "💥",
                          style: TextStyle(fontSize: 50),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.only(right: 8, left: 8),
                          child: Text(
                            "L'application a besoin de votre position pour fonctionner",
                            style: TextStyle(fontSize: 20),
                            softWrap: true,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.only(right: 8, left: 8),
                          child: RichText(
                            textAlign: TextAlign.center,
                            text: TextSpan(children: [
                              TextSpan(
                                text: "Assurez-vous\n",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextSpan(text: privacy + "\n\n")
                            ]),
                          ),
                        )
                      ],
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

    return Column(
      children: [
        Text(shouldWearMask ? "Oui 😷" : "Non 🎉", style: style),
        SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(right: 8, left: 8),
          child: Text(
            shouldWearMask
                ? "Le masque est obligatoire dans le secteur\n« $maskZoneName »"
                : "Profitez bien, mais faîtes attention quand même 🙏",
            style: TextStyle(fontSize: 18),
            softWrap: true,
            textAlign: TextAlign.center,
          ),
        )
      ],
    );
  }
}

void showAboutDialog({
  @required BuildContext context,
}) {
  assert(context != null);
  showDialog<void>(
    context: context,
    builder: (context) => _HelpDialog(),
  );
}

class _HelpDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bodyTextStyle =
        textTheme.bodyText1.apply(color: colorScheme.onPrimary);

    final name = 'Paris Masque';
    final description =
        "Paris Masque vous permet de savoir à tout moment si vous êtes dans une zone de Paris ou le port du masque est obligatoire.\n\n";
    final legalese = 'Par samir elsharkawy';
    final repoUrl = "https://github.com/sharkyze/paris_masque";
    final repoText = "dépôt GitHub";
    final seeSource =
        "L'application est open source, c'est à dire vous pouvez consulter le code source sur le dépôt GitHub.\n\n";
    final createTicket =
        "Si vous avez la moindre question, problème ou vous voulez voir une nouvelle fonctionnalité, n'hésitez pas créer un ticket ici.";
    final ticketText = "n'hésitez pas créer un ticket ici";
    final ticketUrl = "https://github.com/sharkyze/paris_masque/issues/new";

    final repoLinkIndex = seeSource.indexOf(repoText);
    final repoLinkIndexEnd = repoLinkIndex + repoText.length;
    final seeSourceFirst = seeSource.substring(0, repoLinkIndex);
    final seeSourceSecond = seeSource.substring(repoLinkIndexEnd);

    final ticketLinkIndex = createTicket.indexOf(ticketText);
    final ticketLinkIndexEnd = ticketLinkIndex + ticketText.length;
    final createTicketFirst = createTicket.substring(0, ticketLinkIndex);
    final createTicketSecond = createTicket.substring(ticketLinkIndexEnd);

    return AlertDialog(
      backgroundColor: colorScheme.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      content: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: textTheme.headline5.apply(color: colorScheme.onPrimary),
            ),
            SizedBox(height: 5),
            FutureBuilder(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) => Text(
                snapshot.hasData ? 'version: ${snapshot.data.version}' : "",
              ),
            ),
            SizedBox(height: 24),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(style: bodyTextStyle, text: description),
                  TextSpan(style: bodyTextStyle, text: privacy + "\n\n"),
                  TextSpan(style: bodyTextStyle, text: seeSourceFirst),
                  TextSpan(
                    style: bodyTextStyle.copyWith(color: colorScheme.primary),
                    text: repoText,
                    recognizer: TapGestureRecognizer()
                      ..onTap = urlLauncher(repoUrl),
                  ),
                  TextSpan(style: bodyTextStyle, text: seeSourceSecond),
                  TextSpan(style: bodyTextStyle, text: createTicketFirst),
                  TextSpan(
                    style: bodyTextStyle.copyWith(color: colorScheme.primary),
                    text: ticketText,
                    recognizer: TapGestureRecognizer()
                      ..onTap = urlLauncher(ticketUrl),
                  ),
                  TextSpan(style: bodyTextStyle, text: createTicketSecond),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        FlatButton(
          textColor: colorScheme.primary,
          child: Text("Voir les licences"),
          onPressed: () {
            Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (context) => Theme(
                data: Theme.of(context).copyWith(
                  textTheme: Typography.material2018(
                    platform: Theme.of(context).platform,
                  ).black,
                  scaffoldBackgroundColor: Colors.white,
                ),
                child: LicensePage(
                  applicationName: name,
                  applicationLegalese: legalese,
                  applicationIcon: Image.asset(
                    "assets/images/medical-mask.png",
                    height: 200,
                  ),
                ),
              ),
            ));
          },
        ),
        FlatButton(
          textColor: colorScheme.primary,
          child: Text("Fermer"),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

class MapPage extends StatefulWidget {
  final Geofencing geofencing;

  MapPage({Key key, @required this.geofencing}) : super(key: key);

  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  MapController mapController;
  PolygonLayerOptions polygonLayer = PolygonLayerOptions(polygons: []);
  UserLocationOptions userLocationOptions;
  List<Marker> markers = [];

  Future<void> loadData() async {
    final polys = widget.geofencing.features
        .map((e) => e.geometry as GeoJsonPolygon)
        .expand(
          (e) => e.geoSeries.map(
            (element) => Polygon(
              points: element.toLatLng().toList(),
              color: Theme.of(context).accentColor.withOpacity(0.5),
            ),
          ),
        )
        .toList();

    setState(() {
      polygonLayer = PolygonLayerOptions(polygons: polys);
    });
  }

  @override
  void initState() {
    super.initState();
    mapController = MapController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    loadData();
  }

  @override
  Widget build(BuildContext context) {
    final mapboxLayer = TileLayerOptions(
      urlTemplate: "https://api.mapbox.com/styles/v1/"
          "{id}/tiles/{z}/{x}/{y}@2x?access_token={accessToken}",
      additionalOptions: {
        'accessToken': mapboxAccessToken,
        'id': 'mapbox/streets-v11',
      },
    );

    userLocationOptions = UserLocationOptions(
      context: context,
      mapController: mapController,
      markers: markers,
      updateMapLocationOnPositionChange: true,
      showMoveToCurrentLocationFloatingActionButton: true,
      zoomToCurrentLocationOnLoad: true,
    );

    return Layout(
      body: SafeArea(
        child: FlutterMap(
          mapController: mapController,
          options: MapOptions(
            center: LatLng(48.8566, 2.333),
            zoom: 11.6,
            minZoom: 10.5,
            maxZoom: 16,
            plugins: [UserLocationPlugin()],
          ),
          layers: [
            mapboxLayer,
            polygonLayer,
            MarkerLayerOptions(markers: markers),
            userLocationOptions,
          ],
        ),
      ),
    );
  }
}
