import 'package:flutter/material.dart';

import 'package:flippy/features/lessons/lesson_screen.dart';
import 'package:flippy/features/quiz/quiz_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flippy/theme/colors.dart';
import 'package:flippy/theme/fonts.dart';

class LessonOrQuizScreen extends StatefulWidget {
  final Map<String, dynamic>? args;
  const LessonOrQuizScreen({super.key, this.args});

  @override
  State<LessonOrQuizScreen> createState() => _LessonOrQuizScreenState();
}

class _LessonOrQuizScreenState extends State<LessonOrQuizScreen> {
  late final Map<String, dynamic> _args;
  bool _canTest = false;
  // expansion state for items
  bool _expandedSlovicka = false;
  bool _expandedGrammar = false;
  bool _expandedMcq = false;

  // progress / score state
  int _visitedCount = 0;
  int _totalWords = 0;
  int _grammarScore = 0;
  int _mcqScore = 0;
  // whether full quiz run was completed
  bool _grammarDone = false;
  bool _mcqDone = false;
  // whether a quiz run was started but not finished (paused)
  bool _grammarPaused = false;
  bool _mcqPaused = false;

  @override
  void initState() {
    super.initState();
    _args = Map<String, dynamic>.from(widget.args ?? {});
    _computeCanTest();
    _loadProgress();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // recompute when returning to this screen
    _computeCanTest();
  }

  String _computeVisitedKey() {
    // Mirror LessonScreen logic: try to build signature from textbook map
    final routeArgs = _args;
    String? signature;
    final tb = routeArgs['textbook'] ?? routeArgs['book'] ?? routeArgs['textbookMap'];
    if (tb is Map) {
      final tbId = (tb['id'] ?? tb['textbookId'] ?? tb['bookId'] ?? '').toString();

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

      final wordIds = (routeArgs['words'] is List)
          ? (routeArgs['words'] as List).map((w) => (w is Map ? (w['id']?.toString() ?? '') : '')).where((s) => s.isNotEmpty).toList()
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
      final subId = (routeArgs['subchapterId'] ?? routeArgs['id'] ?? routeArgs['subId'] ?? routeArgs['sub'] ?? '').toString();
      final subTitle = (routeArgs['subchapterTitle'] ?? routeArgs['title'] ?? routeArgs['name'] ?? '').toString();

      final chapterId = (routeArgs['chapterId'] ?? routeArgs['parentId'] ?? routeArgs['chapterId'] ?? '').toString();
      final chapterTitle = (routeArgs['chapterTitle'] ?? routeArgs['chapter'] ?? '').toString();

      final bookId = (routeArgs['bookId'] ?? routeArgs['courseId'] ?? '').toString();
      final bookTitle = (routeArgs['bookTitle'] ?? routeArgs['book'] ?? '').toString();

      final parts = [bookId, bookTitle, chapterId, chapterTitle, subId, subTitle].map((s) => s.toString().trim()).where((s) => s.isNotEmpty).toList();
      final combinedKey = parts.isNotEmpty ? parts.join('::') : subTitle;
      keySource = combinedKey;
    }

    final keyId = keySource.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return 'visited_$keyId';
  }

  Future<void> _computeCanTest() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _computeVisitedKey();
      final list = prefs.getStringList(key) ?? <String>[];
      final visited = list.map(int.parse).toSet();

