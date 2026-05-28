import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ElectionDetailScreen extends StatelessWidget {
  const ElectionDetailScreen({super.key, required this.currentUser, required this.electionId, required this.electionData});
  final User? currentUser;
  final String electionId;
  final Map<String, dynamic> electionData;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(electionData['title'] ?? 'Election')),
      body: const Center(child: Text('Election detail coming in next folder.')),
    );
  }
}
