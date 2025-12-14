import 'package:flutter/material.dart';
import 'package:flippy/theme/colors.dart';
import 'package:flippy/theme/fonts.dart';
import 'package:go_router/go_router.dart'; // <-- pridaj tento import
import 'package:flippy/features/lesson_or_quiz/lesson_or_quiz_screen.dart';

class BookScreen extends StatefulWidget {
  final Map<String, dynamic> book;

  const BookScreen({super.key, required this.book});

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  late final Map<String, dynamic> data;
  late List<bool> expanded;

  @override
  void initState() {
    super.initState();
    // Normalize incoming payload: callers may pass either the textbook map
    // directly or a wrapper like { 'textbook': <map> } (Home was changed to
    // send the textbook under that key). Accept both.
    final raw = widget.book;
    if (raw.containsKey('textbook') && raw['textbook'] is Map) {
      data = Map<String, dynamic>.from(raw['textbook'] as Map);
    } else {
      data = Map<String, dynamic>.from(raw);
    }

    // Safely obtain chapters list (may be null) and initialize expansion state
    final chaptersList = (data['chapters'] as List<dynamic>?) ?? <dynamic>[];
    expanded = List<bool>.filled(chaptersList.length, false);
  }

  @override
  Widget build(BuildContext context) {
    final chapters = (data['chapters'] as List<dynamic>?) ?? <dynamic>[];

    return Scaffold(
      // rovnaký gradient background ako na home_screen
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
          // názov knihy v appbare
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () =>
                  context.go('/'), // presmeruje na grid kníh (HomePage)
            ),
            title: Text(
              data["title"] ?? 'Chapters',
              style: AppTextStyles.chapter,
            ),
            foregroundColor: Theme.of(context).colorScheme.onSurface,
          ),
          body: ListView.builder(
            // builder pre jednotlivé kapitoly
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: chapters.length,
            itemBuilder: (context, index) {
              final chapter = chapters[index];
              final isOpen = expanded[index];

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isOpen ? Theme.of(context).colorScheme.primary : Colors.white,
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
                  children: [
                    // CHAPTER HEADER (unit)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() {
                        // if this chapter is already open, close it
                        if (expanded[index]) {
                          expanded[index] = false;
                        } else {
                          // close all chapters, then open the tapped one
                          for (var i = 0; i < expanded.length; i++) {
                            expanded[i] = false;
                          }
                          expanded[index] = true;
                        }
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            /*Text(
                              chapter["id"].toString(),
                              style: TextStyle(
                                color: isOpen ? Colors.white : AppColors.text,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(width: 12),*/
                            Expanded(
                              child: Text(
                                chapter["title"] ?? '',
                                style: TextStyle(
                                  color: isOpen ? Colors.white : Theme.of(context).colorScheme.onSurface,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            Icon(
                              isOpen
                                  ? Icons.keyboard_arrow_down
                                  : Icons.keyboard_arrow_right,
                              color: isOpen ? Colors.white : Theme.of(context).colorScheme.onSurface,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // SUBCHAPTERS (lessons)
                    if (isOpen)
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors
                              .background, // subtle surface color from theme
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(12),
                          ),
                        ),
                        child: Column(
                          children: [
                            for (var sub
                                in (chapter["subchapters"] as List<dynamic>))
                              InkWell(
                                onTap: () {
                                  // open intermediary screen where user chooses
                                  // between Slovíčka (LessonScreen) and Test (QuizScreen)
                                  Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) =>
                                        // import lazily to avoid import cycles
                                        // pass same payload as before
                                        LessonOrQuizScreen(
                                      args: {
                                        'textbook': data,
                                        'chapterId': chapter['id'],
                                        'chapterTitle': chapter['title'],
                                        'subchapterId': sub['id'],
                                        'subchapterTitle': sub['title'],
                                        'words': sub['words'],
                                      },
                                    ),
                                  ));
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 14,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          sub["title"] ?? '',
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
