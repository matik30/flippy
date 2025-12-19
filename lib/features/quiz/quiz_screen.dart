import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flippy/theme/fonts.dart';
import 'package:flippy/widgets/word_card.dart';

// Generate a stable key base for a quiz from the same args structure used
// across the app. Other screens can call this to read/write the same prefs.
String quizKeyFromArgs(Map<String, dynamic>? args, String testType) {
  final a = args ?? {};
  final tb = a['textbook'] ?? a['book'] ?? a['textbookMap'];
  String part = '';
  if (tb is Map) {
    part = (tb['id'] ?? tb['textbookId'] ?? tb['bookId'] ?? '').toString();
  }
  final subId = (a['subchapterId'] ?? a['id'] ?? a['subId'] ?? a['sub'] ?? '')
      .toString();
  final subTitle = (a['subchapterTitle'] ?? a['title'] ?? a['name'] ?? '')
      .toString();
  final combined = [
    part,
    subId,
    subTitle,
  ].where((s) => s.isNotEmpty).join('::');
  final safe = combined.isEmpty
      ? 'default'
      : combined.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  return 'quiz_${safe}_$testType';
}

const int quizSize = 15;

class QuizScreen extends StatefulWidget {
  final Map<String, dynamic>? args;
  const QuizScreen({super.key, this.args});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  late List<Map<String, dynamic>> _words; // bude prepísaný po príprave
  late final List<Map<String, dynamic>>
  _allWords; // original full list from args
  late String _testType; // 'grammar' or 'mcq'
  int _index = 0;
  int _score = 0;
  bool _answered = false;
  bool _correct = false;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final Random _rnd = Random();
  String?
  _selectedOption; // currently chosen MCQ option (for colouring after answer)

  List<String> _currentOptions = []; // for mcq
  static const int _quizSize = quizSize; // desired number of items in a quiz

