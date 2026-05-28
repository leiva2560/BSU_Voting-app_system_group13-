import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
class AdminPanelScreen extends StatelessWidget {
  const AdminPanelScreen({super.key, required this.currentUser});
  final firebase_auth.User currentUser;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Admin Panel')), body: const Center(child: Text('Admin panel coming in folder 7.')));
}
