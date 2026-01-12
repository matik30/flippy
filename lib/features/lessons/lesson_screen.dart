import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // pre zapamätanie pozície v lekcii
import 'package:path/path.dart' as path;
import 'package:flippy/theme/fonts.dart';
import 'package:flippy/widgets/word_card.dart';
import 'package:flippy/features/quiz/quiz_screen.dart';

// Obrazovka lekcie — zobrazuje kartičky slovíčok, galériu a umožňuje spustiť test (kvíz).
// Obsahuje persistenciu pozície, označovanie slovíčok a sledovanie navštívených položiek.

class LessonScreen extends StatefulWidget {
  // získané dáta z GoRouter
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
  String? _baseDir;
  String? _baseUrl;

  // pôvodné route args (uložené aby sme vytvorili rovnaký quiz kľúč ako iné obrazovky)
  Map<String, dynamic>? _routeArgs;

  // kľúč pre zapamätanie pozície v lekcii
  String? _saveKey;

  // uložené označené id slovíčok
  Set<String> _marked = <String>{};

  // kľúč pre uchovanie označených slovíčok (per-subchapter)
  late String _markedKey;

  // navštívené indexy pre povolenie testu; uchovávané per subchapter
  Set<int> _visited = <int>{};
  late String _visitedKey;
  bool _suppressVisitMark = false; // neoznačovať pri skákaní z galérie

  // stav galérie
  double _minScaleSeen = 1.0;
  bool _galleryOpen = false;
  // prah pre otvorenie galérie
  static const double _galleryTriggerScale = 0.98;

