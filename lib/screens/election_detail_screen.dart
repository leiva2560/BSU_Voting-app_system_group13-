import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'candidate_detail_screen.dart';
import 'vote_screen.dart';

class ElectionDetailScreen extends StatelessWidget {
  const ElectionDetailScreen({
    super.key,
    required this.currentUser,
    required this.electionId,
    required this.electionData,
  });

  final User? currentUser;
  final String electionId;
  final Map<String, dynamic> electionData;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: Text(electionData['title'] ?? 'Election Details')),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('elections')
            .doc(electionId)
            .snapshots(),
        builder: (context, electionSnapshot) {
          if (!electionSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final currentElectionData = electionSnapshot.data!.data() as Map<String, dynamic>;
          final currentStartsAt = (currentElectionData['startsAt'] as Timestamp).toDate();
          final currentEndsAt = (currentElectionData['endsAt'] as Timestamp).toDate();
          final currentIsActive = now.isAfter(currentStartsAt) && now.isBefore(currentEndsAt);
          final currentIsCompleted = now.isAfter(currentEndsAt);

          // Check if user has already voted
          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance
                .collection('elections')
                .doc(electionId)
                .collection('votes')
                .doc(currentUser?.uid)
                .get(),
            builder: (context, voteSnapshot) {
              final alreadyVoted = voteSnapshot.hasData && voteSnapshot.data!.exists;

              // Check if user is admin
              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .doc(currentUser?.uid)
                    .get(),
                builder: (context, userSnapshot) {
                  final isAdmin = userSnapshot.hasData && userSnapshot.data?.get('role') == 'admin';
                  final accessLiveResults = currentIsCompleted || isAdmin;

                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('elections')
                        .doc(electionId)
                        .collection('candidates')
                        .snapshots(),
                    builder: (context, candidatesSnapshot) {
                      if (!candidatesSnapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final candidates = candidatesSnapshot.data!.docs;
                      
                      // Group candidates by position
                      final Map<String, List<QueryDocumentSnapshot>> candidatesByPosition = {};
                      for (final candidate in candidates) {
                        final candidateData = candidate.data() as Map<String, dynamic>;
                        final position = candidateData['position'] ?? 'Unknown';
                        candidatesByPosition.putIfAbsent(position, () => []).add(candidate);
                      }

                      return ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Text(currentElectionData['description'] ?? 'No description', 
                              style: const TextStyle(fontSize: 16)),
                          const SizedBox(height: 12),
                          Text('Start: $currentStartsAt', style: const TextStyle(fontSize: 14)),
                          Text('End: $currentEndsAt', style: const TextStyle(fontSize: 14)),
                          const SizedBox(height: 24),
                          
                          if (alreadyVoted)
                            Card(
                              color: Colors.green[50],
                              child: ListTile(
                                leading: const Icon(Icons.check_circle, color: Colors.green),
                                title: const Text('Vote received'),
                                subtitle: const Text('You already submitted your ballot for this election.'),
                              ),
                            ),
                          
                          if (currentIsActive && !alreadyVoted)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.how_to_vote),
                                label: const Text('Vote Now'),
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => VoteScreen(
                                        currentUser: currentUser,
                                        electionId: electionId,
                                        electionData: currentElectionData,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          
                          const SizedBox(height: 16),
                          const Text('Candidates', 
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          
                          ...candidatesByPosition.entries.expand(
                            (entry) {
                              final position = entry.key;
                              final candidatesList = entry.value;
                              return [
                                Text(position, 
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 8),
                                ...candidatesList.map((candidateDoc) {
                                  final candidateData = candidateDoc.data() as Map<String, dynamic>;
                                  final candidateId = candidateDoc.id;
                                  final photoUrl = candidateData['photoUrl'] ?? '';
                                  
                                  ImageProvider imageProvider;
                                  if (!kIsWeb && photoUrl.startsWith('/')) {
                                    try {
                                      final f = File(photoUrl);
                                      if (f.existsSync()) {
                                        imageProvider = FileImage(f);
                                      } else {
                                        imageProvider = NetworkImage(photoUrl);
                                      }
                                    } catch (_) {
                                      imageProvider = const NetworkImage(
                                        'https://picsum.photos/200/200?grayscale');
                                    }
                                  } else if (photoUrl.isNotEmpty) {
                                    imageProvider = NetworkImage(photoUrl);
                                  } else {
                                    imageProvider = const NetworkImage(
                                      'https://picsum.photos/200/200?grayscale');
                                  }

                                  return Card(
                                    child: ListTile(
                                      leading: CircleAvatar(backgroundImage: imageProvider),
                                      title: Text(candidateData['name'] ?? 'Unknown'),
                                      subtitle: Text(candidateData['bio'] ?? 'No bio available'),
                                      trailing: accessLiveResults
                                          ? Text('${candidateData['votes'] ?? 0} votes', 
                                              style: const TextStyle(fontWeight: FontWeight.bold))
                                          : const Icon(Icons.arrow_forward_ios, size: 18),
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => CandidateDetailScreen(
                                              candidateId: candidateId,
                                              candidateData: candidateData,
                                              electionId: electionId,
                                              electionData: currentElectionData,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                }),
                                const SizedBox(height: 16),
                              ];
                            },
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}