      final words = (_args['words'] is List) ? (_args['words'] as List) : <dynamic>[];
      final can = visited.length >= words.length && words.isNotEmpty;
      if (mounted) setState(() => _canTest = can);
    } catch (_) {
      if (mounted) setState(() => _canTest = false);
    }
  }

  Future<void> _loadProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final visitedKey = _computeVisitedKey();
      final list = prefs.getStringList(visitedKey) ?? <String>[];
      final visited = list.map(int.parse).toSet();

      final words = (_args['words'] is List) ? (_args['words'] as List) : <dynamic>[];

      // read persisted quiz scores/done flags using the same key base as QuizScreen
      final grammarBase = quizKeyFromArgs(_args, 'grammar');
      final mcqBase = quizKeyFromArgs(_args, 'mcq');

      final grammar = prefs.getInt('${grammarBase}_score') ?? 0;
      final grammarDone = prefs.getBool('${grammarBase}_done') ?? false;
      final grammarIndex = prefs.getInt('${grammarBase}_index') ?? 0;
      final mcq = prefs.getInt('${mcqBase}_score') ?? 0;
      final mcqDone = prefs.getBool('${mcqBase}_done') ?? false;
      final mcqIndex = prefs.getInt('${mcqBase}_index') ?? 0;

      if (!mounted) return;
      setState(() {
        _visitedCount = visited.length;
        // zobrazujeme počet zdrojových slov — to zodpovedá sekcii "Slovíčka"
        _totalWords = words.length;
        _grammarScore = grammar;
        _mcqScore = mcq;
        _grammarDone = grammarDone;
        _mcqDone = mcqDone;
        _grammarPaused = !grammarDone && grammarIndex > 0;
        _mcqPaused = !mcqDone && mcqIndex > 0;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final title = _args['subchapterTitle'] ?? _args['title'] ?? 'Vyberte';
    // Počet položiek, ktorý sa používa v teste: ak je menej zdrojových slov než quizSize, použije sa ich počet
    final int quizDisplayCount = _totalWords > 0 ? (_totalWords < quizSize ? _totalWords : quizSize) : 0;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Theme.of(context).colorScheme.secondary, Theme.of(context).colorScheme.surface],
            stops: const [0.0, 0.15],
          ),
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            title: Text(title, style: AppTextStyles.chapter),
            foregroundColor: Theme.of(context).colorScheme.onSurface,
          ),
          body: SafeArea(
            minimum: EdgeInsets.only(top:40),
            child: Center(
              child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: ListView(
                children: [
                  // Slovíčka (styled like chapters list item)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _expandedSlovicka ? Theme.of(context).colorScheme.primary : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0,4))],
                    ),
                    child: Column(
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() {
                            if (_expandedSlovicka) {
                              // already open -> close it
                              _expandedSlovicka = false;
                            } else {
                              // open this one and collapse others
                              _expandedSlovicka = true;
                              _expandedGrammar = false;
                              _expandedMcq = false;
                            }
                          }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text('Slovíčka', style: TextStyle(color: _expandedSlovicka ? Colors.white : AppColors.text, fontSize: 18)),
                                ),
                                Icon(_expandedSlovicka ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, color: _expandedSlovicka ? Colors.white : Theme.of(context).colorScheme.onSurface),
                              ],
                            ),
                          ),
                        ),

                        if (_expandedSlovicka)
                          Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                children: [
                                  Container(
                                    height: 160,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      border: Border.all(color: AppColors.text, width: 2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Stack(
                                      children: [
                                        Center(
                                          child: Icon(
                                            _visitedCount >= _totalWords && _totalWords > 0 ? Icons.star : Icons.star_border,
                                            size: 72,
                                            color: _visitedCount >= _totalWords && _totalWords > 0 ? Colors.yellow : Colors.grey,
                                          ),
                                        ),
                                        Positioned(
                                          top: 8,
                                          right: 8,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.white70,
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: AppColors.text.withValues(alpha: 0.2)),
                                            ),
                                            child: Text('$_visitedCount/$_totalWords', style: TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w600)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: ElevatedButton(
                                      onPressed: () {
                                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => LessonScreen(args: _args))).then((_) { _computeCanTest(); _loadProgress(); });
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Theme.of(context).colorScheme.primary,
                                        foregroundColor: Theme.of(context).colorScheme.onSurface,
                                      ),
                                      child: const Text('Spustiť'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Test - Gramatika (styled like chapters list item)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _expandedGrammar ? Theme.of(context).colorScheme.primary : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0,4))],
                    ),
                    child: Column(
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() {
                            if (_expandedGrammar) {
                              _expandedGrammar = false;
                            } else {
                              _expandedGrammar = true;
                              _expandedSlovicka = false;
                              _expandedMcq = false;
                            }
                          }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                Expanded(child: Text('Test - Gramatika', style: TextStyle(color: _expandedGrammar ? Colors.white : AppColors.text, fontSize: 18))),
                                Icon(_expandedGrammar ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, color: _expandedGrammar ? Colors.white : Theme.of(context).colorScheme.onSurface),
                              ],
                            ),
                          ),
                        ),

                        if (_expandedGrammar)
                          Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Row(
                                children: [
                                  // left: score
                                  Expanded(
                                    child: Container(
                                      height: 120,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        border: Border.all(color: AppColors.text, width: 2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Text('Skóre', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                            const SizedBox(height: 8),
                                            Text('$_grammarScore/$quizDisplayCount', style: const TextStyle(fontSize: 20)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // right: stars + button
                                  Expanded(
                                    child: Column(
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: List.generate(3, (i) {
                                            final pct = quizDisplayCount > 0 ? (_grammarScore / quizDisplayCount) * 100.0 : 0.0;
                                            int filled = 0;
                                            if (pct == 0) {filled = 0;}
                                            else if (pct <= 33) {filled = 1;}
                                            else if (pct <= 66) {filled = 2;}
                                            else {filled = 3;}
                                            return Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                              child: Icon(Icons.star, color: i < filled ? Colors.yellow : Colors.grey, size: 28),
                                            );
                                          }),
                                        ),
                                        const SizedBox(height: 12),
                                        ElevatedButton(
                                          onPressed: _canTest
                                              ? () async {
                                                  final args = Map<String, dynamic>.from(_args);
                                                  args['testType'] = 'grammar';
                                                  final base = quizKeyFromArgs(_args, 'grammar');
                                                  // capture navigator before any async gap
                                                  final navigator = Navigator.of(context);

                                                  if (!_grammarPaused) {
                                                    // fresh run or 'Zopakovať' - clear previous run state
                                                    try {
                                                      final prefs = await SharedPreferences.getInstance();
                                                      await prefs.remove('${base}_index');
                                                      await prefs.remove('${base}_answered');
                                                      await prefs.remove('${base}_correct');
                                                      await prefs.remove('${base}_input');
                                                      await prefs.setInt('${base}_score', 0);
                                                      await prefs.setBool('${base}_done', false);
                                                    } catch (_) {}
                                                  }

                                                  if (!mounted) return;
                                                  await navigator.push(MaterialPageRoute(builder: (_) => QuizScreen(args: args)));
                                                  if (!mounted) return;
                                                  _loadProgress();
                                                }
                                              : null,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _canTest ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
                                            foregroundColor: _canTest ? Theme.of(context).colorScheme.onPrimary : AppColors.text,
                                          ),
                                          child: Text(
                                            _grammarDone ? 'Zopakovať' : (_grammarPaused ? 'Pokračovať' : 'Spustiť'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Test - MCQ (styled like chapters list item)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _expandedMcq ? Theme.of(context).colorScheme.primary : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0,4))],
                    ),
                    child: Column(
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() {
                            if (_expandedMcq) {
                              _expandedMcq = false;
                            } else {
                              _expandedMcq = true;
                              _expandedSlovicka = false;
                              _expandedGrammar = false;
                            }
                          }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                Expanded(child: Text('Test - výber odpovede', style: TextStyle(color: _expandedMcq ? Colors.white : AppColors.text, fontSize: 18))),
                                Icon(_expandedMcq ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, color: _expandedMcq ? Colors.white : Theme.of(context).colorScheme.onSurface),
                              ],
                            ),
                          ),
                        ),

                        if (_expandedMcq)
                          Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      height: 120,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        border: Border.all(color: AppColors.text, width: 2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Text('Skóre', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                            const SizedBox(height: 8),
                                            Text('$_mcqScore/$quizDisplayCount', style: const TextStyle(fontSize: 20)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: List.generate(3, (i) {
                                            final pct = quizDisplayCount > 0 ? (_mcqScore / quizDisplayCount) * 100.0 : 0.0;
                                            int filled = 0;
                                            if (pct == 0) {filled = 0;}
                                            else if (pct <= 33) {filled = 1;}
                                            else if (pct <= 66) {filled = 2;}
                                            else {filled = 3;}
                                            return Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                              child: Icon(Icons.star, color: i < filled ? Colors.yellow : Colors.grey, size: 28),
                                            );
                                          }),
                                        ),
                                        const SizedBox(height: 12),
                                        ElevatedButton(
                                          onPressed: _canTest
                                              ? () async {
                                                  final args = Map<String, dynamic>.from(_args);
                                                  args['testType'] = 'mcq';
                                                  final base = quizKeyFromArgs(_args, 'mcq');
                                                  // capture navigator before async work
                                                  final navigator = Navigator.of(context);

                                                  if (!_mcqPaused) {
                                                    try {
                                                      final prefs = await SharedPreferences.getInstance();
                                                      await prefs.remove('${base}_index');
                                                      await prefs.remove('${base}_answered');
                                                      await prefs.remove('${base}_correct');
                                                      await prefs.remove('${base}_input');
                                                      await prefs.setInt('${base}_score', 0);
                                                      await prefs.setBool('${base}_done', false);
                                                    } catch (_) {}
                                                  }

                                                  if (!mounted) return;
                                                  await navigator.push(MaterialPageRoute(builder: (_) => QuizScreen(args: args)));
                                                  if (!mounted) return;
                                                  _loadProgress();
                                                }
                                              : null,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _canTest ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
                                            foregroundColor: _canTest ? Theme.of(context).colorScheme.onPrimary : AppColors.text,
                                          ),
                                          child: Text(
                                            _mcqDone ? 'Zopakovať' : (_mcqPaused ? 'Pokračovať' : 'Spustiť'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          ),
        ),
      ),
    );
  }
}