  @override
  void initState() {
    super.initState();
    final args = widget.args ?? {};
    final rawWords = args['words'] ?? args['wordList'] ?? <dynamic>[];
    if (rawWords is List) {
      _allWords = rawWords
          .map(
            (e) => e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e),
          )
          .cast<Map<String, dynamic>>()
          .toList();
      _words = <Map<String, dynamic>>[]; // will be prepared below
    } else {
      _allWords = <Map<String, dynamic>>[];
      _words = <Map<String, dynamic>>[];
    }
    _testType = (args['testType'] ?? 'mcq') as String;
    if (_testType != 'grammar' && _testType != 'mcq') _testType = 'mcq';
    // Prepare the actual quiz word list (weighted random sampling with replacement)
    // prepare words (will reuse persisted sample if present), then load progress
    _prepareQuizWords().then((_) async {
      await _loadProgress();
      if (_words.isNotEmpty && _testType == 'mcq') _buildOptions();
    });
  }

  String _progressKeyBase() {
    return quizKeyFromArgs(widget.args, _testType);
  }

  Future<void> _saveProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final base = _progressKeyBase();
      await prefs.setInt('${base}_index', _index);
      await prefs.setInt('${base}_score', _score);
      await prefs.setBool('${base}_answered', _answered);
      await prefs.setBool('${base}_correct', _correct);
      if (_testType == 'grammar') {
        await prefs.setString('${base}_input', _controller.text);
      }
    } catch (_) {}
  }

  Future<void> _loadProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final base = _progressKeyBase();
      final idx = prefs.getInt('${base}_index');
      final sc = prefs.getInt('${base}_score');
      final ans = prefs.getBool('${base}_answered');
      final cor = prefs.getBool('${base}_correct');
      final input = prefs.getString('${base}_input');

      if (!mounted) return;

      if (idx != null && idx >= 0 && idx < _words.length) {
        // resume an in-progress run
        setState(() {
          _index = idx;
          _score = sc ?? 0;
          _answered = ans ?? false;
          _correct = cor ?? false;
          if (_testType == 'grammar' && input != null) _controller.text = input;
        });
      } else {
        // No saved index -> treat as a fresh run. Clear any leftover persisted run state
        try {
          await prefs.remove('${base}_index');
          await prefs.remove('${base}_answered');
          await prefs.remove('${base}_correct');
          await prefs.remove('${base}_input');
          // ensure persisted sample is cleared for a fresh run so new sampling occurs
          await prefs.remove('${base}_sample');
          await prefs.setBool('${base}_done', false);
          await prefs.setInt('${base}_score', 0);
        } catch (_) {}

        if (!mounted) return;
        setState(() {
          _index = 0;
          _score = 0;
          _answered = false;
          _correct = false;
          if (_testType == 'grammar') _controller.clear();
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String _normalize(String s) => s.trim().toLowerCase();

  // Normalize a string for grammar comparison: remove parenthetical content,
  // split alternatives by '/', strip non-letter characters (keep a-z and spaces),
  // collapse whitespace and lowercase.
  String _normalizeForComparison(String s) {
    var t = s.toLowerCase();
    // replace any parentheses content with space
    t = t.replaceAll(RegExp(r"\([^)]*\)"), ' ');
    // remove any characters that are not a-z or whitespace
    t = t.replaceAll(RegExp(r'[^a-z\s]'), ' ');
    // collapse whitespace
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  // From a correct-answer string produce a set of accepted normalized variants.
  // Handles slash-separated alternatives and parenthetical parts.
  Set<String> _acceptedVariants(String correctRaw) {
    final out = <String>{};
    final parts = correctRaw.split('/');
    for (var p in parts) {
      final norm = _normalizeForComparison(p);
      if (norm.isNotEmpty) out.add(norm);
    }
    return out;
  }

  String _correctAnswerFor(Map<String, dynamic> w) {
    final en = w['en'] ?? w['english'] ?? '';
    if (en is String) return en.trim();
    if (en is List && en.isNotEmpty) return en.first.toString().trim();
    return en.toString().trim();
  }

  void _buildOptions() {
    final w = _words[_index];
    final correct = _correctAnswerFor(w);

    // Collect unique other answers (exclude the correct answer)
    final othersSet = <String>{};
    for (var i = 0; i < _words.length; i++) {
      if (i == _index) continue;
      final o = _correctAnswerFor(_words[i]);
      if (o.isNotEmpty && _normalize(o) != _normalize(correct)) {
        othersSet.add(o);
      }
    }

    final others = othersSet.toList();
    others.shuffle(_rnd);

    final opts = <String>[];
    opts.add(correct);
    for (var i = 0; i < others.length && opts.length < 3; i++) {
      opts.add(others[i]);
    }
    while (opts.length < 3) {
      opts.add('—');
    }
    opts.shuffle(_rnd);
    setState(() => _currentOptions = opts);
  }

  void _submitGrammar() {
    if (_answered) return;
    final guess = _controller.text;
    final correct = _correctAnswerFor(_words[_index]);
    final accepted = _acceptedVariants(correct);
    final guessNorm = _normalizeForComparison(guess);
    final ok = accepted.contains(guessNorm);
    setState(() {
      _answered = true;
      _correct = ok;
      if (ok) _score++;
    });
    // hide keyboard
    _focusNode.unfocus();
    _saveProgress();
    if (!ok) _markWordAsProblem(_words[_index]);
  }

  void _chooseMcq(String opt) {
    if (_answered) return;
    _selectedOption = opt;
    final correct = _correctAnswerFor(_words[_index]);
    final ok = _normalize(opt) == _normalize(correct);
    setState(() {
      _answered = true;
      _correct = ok;
      if (ok) _score++;
    });
    _saveProgress();
    if (!ok) _markWordAsProblem(_words[_index]);
  }

  Future<void> _markWordAsProblem(Map<String, dynamic> w) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keyId = _safeIdFromArgs();
      final mkKey = 'marked_words_$keyId';
      final id = (w['id'] ?? w['en'] ?? w['english'] ?? '').toString();
      if (id.isEmpty) return;
      final list = prefs.getStringList(mkKey) ?? <String>[];
      if (!list.contains(id)) {
        list.add(id);
        await prefs.setStringList(mkKey, list);
      }
    } catch (_) {}
  }

  void _next() {
    if (_index + 1 >= _words.length) {
      // finished: persist final score first, then show dialog offering to just close
      // or close and return to the previous screen so lesson_or_quiz can refresh.
      _persistFinalScore().then((_) {
        if (!mounted) return;
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Výsledok'),
            content: Text('Skóre: $_score/${_words.length}'),
            actions: [
              // Zavrieť: close dialog and also close QuizScreen to return to LessonOrQuiz
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // close dialog
                  if (mounted) Navigator.of(context).pop(); // pop QuizScreen
                },
                child: const Text('Zavrieť'),
              ),
              // OK: only close dialog, stay on QuizScreen
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      });
      return;
    }
    setState(() {
      _index++;
      _answered = false;
      _correct = false;
      _selectedOption = null;
      _controller.clear();
      if (_testType == 'mcq') _buildOptions();
    });
    // ensure keyboard focus for grammar
    if (_testType == 'grammar') FocusScope.of(context).requestFocus(_focusNode);
    _saveProgress();
  }

  Future<void> _persistFinalScore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final base = _progressKeyBase();
      await prefs.setInt('${base}_score', _score);
      await prefs.setBool('${base}_done', true);
      // remove transient run state so next run starts fresh
      await prefs.remove('${base}_index');
      await prefs.remove('${base}_answered');
      await prefs.remove('${base}_correct');
      await prefs.remove('${base}_input');
    } catch (_) {}
  }

  String _safeIdFromArgs() {
    final a = widget.args ?? {};
    String? signature;
    final tb = a['textbook'] ?? a['book'] ?? a['textbookMap'];
    if (tb is Map) {
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
                  final sid = (sc['id'] ?? sc['subchapterId'] ?? '').toString();
                  if (sid.isNotEmpty) subIds.add(sid);
                }
              }
            }
          }
        }
      }

      final wordIds = (a['words'] is List)
          ? (a['words'] as List)
                .map((w) => (w is Map ? (w['id']?.toString() ?? '') : ''))
                .where((s) => s.isNotEmpty)
                .toList()
          : <String>[];

      final partsList = <String>[];
      if (tbId.isNotEmpty) partsList.add(tbId);
      if (chapterIds.isNotEmpty) partsList.add(chapterIds.join('|'));
      if (subIds.isNotEmpty) partsList.add(subIds.join('|'));
      if (wordIds.isNotEmpty) partsList.add(wordIds.join('|'));

      if (partsList.isNotEmpty) signature = partsList.join('::');
    }

    String keySource;
    if (signature != null && signature.isNotEmpty) {
      keySource = signature;
    } else {
      final subId =
          (a['subchapterId'] ?? a['id'] ?? a['subId'] ?? a['sub'] ?? '')
              .toString();
      final subTitle = (a['subchapterTitle'] ?? a['title'] ?? a['name'] ?? '')
          .toString();

      final chapterId =
          (a['chapterId'] ?? a['parentId'] ?? a['chapterId'] ?? '').toString();
      final chapterTitle = (a['chapterTitle'] ?? a['chapter'] ?? '').toString();

      final bookId = (a['bookId'] ?? a['courseId'] ?? '').toString();
      final bookTitle = (a['bookTitle'] ?? a['book'] ?? '').toString();

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
    return keyId;
  }

  Future<void> _prepareQuizWords() async {
    // If there are no source words, nothing to prepare
    if (_allWords.isEmpty) return;

    // Read marked/problematic words for this subchapter so we can bias selection
    final prefs = await SharedPreferences.getInstance();
    final keyId = _safeIdFromArgs();
    final markedList = prefs.getStringList('marked_words_$keyId') ?? <String>[];
    final markedSet = markedList.toSet();
    // persist/load sample so other screens see the same generated list
    final base = quizKeyFromArgs(widget.args, _testType);
    final sampleKey = '${base}_sample';
    final existingSample = prefs.getStringList(sampleKey);
    if (existingSample != null && existingSample.isNotEmpty) {
      // rebuild words list from persisted ids in the same order
      final rebuilt = <Map<String, dynamic>>[];
      for (final id in existingSample) {
        final found = _allWords.firstWhere((w) {
          final wid = (w['id'] ?? w['en'] ?? w['english'] ?? '').toString();
          return wid == id;
        }, orElse: () => <String, dynamic>{});
        if (found.isNotEmpty) rebuilt.add(Map<String, dynamic>.from(found));
      }
      if (rebuilt.isNotEmpty) {
        setState(() {
          _words = rebuilt;
          if (_index >= _words.length) _index = 0;
        });
        return;
      }
    }

    // Build weights: marked words get higher weight
    final weights = <int>[];
    for (final w in _allWords) {
      final id = (w['id'] ?? w['en'] ?? w['english'] ?? '').toString();
      // bias on marked words (increased to 3 as requested)
      weights.add(markedSet.contains(id) ? 3 : 1);
    }

    // Weighted sampling without replacement using Efraimidis–Spirakis method.
    final selected = <Map<String, dynamic>>[];
    final n = _allWords.length;
    if (n > 0) {
      // If weights are all non-positive, fallback to uniform indices
      final keys = <MapEntry<double, int>>[];
      for (var i = 0; i < n; i++) {
        final w = (weights[i] <= 0) ? 1 : weights[i];
        // generate key = U^(1/w) where U in (0,1]
        final u = (_rnd.nextDouble() * 0.999999) + 1e-9;
        final key = pow(u, 1 / w) as double;
        keys.add(MapEntry(key, i));
      }

      // sort descending by key and pick top min(n, _quizSize)
      keys.sort((a, b) => b.key.compareTo(a.key));
      final take = keys.length < _quizSize ? keys.length : _quizSize;
      final chosenIndices = keys.take(take).map((e) => e.value).toList();

      // build selected unique words in chosen order
      for (final idx in chosenIndices) {
        selected.add(Map<String, dynamic>.from(_allWords[idx]));
      }

      // if we still need more items (quizSize > unique pool), fill by weighted random picks allowing duplicates
      final totalWeight = weights.fold<int>(0, (p, e) => p + e);
      while (selected.length < _quizSize) {
        if (totalWeight <= 0) {
          final idx = _rnd.nextInt(n);
          selected.add(Map<String, dynamic>.from(_allWords[idx]));
          continue;
        }
        var r = _rnd.nextInt(totalWeight);
        var acc = 0;
        var chosen = 0;
        for (var j = 0; j < weights.length; j++) {
          acc += weights[j];
          if (r < acc) {
            chosen = j;
            break;
          }
        }
        selected.add(Map<String, dynamic>.from(_allWords[chosen]));
      }
    }

    // persist sampled ids so other screens (and future resumes) use same order
    try {
      final ids = selected
          .map((w) => (w['id'] ?? w['en'] ?? w['english'] ?? '').toString())
          .toList();
      await prefs.setStringList(sampleKey, ids);
    } catch (_) {}

    setState(() {
      _words = selected;
      // clamp index if out of range after sampling
      if (_index >= _words.length) _index = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.args?['subchapterTitle'] ?? widget.args?['title'] ?? 'Test';
    if (_words.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              title.isEmpty ? 'Lekcia' : title,
              style: AppTextStyles.chapter,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        body: const Center(child: Text('Žiadne slovíčka v tejto lekcii')),
      );
    }

    final word = _words[_index];
    final sk = (word['sk'] ?? word['cz'] ?? '').toString();
    final en = (word['en'] ?? word['english'] ?? '').toString();
    final img = word['image'] ?? '';
    final correct = _correctAnswerFor(word);

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
                title.isEmpty ? 'Lekcia' : title,
                style: AppTextStyles.chapter,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            foregroundColor: Theme.of(context).colorScheme.onSurface,
          ),
          body: Container(
            margin: EdgeInsets.symmetric(
              horizontal: MediaQuery.of(context).size.width * 0.10,
              vertical: MediaQuery.of(context).size.height * 0.15,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Transform.translate(
                  offset: const Offset(0, -70), // 👈 move UP
                  child: Text(
                    'Skóre: $_score / ${_words.length}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    key: ValueKey('quiz_card'),
                    margin: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 30,
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
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Cvičenie ${_index + 1}',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (img != null && img.toString().isNotEmpty)
                            Flexible(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                child: WordImage(
                                  assetPath: img.toString(),
                                  fallbackText: en.toString(),
                                  maxHeight: 240,
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          Text(
                            sk.toUpperCase(),
                            style: AppTextStyles.lesson,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          if (_answered)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Column(
                                children: [
                                  if (_testType == 'grammar') ...[
                                    // Result text (Správne / Nesprávne)
                                    Text(
                                      _correct ? 'Správne' : 'Nesprávne',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.copyWith(
                                            color: _correct
                                                ? Colors.green.shade600
                                                : Colors.red.shade600,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),

                                    // Correct answer shown ONLY if grammar & wrong
                                    if (!_correct)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: 8.0,
                                        ),
                                        child: Text(
                                          _correctAnswerFor(word),
                                          style: AppTextStyles.body.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                if (_testType == 'grammar') ...[
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 22),
                    child: Column(
                      children: [
                        TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submitGrammar(),
                          decoration: InputDecoration(
                            hintText: 'Napíšte anglický preklad',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.black),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _answered ? _next : _submitGrammar,
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                            ),
                            child: Text(
                              _answered ? 'Ďalej' : 'Odoslať',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 22),
                    child: Column(
                      children: [
                        // MCQ options
                        ..._currentOptions.map((opt) {
                          final normOpt = _normalize(opt);
                          final isCorrect = _normalize(correct) == normOpt;
                          final isSelected =
                              _selectedOption != null &&
                              _normalize(_selectedOption!) == normOpt;

                          Color bg;
                          Color txt;
                          IconData? icon;
                          Color? iconColor;

                          if (!_answered) {
                            bg = Theme.of(context).colorScheme.primary;
                            txt = Theme.of(context).colorScheme.onPrimary;
                          } else {
                            if (isCorrect) {
                              bg = Colors.green.shade600;
                              txt = Colors.white;
                              icon = Icons.check_circle;
                              iconColor = Colors.white;
                            } else if (isSelected) {
                              bg = Colors.red.shade600;
                              txt = Colors.white;
                              icon = Icons.cancel;
                              iconColor = Colors.white;
                            } else {
                              bg = Colors.grey.shade200;
                              txt = Theme.of(context).colorScheme.onSurface;
                            }
                          }

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6.0),
                            child: SizedBox(
                              width:
                                  double.infinity, // 👈 same width as quiz card
                              child: ElevatedButton(
                                onPressed: _answered
                                    ? _next
                                    : () => _chooseMcq(opt),
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                  backgroundColor: bg,
                                  foregroundColor: txt,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.max,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        opt,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: txt),
                                      ),
                                    ),
                                    if (icon != null) ...[
                                      const SizedBox(width: 10),
                                      Icon(icon, color: iconColor),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),

                        const SizedBox(height: 8),

                        // Next button
                        if (_answered)
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _next,
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size.fromHeight(44),
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.primary,
                              ),
                              child: Text(
                                'Ďalej',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimary,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
