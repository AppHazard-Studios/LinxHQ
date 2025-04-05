import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to landscape mode
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]).then((_) {
    // Ensure the app uses the entire screen without system UI overlays
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );
    runApp(const LinxHQApp());
  });
}

class LinxHQApp extends StatefulWidget {
  const LinxHQApp({super.key});

  @override
  State<LinxHQApp> createState() => _LinxHQAppState();
}

class _LinxHQAppState extends State<LinxHQApp> {
  @override
  void initState() {
    super.initState();
    // Reinforce orientation lock when the app starts
    _setOrientationLock();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reapply orientation lock when dependencies change
    _setOrientationLock();
  }

  void _setOrientationLock() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Ensure fullscreen mode
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LinxHQ',
      theme: ThemeData.dark(useMaterial3: true),
      debugShowCheckedModeBanner: false,
      home: const HomePage(),
      builder: (context, child) {
        // This ensures the app fills available space and handles system scaling
        return MediaQuery(
          // Prevent system text scaling from affecting our layout calculations
          data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
          child: child!,
        );
      },
    );
  }
}

class Tile {
  final String id;
  String title;
  String url;
  String? iconPath;
  Color? dominantEdgeColor;

  Tile({
    required this.id,
    required this.title,
    required this.url,
    this.iconPath,
    this.dominantEdgeColor,
  });

  factory Tile.fromJson(Map<String, dynamic> json) => Tile(
        id: json['id'],
        title: json['title'],
        url: json['url'],
        iconPath: json['iconPath'],
        dominantEdgeColor: json['dominantEdgeColor'] != null
            ? Color(json['dominantEdgeColor'])
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'iconPath': iconPath,
        'dominantEdgeColor': dominantEdgeColor?.value,
      };
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  // Constants - more adaptive to screen sizes
  static const int tilesPerRow = 5; // Default tiles per row
// Use aspect ratio instead of fixed height
// Minimum size for tiles to be usable

  // State variables
  List<Tile> _tiles = [];
  bool _isLoading = true;
  bool _isEditMode = false;
  bool _useDoubleColumn =
      true; // Default to double column, will be adjusted based on screen dimensions

  // Controllers
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadTiles();

    // Reinforce orientation lock
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Ensure fullscreen mode
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // Data persistence methods
  Future<void> _loadTiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tilesJson = prefs.getStringList('tiles') ?? [];

