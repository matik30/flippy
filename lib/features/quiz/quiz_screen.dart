import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QuizScreen extends StatefulWidget {
  final Map<String, dynamic>? args;
  const QuizScreen({super.key, this.args});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  late final List<Map<String, dynamic>> _words;
  late final String _testType; // 'grammar' or 'mcq'
  int _index = 0;
  int _score = 0;
  bool _answered = false;
  bool _correct = false;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final Random _rnd = Random();

  List<String> _currentOptions = []; // for mcq

  @override
  void initState() {
    super.initState();
    final args = widget.args ?? {};
    final rawWords = args['words'] ?? args['wordList'] ?? <dynamic>[];
    if (rawWords is List) {
      _words = rawWords.map((e) => e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e)).cast<Map<String,dynamic>>().toList();
    } else {
      _words = <Map<String,dynamic>>[];
    }
    _testType = (args['testType'] ?? 'mcq') as String;
    if (_testType != 'grammar' && _testType != 'mcq') _testType = 'mcq';
    _loadProgress().then((_) {
      if (_words.isNotEmpty && _testType == 'mcq') _buildOptions();
    });
  }

  String _progressKeyBase() {
    final args = widget.args ?? {};
    final tb = args['textbook'] ?? args['book'] ?? args['textbookMap'];
    String part = '';
    if (tb is Map) {
      part = (tb['id'] ?? tb['textbookId'] ?? tb['bookId'] ?? '').toString();
    }
    final subId = (args['subchapterId'] ?? args['id'] ?? args['subId'] ?? args['sub'] ?? '').toString();
    final subTitle = (args['subchapterTitle'] ?? args['title'] ?? args['name'] ?? '').toString();
    final combined = [part, subId, subTitle].where((s) => s.isNotEmpty).join('::');
    final safe = combined.isEmpty ? 'default' : combined.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return 'quiz_${safe}_${_testType}';
  }

  Future<void> _saveProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final base = _progressKeyBase();
      await prefs.setInt('${base}_index', _index);
      await prefs.setInt('${base}_score', _score);
      await prefs.setBool('${base}_answered', _answered);
      if (_testType == 'grammar') await prefs.setString('${base}_input', _controller.text);
    } catch (_) {}
  }

  Future<void> _loadProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final base = _progressKeyBase();
      final idx = prefs.getInt('${base}_index');
      final sc = prefs.getInt('${base}_score');
      final ans = prefs.getBool('${base}_answered');
      final input = prefs.getString('${base}_input');
      if (!mounted) return;
      setState(() {
        if (idx != null && idx >= 0 && idx < _words.length) _index = idx;
        if (sc != null) _score = sc;
        if (ans != null) _answered = ans;
        if (_testType == 'grammar' && input != null) _controller.text = input;
      });
    } catch (_) {}
  }

  Future<void> _clearProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final base = _progressKeyBase();
      await prefs.remove('${base}_index');
      await prefs.remove('${base}_score');
      await prefs.remove('${base}_answered');
      await prefs.remove('${base}_input');
    } catch (_) {}
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String _normalize(String s) => s.trim().toLowerCase();

  String _correctAnswerFor(Map<String, dynamic> w) {
    final en = w['en'] ?? w['english'] ?? '';
    if (en is String) return en.trim();
    if (en is List && en.isNotEmpty) return en.first.toString().trim();
    return en.toString().trim();
  }

  void _buildOptions() {
    final w = _words[_index];
    final correct = _correctAnswerFor(w);
    final others = <String>[];
    for (var i = 0; i < _words.length; i++) {
      if (i == _index) continue;
      final o = _correctAnswerFor(_words[i]);
      if (o.isNotEmpty && o != correct) others.add(o);
    }
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
    final ok = _normalize(guess) == _normalize(correct);
    setState(() {
      _answered = true;
      _correct = ok;
      if (ok) _score++;
    });
    // hide keyboard
    _focusNode.unfocus();
    _saveProgress();
  }

  void _chooseMcq(String opt) {
    if (_answered) return;
    final correct = _correctAnswerFor(_words[_index]);
    final ok = _normalize(opt) == _normalize(correct);
    setState(() {
      _answered = true;
      _correct = ok;
      if (ok) _score++;
    });
    _saveProgress();
  }

  void _next() {
    if (_index + 1 >= _words.length) {
      // finished
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Výsledok'),
          content: Text('Skóre:  $_score/${_words.length}'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Zavrieť')),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
          ],
        ),
      ).then((_) async {
        // clear saved progress when user finishes
        await _clearProgress();
      });
      return;
    }
    setState(() {
      _index++;
      _answered = false;
      _correct = false;
      _controller.clear();
      if (_testType == 'mcq') _buildOptions();
    });
    // ensure keyboard focus for grammar
    if (_testType == 'grammar') FocusScope.of(context).requestFocus(_focusNode);
    _saveProgress();
  }

  @override
  Widget build(BuildContext context) {
    if (_words.isEmpty) {
      final title = widget.args?['subchapterTitle'] ?? widget.args?['title'] ?? 'Test';
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(child: Text('Žiadne slovíčka v tejto lekcii')),
      );
    }

    final word = _words[_index];
    final sk = (word['sk'] ?? word['cz'] ?? '').toString();
    final img = word['image'] ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.args?['subchapterTitle'] ?? widget.args?['title'] ?? 'Test'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 6,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (img != null && img.toString().isNotEmpty)
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: Image(
                              image: img.toString().startsWith('assets/') ? AssetImage(img.toString()) : NetworkImage(img.toString()) as ImageProvider,
                              height: 180,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      Text(sk.toUpperCase(), style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      if (_answered)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_correct ? Icons.check_circle : Icons.cancel, color: _correct ? Colors.green : Colors.red),
                            const SizedBox(width: 8),
                            Text(_correct ? 'Správne' : 'Nesprávne', style: TextStyle(color: _correct ? Colors.green : Colors.red)),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            if (_testType == 'grammar') ...[
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submitGrammar(),
                decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Napíšte anglický preklad'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _answered ? _next : _submitGrammar,
                      style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
                      child: Text(_answered ? 'Ďalej' : 'Odoslať', style: TextStyle(color: Theme.of(context).colorScheme.onPrimary)),
                    ),
                  ),
                ],
              ),
            ] else ...[
              // MCQ
              ..._currentOptions.map((opt) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: ElevatedButton(
                    onPressed: _answered ? (_next) : () => _chooseMcq(opt),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _answered
                          ? ( _correct && _normalize(opt) == _normalize(_correctAnswerFor(word)) ? Colors.green : Colors.grey.shade300)
                          : Theme.of(context).colorScheme.primary,
                    ),
                    child: Text(opt, style: TextStyle(color: _answered ? Colors.white : Theme.of(context).colorScheme.onPrimary)),
                  ),
                );
              }),
              const SizedBox(height: 8),
              if (_answered)
                ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
                  child: Text('Ďalej', style: TextStyle(color: Theme.of(context).colorScheme.onPrimary)),
                ),
            ],
            const SizedBox(height: 8),
            Text('$_score / ${_words.length}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
