import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // pre zapamätanie pozície v lekcii
import 'package:flippy/theme/colors.dart';
import 'package:flippy/theme/fonts.dart';
import 'package:flippy/widgets/word_card.dart';

class LessonScreen extends StatefulWidget {
  // získané dáta z GoRouter (routerConfig passes args via state.extra)
  final Map<String, dynamic>? args;
  const LessonScreen({super.key, this.args});

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  late final PageController _pageController;
  int _index = 0;
  bool _showBack = false; // či sa zobrazuje zadná strana kartičky

  List<Map<String, dynamic>> _words = [];
  String _title = '';

  // kľúč pre zapamätanie pozície v lekcii
  String? _saveKey;

  // uložené označené id slovíčok
  Set<String> _marked = <String>{};

  // kľúč pre uchovanie označených slovíčok (per-subchapter)
  late String _markedKey;

  // pinch / gallery state
  double _minScaleSeen = 1.0;
  bool _galleryOpen = false;
  // trigger when user pinches fingers together (scale goes below this)
  static const double _galleryTriggerScale = 0.85;

  Future<void> _loadMarked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_markedKey) ?? <String>[];
      setState(() => _marked = list.toSet());
    } catch (_) {}
  }

  Future<void> _saveMarked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_markedKey, _marked.toList());
    } catch (_) {}
  }

  void _toggleMarked(String id) {
    setState(() {
      if (_marked.contains(id)) {
        _marked.remove(id);
      } else {
        _marked.add(id);
      }
    });
    _saveMarked();
  }

  // zabezpečí že didChangeDependencies inicializuje len raz
  bool _inited = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  // persist current index
  Future<void> _saveIndex(int i) async {
    if (_saveKey == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_saveKey!, i);
    } catch (_) {}
  }

  Future<void> _loadSavedIndexAndJump() async {
    if (_saveKey == null || _words.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_saveKey!);
      if (saved != null && saved >= 0 && saved < _words.length) {
        setState(() {
          _index = saved;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageController.hasClients) {
            _pageController.jumpToPage(saved);
          }
        });
      }
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;

    // prefer widget.args (GoRouter) a fallback na ModalRoute (compat)
    final routeArgs =
        widget.args ??
        (ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?);
    if (routeArgs != null) {
      // podporujeme oba názvy: "subchapterTitle" (chapters_screen) alebo "title"
      _title =
          (routeArgs['subchapterTitle'] ?? routeArgs['title'] ?? '') as String;
      final raw = routeArgs['words'] ?? routeArgs['wordList'];
      if (raw is List) {
        _words = raw.map((e) {
          if (e is Map<String, dynamic>) return e;
          if (e is Map) return Map<String, dynamic>.from(e);
          return <String, dynamic>{};
        }).toList();
      }

      // prepare persistence key (prefer stable id if available)
      final id = (routeArgs['subchapterId'] ?? routeArgs['id'] ?? _title)
          .toString();
      _saveKey = 'lesson_pos_$id';

      // set marked key per subchapter (sanitize id)
      final keyId = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      _markedKey = 'marked_words_$keyId';

      // load saved index (after words are set)
      _loadSavedIndexAndJump();
      // load marked words for this subchapter
      _loadMarked();
    }
    _inited = true;
  }

  void _goTo(int idx) {
    if (_words.isEmpty) return;
    if (idx < 0) idx = 0;
    if (idx >= _words.length) idx = _words.length - 1;
    _pageController.animateToPage(
      idx,
      duration: const Duration(milliseconds: 300),
      curve: Curves.ease,
    );
    setState(() => _index = idx);
    _saveIndex(idx);
  }

  Widget _buildCard(Map<String, dynamic> word) {
    final sk = word['sk'] ?? '';
    final en = word['en'] ?? '';
    final pron = word['pronunciation'] ?? '';
    final img = word['image'] ?? '';

    return GestureDetector(
      onTap: () => setState(() => _showBack = !_showBack),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, anim) {
          final rotate = Tween(begin: pi, end: 0.0).animate(anim);
          return AnimatedBuilder(
            animation: rotate,
            child: child,
            builder: (context, child) {
              return Transform(
                transform: Matrix4.rotationY(rotate.value),
                alignment: Alignment.center,
                child: child,
              );
            },
          );
        },
        child: _showBack
            ? Container(
                key: const ValueKey('back'),
                margin: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      en.toString().toUpperCase(),
                      style: AppTextStyles.lesson,
                    ),
                    const SizedBox(height: 12),
                    if (img != null && img.toString().isNotEmpty)
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: WordImage(
                            assetPath: img.toString(),
                            fallbackText: en.toString(),
                            maxHeight: 240,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(pron.toString(), style: AppTextStyles.body),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: () => setState(() => _showBack = false),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : Container(
                key: const ValueKey('front'),
                margin: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.text, width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 8),
                    // označiť ako problém
                    Builder(
                      builder: (ctx) {
                        final id = word['id']?.toString() ?? en.toString();
                        final marked = _marked.contains(id);
                        return IconButton(
                          icon: Icon(
                            Icons.priority_high,
                            color: marked ? Colors.red : AppColors.text,
                          ),
                          onPressed: () => _toggleMarked(id),
                          tooltip: marked
                              ? 'Označené ako problém'
                              : 'Označiť ako problém',
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      sk.toString().toUpperCase(),
                      style: AppTextStyles.lesson,
                    ),
                    const SizedBox(height: 12),
                    if (img != null && img.toString().isNotEmpty)
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: WordImage(
                            assetPath: img.toString(),
                            fallbackText: en.toString(),
                            maxHeight: 240,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: IconButton(
                          icon: const Icon(Icons.rotate_right),
                          onPressed: () => setState(() => _showBack = true),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _words.length;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.accent, AppColors.background],
            stops: const [0.0, 0.15],
          ),
        ),
        // vnútorný Scaffold s priehľadným appBarom (rovnaký štýl ako v Chapters)
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            title: Text(
              _title.isEmpty ? 'Lekcia' : _title,
              style: AppTextStyles.chapter,
            ),
            foregroundColor: AppColors.text,
          ),
          body: SafeArea(
            child: Column(
              children: [
                // Card pager
                Expanded(
                  // wrap pager with GestureDetector to detect pinch and open gallery
                  child: total == 0
                      ? const Center(
                          child: Text(
                            'No words',
                            style: TextStyle(fontSize: 16),
                          ),
                        )
                      : GestureDetector(
                          onScaleStart: (_) {
                            _minScaleSeen = 1.0;
                          },
                          onScaleUpdate: (details) {
                            _minScaleSeen = min(_minScaleSeen, details.scale);
                          },
                          onScaleEnd: (_) async {
                            if (_minScaleSeen <= _galleryTriggerScale &&
                                !_galleryOpen) {
                              _galleryOpen = true;
                              final selected = await _showGalleryAndPick();
                              _galleryOpen = false;
                              if (selected != null) {
                                // jump to selected card
                                _goTo(selected);
                              }
                            }
                            _minScaleSeen = 1.0;
                          },
                          child: PageView.builder(
                            controller: _pageController,
                            itemCount: total,
                            onPageChanged: (i) => setState(() {
                              _index = i;
                              _showBack = false;
                              _saveIndex(i); // save on page change
                            }),
                            itemBuilder: (context, i) {
                              final word = _words[i];
                              return _buildCard(word);
                            },
                          ),
                        ),
                ),

                // Footer controls
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Column(
                    children: [
                      Text(
                        total == 0 ? '0/0' : '${_index + 1}/$total',
                        style: AppTextStyles.lesson,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_left),
                            onPressed: () => _goTo(_index - 1),
                          ),
                          const SizedBox(width: 8),
                          // quick jump buttons: prev, current, next
                          for (
                            var i = max(0, _index - 1);
                            i <= min(total - 1, _index + 1);
                            i++
                          )
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: i == _index
                                      ? AppColors.primary
                                      : Colors.white,
                                  elevation: 4,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: () => _goTo(i),
                                child: Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    color: i == _index
                                        ? Colors.white
                                        : AppColors.text,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.arrow_right),
                            onPressed: () => _goTo(_index + 1),
                          ),
                        ],
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

  // shows gallery dialog/grid and returns tapped index (or null)
  Future<int?> _showGalleryAndPick() {
    // fixed 5 rows x 4 columns layout; allow scrolling if more items
    const cols = 4;
    const rows = 5;
    const tileHeight = 100.0;
    final gridHeight = rows * tileHeight;

    return showDialog<int>(
      context: context,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          child: SizedBox(
            height: min(
              gridHeight + 56,
              MediaQuery.of(context).size.height * 0.85,
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text('Galeria', style: AppTextStyles.heading),
                ),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: cols,
                    childAspectRatio: 0.9,
                    padding: const EdgeInsets.all(8),
                    children: List.generate(_words.length, (i) {
                      final w = _words[i];
                      final en = (w['en'] ?? w['english'] ?? '').toString();
                      final imgPath = (w['image'] ?? '').toString();
                      // identify word id used for marking
                      final wid = (w['id']?.toString() ?? en);
                      final isMarked = _marked.contains(wid);
                      return InkWell(
                        onTap: () => Navigator.of(ctx).pop(i),
                        child: Card(
                          margin: const EdgeInsets.all(6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: isMarked ? AppColors.accent: Colors.transparent,
                              width: isMarked ? 3.0 : 1.0,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (imgPath.isNotEmpty)
                                SizedBox(
                                  height: 64,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    child: WordImage(
                                      assetPath: imgPath,
                                      fallbackText: en,
                                      maxHeight: 64,
                                    ),
                                  ),
                                )
                              else
                                const SizedBox(height: 64),
                              const SizedBox(height: 6),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  child: Text(
                                    en,
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 2,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