      setState(() {
        _tiles = tilesJson.map((t) => Tile.fromJson(jsonDecode(t))).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveTiles() async {
    final prefs = await SharedPreferences.getInstance();
    final tilesJson = _tiles.map((t) => jsonEncode(t.toJson())).toList();
    await prefs.setStringList('tiles', tilesJson);
  }

  // Tile management
  Future<void> _addTile(Tile tile) async {
    setState(() => _tiles.add(tile));
    await _saveTiles();

    // Calculate items per page based on current layout
    final int tilesPerPage = _useDoubleColumn ? tilesPerRow * 2 : tilesPerRow;

    // Show the page with the new tile
    if (_tiles.length > tilesPerPage) {
      final pageIndex = (_tiles.length - 1) ~/ tilesPerPage;
      _pageController.animateToPage(
        pageIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _updateTile(Tile tile) async {
    setState(() {
      final index = _tiles.indexWhere((t) => t.id == tile.id);
      if (index >= 0) {
        _tiles[index] = tile;
      }
    });
    await _saveTiles();
  }

  Future<void> _deleteTile(String id) async {
    setState(() => _tiles.removeWhere((t) => t.id == id));
    await _saveTiles();
  }

  void _toggleEditMode() {
    setState(() {
      _isEditMode = !_isEditMode;
    });
  }

  Future<void> _launchUrl(String url) async {
    if (_isEditMode) return;

    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not launch: $url')),
      );
    }
  }

  void _showDeleteConfirmation(Tile tile) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${tile.title}"?'),
        content: const Text('This app will be deleted from your home screen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _deleteTile(tile.id);
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _editTile(Tile tile) {
    showDialog(
      context: context,
      builder: (context) => TileFormDialog(
        tile: tile,
        onSave: _updateTile,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Reinforce orientation lock on each build
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        centerTitle: true,
        toolbarHeight: 90, // Reduced from 90
        title: const Text(
          'LinxHQ',
          textScaleFactor: 1.0,
          style: TextStyle(
            fontSize: 65, // Reduced from 50
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  alignment: Alignment.center,
                  foregroundColor: _isEditMode
                      ? const Color(0xFFFFFFFF)
                      : Colors.white.withOpacity(0.5),
                ),
                onPressed: _toggleEditMode,
                child: Text(
                  _isEditMode ? 'Done' : 'Edit',
                  style: const TextStyle(
                    fontSize: 26, // Reduced from 24
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
        leadingWidth: 100,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            width: 50,
            child: Center(
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.add,
                    size: 50, color: Color(0xFFFFFFFF)), // Reduced from 50
                onPressed: () async {
                  if (_isEditMode) {
                    setState(() {
                      _isEditMode = false;
                    });
                  }

                  final result = await showDialog<Tile>(
                    context: context,
                    builder: (context) => const TileFormDialog(),
                  );
                  if (result != null) await _addTile(result);
                },
              ),
            ),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: _isEditMode ? () => _toggleEditMode() : null,
        behavior: HitTestBehavior.translucent,
        child: LayoutBuilder(builder: (context, constraints) {
          // Safe area calculations
          final safeHeight = constraints.maxHeight;
          final safeWidth = constraints.maxWidth;

          // Use simpler logic to determine layout
          // Force double column on landscape tablets, single column on very narrow screens
          final useDoubleColumn = safeWidth > 600 && safeHeight > 400;

          // Update state if column layout changed
          if (_useDoubleColumn != useDoubleColumn) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              setState(() {
                _useDoubleColumn = useDoubleColumn;
              });
            });
          }

          // Screen padding - smaller for small screens
          final screenPadding = safeWidth > 600 ? 16.0 : 8.0;
          final tileSpacing = safeWidth > 600 ? 16.0 : 8.0;

          // Calculate available space after accounting for app bar and paddings
          final availableWidth = safeWidth - (screenPadding * 2);

          // Calculate the height of each row with margins
          int rowCount = useDoubleColumn ? 2 : 1;
          final titleHeight = 36.0; // Fixed title height

          // Calculate tile dimensions
          int itemsPerRow;
          double tileSize;

          if (useDoubleColumn) {
            // For double column (tablet), use fixed 5 items per row
            itemsPerRow = 5;

            // When calculating available height, use larger title height
            double titleHeight = 50.0; // Increased from 36.0

            // Maximum available height for content
            double maxRowHeight =
                (safeHeight - (screenPadding * 2) - tileSpacing) / rowCount;

            // Height available for the actual tile (minus title)
            double availableTileHeight = maxRowHeight - titleHeight;

            // Width per tile
            double availableTileWidth =
                (availableWidth - (tileSpacing * (itemsPerRow - 1))) /
                    itemsPerRow;

            // Use smaller dimension to ensure square tiles
            tileSize = min(availableTileWidth, availableTileHeight);
          } else {
            // For single column (phone), adapt items per row based on width
            if (availableWidth >= 500) {
              itemsPerRow = 5;
            } else if (availableWidth >= 400) {
              itemsPerRow = 4;
            } else if (availableWidth >= 300) {
              itemsPerRow = 3;
            } else {
              itemsPerRow = 2;
            }

            // For single column, we have more height to work with
            double availableTileWidth =
                (availableWidth - (tileSpacing * (itemsPerRow - 1))) /
                    itemsPerRow;

            // Height available after accounting for title and padding
            double availableHeight =
                safeHeight - (screenPadding * 2) - titleHeight;

            // Use the smaller dimension to keep tiles square
            tileSize = min(availableTileWidth, availableHeight);
          }

          // Ensure minimum size
          tileSize = max(tileSize, 60.0);

          // Calculate tiles per page
          final tilesPerPage = itemsPerRow * rowCount;

          // Calculate pages
          final pages = <List<Tile>>[];
          for (int i = 0; i < _tiles.length; i += tilesPerPage) {
            final end = i + tilesPerPage < _tiles.length
                ? i + tilesPerPage
                : _tiles.length;
            pages.add(_tiles.sublist(i, end));
          }
          if (pages.isEmpty) pages.add([]);

          return Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  physics: null,
                  itemCount: pages.length,
                  itemBuilder: (ctx, pageIndex) {
                    return Padding(
                      padding: EdgeInsets.all(screenPadding),
                      child: useDoubleColumn
                          ? _buildDoubleColumnLayout(
                              pages[pageIndex],
                              pageIndex * tilesPerPage,
                              itemsPerRow,
                              tileSize,
                              tileSpacing,
                            )
                          : _buildSingleColumnLayout(
                              pages[pageIndex],
                              pageIndex * tilesPerPage,
                              itemsPerRow,
                              tileSize,
                              tileSpacing,
                            ),
                    );
                  },
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  // Build a double column layout (2 rows)
  // Build a double column layout (2 rows)
  Widget _buildDoubleColumnLayout(
    List<Tile> pageTiles,
    int startIndex,
    int itemsPerRow,
    double tileSize,
    double tileSpacing,
  ) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // First row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: _buildTileRow(
            pageTiles,
            startIndex,
            0,
            itemsPerRow,
            tileSize,
            tileSpacing,
          ),
        ),

        // Second row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: _buildTileRow(
            pageTiles,
            startIndex,
            itemsPerRow,
            itemsPerRow,
            tileSize,
            tileSpacing,
          ),
        ),
      ],
    );
  }

