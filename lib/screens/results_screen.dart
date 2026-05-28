import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key, required this.currentUser});
  final User? currentUser;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Results')), body: const Center(child: Text('Results coming in folder 6.')));
}