  Future<void> _loadMarked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_markedKey) ?? <String>[];
      if (mounted) setState(() => _marked = list.toSet());
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

  // Uloží aktuálny index
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
          // označiť uloženú stránku ako navštívenú
          if (mounted) {
            // neoznačovať pri skákaní z galérie
            _markVisited(saved);
          }
        });
      }
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;

    // Získanie argumentov z trasy alebo widgetu
    final routeArgs =
        widget.args ??
        (ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?);
    // uložené aby sme vytvorili rovnaký quiz kľúč ako iné obrazovky
    _routeArgs = routeArgs != null
        ? Map<String, dynamic>.from(routeArgs)
        : null;
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

      // Vytvorenie jedinečného podpisu pre aktuálny kvíz
      String? signature;
      final tb =
          routeArgs['textbook'] ??
          routeArgs['book'] ??
          routeArgs['textbookMap'];
      if (tb is Map) {
        final filePath = tb['__file__'];
        if (filePath is String && filePath.isNotEmpty) {
          _baseDir = path.dirname(filePath);
        }

        // základná URL pre načítanie obrázkov
        final serverUrl = tb['serverBaseUrl'] ?? tb['baseUrl'];
        if (serverUrl is String && serverUrl.isNotEmpty) {
          _baseUrl = serverUrl;
        }

        final tbId = (tb['id'] ?? tb['textbookId'] ?? tb['bookId'] ?? '')
            .toString();

        final chapterIds = <String>[];
        final subIds = <String>[];

        if (tb['chapters'] is List) {
          for (final ch in tb['chapters']) {
            if (ch is Map) {
              final cid = (ch['id'] ?? ch['chapterId'] ?? '').toString();
              if (cid.isNotEmpty) chapterIds.add(cid);
              if (ch['subchapters'] is List) {
                for (final sc in ch['subchapters']) {
                  if (sc is Map) {
                    final sid = (sc['id'] ?? sc['subchapterId'] ?? '')
                        .toString();
                    if (sid.isNotEmpty) subIds.add(sid);
                  }
                }
              }
            }
          }
        }

        // získanie id všetkých slovíčok v lekcii
        final wordIds = _words
            .map((w) => (w['id']?.toString() ?? ''))
            .where((s) => s.isNotEmpty)
            .toList();

        final partsList = <String>[];
        if (tbId.isNotEmpty) partsList.add(tbId);
        if (chapterIds.isNotEmpty) partsList.add(chapterIds.join('|'));
        if (subIds.isNotEmpty) partsList.add(subIds.join('|'));
        if (wordIds.isNotEmpty) partsList.add(wordIds.join('|'));

        if (partsList.isNotEmpty) signature = partsList.join('::');
      }

      // vytvorenie kľúčov pre persistenciu
      String keySource;
      if (signature != null && signature.isNotEmpty) {
        keySource = signature;
      } else {
        final subId =
            (routeArgs['subchapterId'] ??
                    routeArgs['id'] ??
                    routeArgs['subId'] ??
                    routeArgs['sub'] ??
                    '')
                .toString();
        final subTitle =
            (routeArgs['subchapterTitle'] ??
                    routeArgs['title'] ??
                    routeArgs['name'] ??
                    _title)
                .toString();

        final chapterId =
            (routeArgs['chapterId'] ??
                    routeArgs['parentId'] ??
                    routeArgs['chapterId'] ??
                    '')
                .toString();
        final chapterTitle =
            (routeArgs['chapterTitle'] ?? routeArgs['chapter'] ?? '')
                .toString();

        final bookId = (routeArgs['bookId'] ?? routeArgs['courseId'] ?? '')
            .toString();
        final bookTitle = (routeArgs['bookTitle'] ?? routeArgs['book'] ?? '')
            .toString();

        final parts = [
          bookId,
          bookTitle,
          chapterId,
          chapterTitle,
          subId,
          subTitle,
        ].map((s) => s.toString().trim()).where((s) => s.isNotEmpty).toList();

        final combinedKey = parts.isNotEmpty ? parts.join('::') : subTitle;
        keySource = combinedKey;
      }

      final keyId = keySource.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

      _saveKey = 'lesson_pos_$keyId';
      _markedKey = 'marked_words_$keyId';
      _visitedKey = 'visited_$keyId';

      // načítanie uloženého indexu a skok naň
      _loadSavedIndexAndJump();
      // načítanie označených slovíčok pre túto podkapitolu
      _loadMarked();
      // načítanie navštívených indexov
      _loadVisited();

      // zabezpečenie, že aktuálne zobrazená stránka sa počíta ako navštívená (pokrytie počiatočného zobrazenia)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_words.isNotEmpty &&
            !_visited.contains(_index) &&
            !_suppressVisitMark) {
          _markVisited(_index);
        }
      });
    }
    _inited = true;
  }

  Future<void> _loadVisited() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_visitedKey) ?? <String>[];
      final loaded = list.map(int.parse).toSet();
      if (!mounted) return;
      setState(() => _visited = loaded);

      // zabezpečenie, že aktuálne zobrazená stránka sa počíta ako navštívená (pokrytie počiatočného zobrazenia)
      if (_words.isNotEmpty &&
          !_visited.contains(_index) &&
          !_suppressVisitMark) {
        _markVisited(_index);
      }
    } catch (_) {}
  }

  Future<void> _saveVisited() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _visitedKey,
        _visited.map((e) => e.toString()).toList(),
      );
    } catch (_) {}
  }

  void _markVisited(int idx) {
    if (_visited.contains(idx)) return;
    setState(() => _visited.add(idx));
    _saveVisited();
  }

  bool get _canTest {
    if (_words.isEmpty) return false;
    // používateľ musí navštíviť každú položku aspoň raz
    return _visited.length >= _words.length;
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
    // zabezpečenie, že aktuálne zobrazená stránka sa počíta ako navštívená
    if (!_suppressVisitMark) {
      _markVisited(idx);
    }
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
                margin: EdgeInsets.symmetric(
                  horizontal: MediaQuery.of(context).size.width * 0.20,
                  vertical: MediaQuery.of(context).size.height * 0.08,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.onSurface,
                    width: 2,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 56),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 8),

                            Builder(
                              builder: (ctx) {
                                final id =
                                    word['id']?.toString() ?? en.toString();
                                final marked = _marked.contains(id);
                                return IconButton(
                                  icon: Icon(
                                    Icons.priority_high,
                                    color: marked
                                        ? Colors.red
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                  ),
                                  onPressed: () => _toggleMarked(id),
                                );
                              },
                            ),

                            Text(
                              en.toString().toUpperCase(),
                              style: AppTextStyles.lesson,
                            ),

                            const SizedBox(height: 12),

                            if (img != null && img.toString().isNotEmpty)
                              Flexible(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  child: WordImage(
                                    assetPath: img.toString(),
                                    fallbackText: en.toString(),
                                    baseDir: _baseDir,
                                    baseUrl: _baseUrl,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 12),
                            Text(pron.toString(), style: AppTextStyles.body),
                          ],
                        ),
                      ),
                    ),

                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: () => setState(() => _showBack = false),
                      ),
                    ),
                  ],
                ),
              )
            : Container(
                key: const ValueKey('front'),
                margin: EdgeInsets.symmetric(
                  horizontal: MediaQuery.of(context).size.width * 0.20,
                  vertical: MediaQuery.of(context).size.height * 0.08,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.onSurface,
                    width: 2,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 56),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 8),

                            Builder(
                              builder: (ctx) {
                                final id =
                                    word['id']?.toString() ?? sk.toString();
                                final marked = _marked.contains(id);
                                return IconButton(
                                  icon: Icon(
                                    Icons.priority_high,
                                    color: marked
                                        ? Colors.red
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                  ),
                                  onPressed: () => _toggleMarked(id),
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
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  child: WordImage(
                                    assetPath: img.toString(),
                                    fallbackText: sk.toString(),
                                    baseDir: _baseDir,
                                    baseUrl: _baseUrl,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: IconButton(
                        icon: const Icon(Icons.rotate_right),
                        onPressed: () => setState(() => _showBack = true),
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
            colors: [
              Theme.of(context).colorScheme.secondary,
              Theme.of(context).colorScheme.surface,
            ],
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
            title: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                _title.isEmpty ? 'Lekcia' : _title,
                style: AppTextStyles.chapter,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            foregroundColor: Theme.of(context).colorScheme.onSurface,
          ),
          body: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 16),
                // Test button (funckia je povolená len ak sú všetky položky navštívené)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    child: ElevatedButton(
                      onPressed: _canTest
                          ? () async {
                              final args = <String, dynamic>{
                                // prenesenie pôvodných argumentov pre konzistenciu kľúčov
                                ...?_routeArgs,
                                'words': _words,
                                'testType': 'mcq',
                                'subchapterTitle': _title,
                              };

                              final navigator = Navigator.of(context);
                              final base = quizKeyFromArgs(
                                _routeArgs ?? widget.args ?? {},
                                'mcq',
                              );

                              try {
                                final prefs =
                                    await SharedPreferences.getInstance();
                                final hasIndex =
                                    prefs.getInt('${base}_index') != null;
                                if (!hasIndex) {
                                  // prvý pokus o test v tejto lekcii — vymazať všetky staré dáta
                                  await prefs.remove('${base}_index');
                                  await prefs.remove('${base}_answered');
                                  await prefs.remove('${base}_correct');
                                  await prefs.remove('${base}_input');
                                  await prefs.setInt('${base}_score', 0);
                                  await prefs.setBool('${base}_done', false);
                                }
                              } catch (_) {}

                              // spustenie quiz obrazovky a čakanie na návrat
                              await navigator.push(
                                MaterialPageRoute(
                                  builder: (_) => QuizScreen(args: args),
                                ),
                              );
                              if (!mounted) return;
                              navigator.pop();
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _canTest
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade300,
                      ),
                      child: Text(
                        'Otestuj sa',
                        style: TextStyle(
                          color: _canTest
                              ? Theme.of(context).colorScheme.onPrimary
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),

                // Kartičky slovíčok v PageView
                Expanded(
                  // ak je prázdna lekcia, zobrazí sa len text "No words"
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
                              // otvorenie galérie
                              final selected = await _showGalleryAndPick(
                                initialIndex: _index,
                              );
                              _galleryOpen = false;

                              // zabezpečenie, že aktuálne zobrazená stránka sa počíta ako navštívená
                              if (!mounted) {
                                _minScaleSeen = 1.0;
                                return;
                              }

                              if (selected != null) {
                                // neoznačovať pri skákaní z galérie
                                setState(() => _suppressVisitMark = true);
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
                              _saveIndex(i); // uloženie pozície
                              // zabezpečenie, že aktuálne zobrazená stránka sa počíta ako navštívená
                              if (!_suppressVisitMark) {
                                _markVisited(i);
                              } else {
                                // reset potlačenie označenia
                                _suppressVisitMark = false;
                              }
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
                  padding: const EdgeInsets.symmetric(vertical: 32.0),
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
                          // zobrazenie tlačidiel pre aktuálnu, predchádzajúcu a nasledujúcu stránku
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
                                      ? Theme.of(context).colorScheme.primary
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
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.onPrimary
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
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

  // Zobrazenie galérie a výber položky
  Future<int?> _showGalleryAndPick({int initialIndex = 0}) async {
    const cols = 3;

    // výpočet maximálnej dĺžky anglického slova pre úpravu veľkosti písma
    int maxEnLen = 0;
    for (final w in _words) {
      final en = (w['en'] ?? w['english'] ?? '').toString();
      if (en.length > maxEnLen) maxEnLen = en.length;
    }

    double computeFontSize(int maxLen) {
      if (maxLen <= 8) return 16.0;
      if (maxLen <= 12) return 14.0;
      if (maxLen <= 16) return 13.0;
      if (maxLen <= 24) return 12.0;
      return 11.0;
    }

    final tileFontSize = computeFontSize(maxEnLen);

    if (!mounted) return null;

    final selected = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        fullscreenDialog: true,
        builder: (ctx) {
          double maxScaleSeen = 1.0;
          const double returnTriggerScale = 1.15;

          return GestureDetector(
            onScaleStart: (_) => maxScaleSeen = 1.0,
            onScaleUpdate: (details) =>
                maxScaleSeen = max(maxScaleSeen, details.scale),
            onScaleEnd: (_) {
              if (maxScaleSeen >= returnTriggerScale) {
                if (ctx.mounted) Navigator.of(ctx).pop(initialIndex);
              }
            },
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Theme.of(ctx).colorScheme.secondary,
                    Theme.of(ctx).colorScheme.surface,
                  ],
                  stops: const [0.0, 0.15],
                ),
              ),
              child: Scaffold(
                backgroundColor: Colors.transparent,
                appBar: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  centerTitle: true,
                  title: Text('Galéria', style: AppTextStyles.heading),
                  foregroundColor: Theme.of(ctx).colorScheme.onSurface,
                ),
                body: SafeArea(
                  child: Column(
                    children: <Widget>[
                      Expanded(
                        child: GridView.count(
                          crossAxisCount: cols,
                          childAspectRatio: 1.4,
                          padding: const EdgeInsets.all(6),
                          children: List<Widget>.generate(_words.length, (i) {
                            final w = _words[i];
                            final en = (w['en'] ?? w['english'] ?? '')
                                .toString();
                            final wid = (w['id']?.toString() ?? en);
                            final isMarked = _marked.contains(wid);

                            return InkWell(
                              onTap: () {
                                if (ctx.mounted) Navigator.of(ctx).pop(i);
                              },
                              child: Card(
                                margin: const EdgeInsets.all(4),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(
                                    color: isMarked
                                        ? Theme.of(ctx).colorScheme.secondary
                                        : Colors.transparent,
                                    width: isMarked ? 3.0 : 1.0,
                                  ),
                                ),
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8.0,
                                      vertical: 4.0,
                                    ),
                                    child: Text(
                                      en,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: tileFontSize,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(
                                          ctx,
                                        ).colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 12.0,
                        ),
                        child: ElevatedButton(
                          onPressed: _canTest
                              ? () {
                                  if (!ctx.mounted) return;
                                  final args = Map<String, dynamic>.from(
                                    widget.args ?? {},
                                  );
                                  args['testType'] = args['testType'] ?? 'mcq';
                                  Navigator.of(ctx).push(
                                    MaterialPageRoute(
                                      builder: (_) => QuizScreen(args: args),
                                    ),
                                  );
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                            backgroundColor: _canTest
                                ? Theme.of(ctx).colorScheme.primary
                                : Colors.grey.shade300,
                          ),
                          child: Text(
                            'Otestuj sa',
                            style: TextStyle(
                              color: _canTest
                                  ? Theme.of(ctx).colorScheme.onPrimary
                                  : Theme.of(ctx).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    return selected;
  }
}