  // Build a single column layout (1 row)
  // Build a single column layout (1 row)
  Widget _buildSingleColumnLayout(
    List<Tile> pageTiles,
    int startIndex,
    int itemsPerRow,
    double tileSize,
    double tileSpacing,
  ) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Single row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: _buildTileRow(
            pageTiles,
            startIndex,
            0,
            itemsPerRow,
            tileSize,
            tileSpacing,
          ),
        ),
      ],
    );
  }

  // Build a row of tiles with consistent spacing
  List<Widget> _buildTileRow(
    List<Tile> pageTiles,
    int startIndex,
    int rowOffset,
    int itemsPerRow,
    double tileSize,
    double tileSpacing,
  ) {
    List<Widget> rowTiles = [];

    for (int index = 0; index < itemsPerRow; index++) {
      final tileIndex = startIndex + index + rowOffset;

      // Add the tile or an empty space
      if (tileIndex < _tiles.length) {
        rowTiles.add(
          AppTile(
            key: ValueKey(_tiles[tileIndex].id),
            tile: _tiles[tileIndex],
            isEditMode: _isEditMode,
            size: tileSize, // Now guaranteed to be square
            onTap: () => _launchUrl(_tiles[tileIndex].url),
            onDelete: () => _showDeleteConfirmation(_tiles[tileIndex]),
            onEdit: () => _editTile(_tiles[tileIndex]),
            onLongPress: _toggleEditMode,
            onUpdateTileColor: (color) {
              setState(() {
                final tile = _tiles[tileIndex];
                _tiles[tileIndex] = Tile(
                  id: tile.id,
                  title: tile.title,
                  url: tile.url,
                  iconPath: tile.iconPath,
                  dominantEdgeColor: color,
                );
              });
              _saveTiles();
            },
          ),
        );

        // Add spacing between tiles (but not after the last one)
        if (index < itemsPerRow - 1) {
          rowTiles.add(SizedBox(width: tileSpacing));
        }
      } else {
        // Add an empty space for missing tiles
        rowTiles.add(SizedBox(width: tileSize));

        // Add spacing between empty spaces (but not after the last one)
        if (index < itemsPerRow - 1) {
          rowTiles.add(SizedBox(width: tileSpacing));
        }
      }
    }

    return rowTiles;
  }
}

