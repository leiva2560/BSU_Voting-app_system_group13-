import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/candidate_photo.dart';

class VoteScreen extends StatefulWidget {
  const VoteScreen({
    super.key,
    required this.currentUser,
    required this.electionId,
    required this.electionData,
  });

  final User? currentUser;
  final String electionId;
  final Map<String, dynamic> electionData;

  @override
  State<VoteScreen> createState() => _VoteScreenState();
}

class _VoteScreenState extends State<VoteScreen> {
  final Map<String, String> _selectedCandidates = {};
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Secure Vote'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('elections')
            .doc(widget.electionId)
            .collection('candidates')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final candidates = snapshot.data!.docs;
          final positions = widget.electionData['positions'] as List? ?? [];
          
          // Group candidates by position
          final Map<String, List<QueryDocumentSnapshot>> candidatesByPosition = {};
          for (final candidate in candidates) {
            final candidateData = candidate.data() as Map<String, dynamic>;
            final position = candidateData['position'] ?? 'Unknown';
            candidatesByPosition.putIfAbsent(position, () => []).add(candidate);
          }

          // Check if user has already voted
          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance
                .collection('elections')
                .doc(widget.electionId)
                .collection('votes')
                .doc(widget.currentUser?.uid)
                .get(),
            builder: (context, voteSnapshot) {
              final alreadyVoted = voteSnapshot.hasData && voteSnapshot.data!.exists;

              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.electionData['title'] ?? 'Election',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text('Select one candidate per position category.'),
                    const SizedBox(height: 20),
                    
                    if (alreadyVoted)
                      const Text(
                        'You have already cast your vote for this election.',
                        style: TextStyle(color: Colors.green),
                      ),
                    
                    if (!alreadyVoted)
                      Expanded(
                        child: ListView(
                          children: positions.map((position) {
                            final positionCandidates = candidatesByPosition[position] ?? [];
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  position,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 8),
                                ...positionCandidates.map((candidateDoc) {
                                  final candidateData = candidateDoc.data() as Map<String, dynamic>;
                                  final candidateId = candidateDoc.id;

                                  return RadioListTile<String>(
                                    value: candidateId,
                                    groupValue: _selectedCandidates[position],
                                    onChanged: (value) {
                                      setState(() {
                                        _selectedCandidates[position] = value!;
                                      });
                                    },
                                    title: Text(candidateData['name'] ?? 'Unknown'),
                                    subtitle: Text(candidateData['bio'] ?? 'No bio'),
                                    secondary: CandidatePhotoWidget(
                                      candidateData: candidateData,
                                      radius: 20,
                                    ),
                                  );
                                }),
                                const Divider(),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: alreadyVoted || _isSubmitting
                          ? null
                          : () async {
                              if (_selectedCandidates.length != positions.length) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Please vote for every position.')),
                                );
                                return;
                              }
                              
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (dialogContext) {
                                  return AlertDialog(
                                    title: const Text('Confirm Vote'),
                                    content: const Text(
                                      'Submit your ballot. This vote is recorded securely and cannot be changed.'
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(dialogContext).pop(false),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () => Navigator.of(dialogContext).pop(true),
                                        child: const Text('Confirm'),
                                      ),
                                    ],
                                  );
                                },
                              );
                              
                              if (confirmed != true) return;
                              if (!mounted) return;
                              
                              await _submitVote();
                            },
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Submit Vote'),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _submitVote() async {
    setState(() {
      _isSubmitting = true;
    });

    try {
      final batch = FirebaseFirestore.instance.batch();
      
      // Create vote document
      final voteRef = FirebaseFirestore.instance
          .collection('elections')
          .doc(widget.electionId)
          .collection('votes')
          .doc(widget.currentUser!.uid);
      
      batch.set(voteRef, {
        'userId': widget.currentUser!.uid,
        'selections': _selectedCandidates,
        'votedAt': FieldValue.serverTimestamp(),
      });

      // Increment vote counts for each selected candidate
      for (final candidateId in _selectedCandidates.values) {
        final candidateRef = FirebaseFirestore.instance
            .collection('elections')
            .doc(widget.electionId)
            .collection('candidates')
            .doc(candidateId);
        
        batch.update(candidateRef, {
          'votes': FieldValue.increment(1),
        });
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your vote has been recorded.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting vote: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }
}