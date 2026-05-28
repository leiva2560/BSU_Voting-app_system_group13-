import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class CandidateDetailScreen extends StatelessWidget {
  const CandidateDetailScreen({
    super.key,
    required this.candidateId,
    required this.candidateData,
    required this.electionId,
    required this.electionData,
  });

  final String candidateId;
  final Map<String, dynamic> candidateData;
  final String electionId;
  final Map<String, dynamic> electionData;

  @override
  Widget build(BuildContext context) {
    final photoUrl = candidateData['photoUrl'] ?? '';
    
    // Determine image provider based on platform and URL type
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
        imageProvider = const NetworkImage('https://picsum.photos/200/200?grayscale');
      }
    } else if (photoUrl.isNotEmpty) {
      imageProvider = NetworkImage(photoUrl);
    } else {
      imageProvider = const NetworkImage('https://picsum.photos/200/200?grayscale');
    }
    
    return Scaffold(
      appBar: AppBar(
        title: Text(candidateData['name'] ?? 'Candidate Details'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Profile Image
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image(
                image: imageProvider,
                height: 220,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 220,
                    color: Colors.grey[200],
                    child: const Center(
                      child: Icon(Icons.person, size: 80, color: Colors.grey),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            
            // Position
            Text(
              candidateData['position'] ?? 'No position',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.blue),
            ),
            const SizedBox(height: 8),
            
            // Bio/About
            const Text(
              'About',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              candidateData['bio'] ?? 'No bio available',
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 24),
            
            // Election Information Card
            Card(
              color: Colors.grey[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Election Information',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('Election: ${electionData['title'] ?? 'Unknown'}'),
                    const SizedBox(height: 4),
                    Text('Position: ${candidateData['position'] ?? 'Unknown'}'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}