// The AppTile class and TileFormDialog remain the same as in your original code
class AppTile extends StatefulWidget {
  final Tile tile;
  final bool isEditMode;
  final double size;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onLongPress;
  final Function(Color) onUpdateTileColor;

  const AppTile({
    super.key,
    required this.tile,
    required this.isEditMode,
    required this.size,
    required this.onTap,
    required this.onDelete,
    required this.onEdit,
    required this.onLongPress,
    required this.onUpdateTileColor,
  });

  @override
  State<AppTile> createState() => _AppTileState();
}

class _AppTileState extends State<AppTile> {
  Color? _dominantEdgeColor;
  bool _isAnalyzing = false;

  @override
  void initState() {
    super.initState();
    _dominantEdgeColor = widget.tile.dominantEdgeColor;

    if (widget.tile.iconPath != null && _dominantEdgeColor == null) {
      _analyzeImage();
    }
  }

  @override
  void didUpdateWidget(AppTile oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.tile.iconPath != oldWidget.tile.iconPath) {
      _dominantEdgeColor = widget.tile.dominantEdgeColor;
      if (widget.tile.iconPath != null && _dominantEdgeColor == null) {
        _analyzeImage();
      }
    }
  }

  // Analyze the image to find the dominant edge color
  Future<void> _analyzeImage() async {
    if (widget.tile.iconPath == null || widget.tile.iconPath!.isEmpty) return;
    if (_isAnalyzing) return; // Prevent multiple concurrent analyses

    final file = File(widget.tile.iconPath!);
    if (!file.existsSync()) return;

    _isAnalyzing = true;

    try {
      // Load the image
      final bytes = await file.readAsBytes();
      final image = await decodeImageFromList(bytes);

      // Find the dominant color around the edges
      final color = await _findDominantEdgeColor(image, bytes);

      if (mounted) {
        setState(() {
          _dominantEdgeColor = color;
          _isAnalyzing = false;
        });

        // Notify parent about the new color
        widget.onUpdateTileColor(color);
      }
    } catch (e) {
      // If there's an error, use a default color
      if (mounted) {
        setState(() {
          _dominantEdgeColor = const Color(0xFF333333);
          _isAnalyzing = false;
        });
      }
    }
  }

  // Find the dominant edge color in an image with transparency
  Future<Color> _findDominantEdgeColor(ui.Image image, Uint8List bytes) async {
    // Default fallback color
    Color defaultColor = const Color(0xFF333333);

    try {
      final width = image.width;
      final height = image.height;

      // Get the byte data from the image
      final completer = Completer<ByteData>();
      image.toByteData(format: ui.ImageByteFormat.rawRgba).then((data) {
        if (data != null) {
          completer.complete(data);
        } else {
          completer.complete(ByteData(0)); // Empty ByteData as fallback
        }
      });

      final byteData = await completer.future;
      if (byteData.lengthInBytes == 0) return defaultColor;

      // Collect all non-transparent colors from the entire image
      List<Color> visibleColors = [];
      Map<Color, int> colorCounts = {};

      // Sample more densely, including inner parts of the image
      for (int y = 0; y < height; y += height ~/ 40) {
        for (int x = 0; x < width; x += width ~/ 40) {
          int offset = (x + y * width) * 4;

          // Check if the pixel is within byte data and isn't fully transparent
          if (offset + 3 < byteData.lengthInBytes &&
              byteData.getUint8(offset + 3) > 50) {
            // Create a color from RGB values (using full opacity)
            final color = Color.fromARGB(
              255,
              byteData.getUint8(offset),
              byteData.getUint8(offset + 1),
              byteData.getUint8(offset + 2),
            );

            // Group similar colors by rounding RGB values to reduce color variations
            // This helps find the dominant color family rather than exact shades
            final simplifiedColor = Color.fromARGB(
              255,
              (byteData.getUint8(offset) ~/ 10) * 10,
              (byteData.getUint8(offset + 1) ~/ 10) * 10,
              (byteData.getUint8(offset + 2) ~/ 10) * 10,
            );

            visibleColors.add(color);
            colorCounts[simplifiedColor] =
                (colorCounts[simplifiedColor] ?? 0) + 1;
          }
        }
      }

      // Find the most common color
      if (colorCounts.isNotEmpty) {
        var dominantColor = defaultColor;
        var maxCount = 0;

        colorCounts.forEach((color, count) {
          if (count > maxCount) {
            maxCount = count;
            dominantColor = color;
          }
        });

        // For colors like YouTube red that are very saturated,
        // find an actual instance of this color family from our samples
        if (visibleColors.isNotEmpty &&
            (dominantColor.red > 200 ||
                dominantColor.green > 200 ||
                dominantColor.blue > 200)) {
          // Find closest matching real color from our samples
          for (var color in visibleColors) {
            if ((color.red ~/ 10) * 10 == dominantColor.red &&
                (color.green ~/ 10) * 10 == dominantColor.green &&
                (color.blue ~/ 10) * 10 == dominantColor.blue) {
              return color;
            }
          }
        }

        return dominantColor;
      }

      return defaultColor;
    } catch (e) {
      return defaultColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Adaptive font size based on tile size
    final fontSize = widget.size < 80
        ? 18.0
        : widget.size < 100
            ? 22.0
            : widget.size < 120
                ? 26.0
                : 30.0;

    // Determine title height based on font size
    final titleHeight = fontSize <= 22
        ? 40.0
        : fontSize <= 26
            ? 46.0
            : 50.0;

    // Total height includes adjusted title height
    return SizedBox(
      width: widget.size,
      height: widget.size + titleHeight, // Dynamic total height
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon container - strictly square
          SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              children: [
                GestureDetector(
                  onTap: () {
                    if (widget.isEditMode) {
                      widget.onLongPress();
                    } else {
                      widget.onTap();
                    }
                  },
                  onLongPress: widget.onLongPress,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      color: const Color(0xFF333333),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _buildTileIcon(),
                    ),
                  ),
                ),
                if (widget.isEditMode)
                  Positioned.fill(
                    child: Container(
                      margin: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              GestureDetector(
                                onTap: widget.onEdit,
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.black.withOpacity(0.35),
                                  ),
                                  width: min(40, widget.size / 3),
                                  height: min(40, widget.size / 3),
                                  child: Icon(
                                    Icons.edit,
                                    size: min(24, widget.size / 4),
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: widget.onDelete,
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.black.withOpacity(0.35),
                                  ),
                                  width: min(40, widget.size / 3),
                                  height: min(40, widget.size / 3),
                                  child: Icon(
                                    Icons.close,
                                    size: min(28, widget.size / 4),
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Title container - dynamic height based on font size
          SizedBox(
            height: titleHeight,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Text(
                  widget.tile.title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTileIcon() {
    // Show custom image if available
    if (widget.tile.iconPath != null && widget.tile.iconPath!.isNotEmpty) {
      final file = File(widget.tile.iconPath!);
      if (file.existsSync()) {
        // Use the detected dominant edge color for the background
        return Container(
          color: _dominantEdgeColor ?? const Color(0xFF333333),
          child: Image.file(
            file,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildGenericIcon(),
          ),
        );
      }
    }

    // Show generic icon
    return _buildGenericIcon();
  }

  Widget _buildGenericIcon() {
    return Container(
      color: const Color(0xFF2C2C2E),
      child: Center(
        child: Icon(
          Icons.link_outlined,
          // Adaptive icon size
          size: widget.size < 80
              ? 30
              : widget.size < 120
                  ? 40
                  : 60,
          color: Colors.white70,
        ),
      ),
    );
  }
}

// TileFormDialog class unchanged
class TileFormDialog extends StatefulWidget {
  final Tile? tile;
  final Function(Tile)? onSave;

  const TileFormDialog({
    super.key,
    this.tile,
    this.onSave,
  });

  @override
  State<TileFormDialog> createState() => _TileFormDialogState();
}

class _TileFormDialogState extends State<TileFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _urlController;
  File? _iconFile;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.tile?.title ?? '');
    _urlController = TextEditingController(text: widget.tile?.url ?? '');

    _loadExistingIcon();
  }

  Future<void> _loadExistingIcon() async {
    if (widget.tile?.iconPath != null && widget.tile!.iconPath!.isNotEmpty) {
      final file = File(widget.tile!.iconPath!);
      if (file.existsSync()) {
        setState(() => _iconFile = file);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_isLoading) return;

    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );

      if (image != null) {
        setState(() => _iconFile = File(image.path));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e')),
      );
    }
  }

  Future<String?> _saveImage(File sourceFile) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final destinationPath =
          path.join(directory.path, 'linxhq_icons', fileName);

      final dir = Directory(path.dirname(destinationPath));
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      final savedFile = await sourceFile.copy(destinationPath);
      return savedFile.path;
    } catch (e) {
      return null;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      String? iconPath = widget.tile?.iconPath;

      if (_iconFile != null &&
          (widget.tile?.iconPath == null ||
              _iconFile!.path != widget.tile!.iconPath)) {
        iconPath = await _saveImage(_iconFile!);
      }

      String url = _urlController.text.trim();
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }

      final tile = Tile(
        id: widget.tile?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        title: _titleController.text.trim(),
        url: url,
        iconPath: iconPath,
        dominantEdgeColor: widget.tile?.dominantEdgeColor,
      );

      if (widget.onSave != null) {
        widget.onSave!(tile);
      }

      if (!mounted) return;
      Navigator.pop(context, tile);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving tile: $e')),
      );
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.tile != null;
    final previewSize = 100.0;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: SingleChildScrollView(
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
                  child: Text(
                    isEditing ? 'Edit Tile' : 'Add New Tile',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Stack(
                          children: [
                            Container(
                              width: previewSize,
                              height: previewSize,
                              decoration: BoxDecoration(
                                color: const Color(0xFF333333),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: _iconFile != null
                                    ? Image.file(_iconFile!, fit: BoxFit.cover)
                                    : Container(
                                        color: const Color(0xFF2C2C2E),
                                        child: const Center(
                                          child: Icon(
                                            Icons.link_outlined,
                                            size: 50,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                            Positioned.fill(
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: _isLoading ? null : _pickImage,
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      color: Colors.black.withOpacity(0.3),
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        Icons.edit,
                                        color: Colors.white,
                                        size: 40,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        MediaQuery(
                          data: MediaQuery.of(context)
                              .copyWith(textScaleFactor: 1.0),
                          child: SizedBox(
                            height: 36,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: SizedBox(
                                width: previewSize,
                                child: Text(
                                  _titleController.text.isEmpty
                                      ? 'Title'
                                      : _titleController.text,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: _titleController,
                            decoration: const InputDecoration(
                              labelText: 'Title',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() {}),
                            validator: (value) => (value?.isEmpty ?? true)
                                ? 'Please enter a title'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _urlController,
                            decoration: const InputDecoration(
                              labelText: 'URL',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value?.isEmpty ?? true)
                                return 'Please enter a URL';
                              if (!value!.contains('.'))
                                return 'Please enter a valid URL';
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed:
                            _isLoading ? null : () => Navigator.pop(context),
                        child: const Text('CANCEL'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: _isLoading ? null : _submit,
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(isEditing ? 'SAVE' : 'ADD'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
