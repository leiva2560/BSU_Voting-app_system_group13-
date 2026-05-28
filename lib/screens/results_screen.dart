import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import '../widgets/candidate_photo.dart';

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key, required this.currentUser});
  final User? currentUser;

  // Palette for bar chart bars
  static const _barColors = [
    Color(0xFF2196F3), Color(0xFF4CAF50), Color(0xFFFF9800),
    Color(0xFF9C27B0), Color(0xFFF44336), Color(0xFF00BCD4),
    Color(0xFF795548), Color(0xFF607D8B),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Election Results'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser?.uid)
            .get(),
        builder: (context, userSnap) {
          final isAdmin = userSnap.hasData &&
              userSnap.data?.get('role') == 'admin';
          final userName = userSnap.hasData && userSnap.data!.exists
              ? (userSnap.data!.data() as Map<String, dynamic>)['name'] ?? 'Student'
              : 'Student';

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('elections')
                .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final elections = snap.data!.docs;
              if (elections.isEmpty) {
                return const Center(child: Text('No elections found.'));
              }

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Header
                  Row(children: [
                    CircleAvatar(
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      child: Text(
                        userName.isNotEmpty
                            ? userName[0].toUpperCase()
                            : 'S',
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hello, $userName',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16)),
                        if (isAdmin)
                          const Text('Live admin view',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.green)),
                      ],
                    ),
                  ]),
                  const SizedBox(height: 20),

                  ...elections.map((electionDoc) {
                    final data =
                        electionDoc.data() as Map<String, dynamic>;
                    final endsAt =
                        (data['endsAt'] as Timestamp).toDate();
                    final isCompleted =
                        DateTime.now().isAfter(endsAt);
                    final showResults = isCompleted || isAdmin;

                    return _ElectionResultCard(
                      electionId: electionDoc.id,
                      electionData: data,
                      showResults: showResults,
                      barColors: _barColors,
                    );
                  }),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ── Election result card ─────────────────────────────────────────────────────
class _ElectionResultCard extends StatefulWidget {
  const _ElectionResultCard({
    required this.electionId,
    required this.electionData,
    required this.showResults,
    required this.barColors,
  });
  final String electionId;
  final Map<String, dynamic> electionData;
  final bool showResults;
  final List<Color> barColors;

  @override
  State<_ElectionResultCard> createState() => _ElectionResultCardState();
}

class _ElectionResultCardState extends State<_ElectionResultCard> {
  bool _showChart = true;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      elevation: 2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Election header
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              Expanded(
                child: Text(
                  widget.electionData['title'] ?? 'Untitled',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: colorScheme.onPrimaryContainer),
                ),
              ),
              if (widget.showResults)
                IconButton(
                  icon: Icon(
                      _showChart ? Icons.bar_chart : Icons.list_alt,
                      color: colorScheme.primary),
                  tooltip: _showChart ? 'Show list' : 'Show chart',
                  onPressed: () =>
                      setState(() => _showChart = !_showChart),
                ),
            ]),
          ),

          if (!widget.showResults)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Row(children: [
                Icon(Icons.lock_clock, color: Colors.orange),
                SizedBox(width: 10),
                Text('Results available after polls close.',
                    style: TextStyle(color: Colors.orange)),
              ]),
            )
          else
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('elections')
                  .doc(widget.electionId)
                  .collection('candidates')
                  .snapshots(),
              builder: (context, candSnap) {
                if (!candSnap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final candidates = candSnap.data!.docs;
                if (candidates.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No candidates yet.',
                        style: TextStyle(color: Colors.grey)),
                  );
                }

                // Group by position
                final Map<String, List<QueryDocumentSnapshot>> byPos = {};
                for (final c in candidates) {
                  final cd = c.data() as Map<String, dynamic>;
                  byPos
                      .putIfAbsent(cd['position'] ?? 'Unknown', () => [])
                      .add(c);
                }

                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: byPos.entries.map((entry) {
                      final pos = entry.key;
                      final list = entry.value;
                      final total = list.fold<int>(0, (s, c) {
                        final cd = c.data() as Map<String, dynamic>;
                        return s + ((cd['votes'] as int?) ?? 0);
                      });

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Position label
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(pos,
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color:
                                        colorScheme.onSecondaryContainer)),
                          ),

                          if (_showChart)
                            _BarChartWidget(
                              candidates: list,
                              totalVotes: total,
                              barColors: widget.barColors,
                            )
                          else
                            _ListResultWidget(
                              candidates: list,
                              totalVotes: total,
                              barColors: widget.barColors,
                            ),

                          const SizedBox(height: 8),
                          Text('Total votes: $total',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                          const Divider(height: 24),
                        ],
                      );
                    }).toList(),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ── Bar chart widget ─────────────────────────────────────────────────────────
class _BarChartWidget extends StatelessWidget {
  const _BarChartWidget({
    required this.candidates,
    required this.totalVotes,
    required this.barColors,
  });
  final List<QueryDocumentSnapshot> candidates;
  final int totalVotes;
  final List<Color> barColors;

  @override
  Widget build(BuildContext context) {
    final maxVotes = candidates.fold<int>(0, (m, c) {
      final cd = c.data() as Map<String, dynamic>;
      final v = (cd['votes'] as int?) ?? 0;
      return v > m ? v : m;
    });

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          maxY: (maxVotes + 1).toDouble(),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final cd = candidates[groupIndex].data()
                    as Map<String, dynamic>;
                final votes = (cd['votes'] as int?) ?? 0;
                final pct = totalVotes > 0
                    ? (votes / totalVotes * 100).toStringAsFixed(1)
                    : '0.0';
                return BarTooltipItem(
                  '${cd['name']}\n$votes votes ($pct%)',
                  const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                getTitlesWidget: (v, _) => Text(
                  v.toInt().toString(),
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (value, _) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= candidates.length) {
                    return const SizedBox.shrink();
                  }
                  final cd = candidates[idx].data()
                      as Map<String, dynamic>;
                  final name = (cd['name'] as String? ?? '');
                  final short = name.length > 8
                      ? '${name.substring(0, 7)}…'
                      : name;
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(short,
                        style: const TextStyle(fontSize: 10),
                        textAlign: TextAlign.center),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: Colors.grey[200]!, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(candidates.length, (i) {
            final cd =
                candidates[i].data() as Map<String, dynamic>;
            final votes = (cd['votes'] as int?) ?? 0;
            final color = barColors[i % barColors.length];
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: votes.toDouble(),
                  color: color,
                  width: 28,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6)),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

// ── List result widget ───────────────────────────────────────────────────────
class _ListResultWidget extends StatelessWidget {
  const _ListResultWidget({
    required this.candidates,
    required this.totalVotes,
    required this.barColors,
  });
  final List<QueryDocumentSnapshot> candidates;
  final int totalVotes;
  final List<Color> barColors;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(candidates.length, (i) {
        final cd = candidates[i].data() as Map<String, dynamic>;
        final votes = (cd['votes'] as int?) ?? 0;
        final pct = totalVotes > 0 ? votes / totalVotes : 0.0;
        final color = barColors[i % barColors.length];

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              CandidatePhotoWidget(candidateData: cd, radius: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(cd['name'] ?? '',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w500)),
                        ),
                        Text(
                          '$votes  (${(pct * 100).toStringAsFixed(1)}%)',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: color,
                              fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 8,
                        backgroundColor: Colors.grey[200],
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
