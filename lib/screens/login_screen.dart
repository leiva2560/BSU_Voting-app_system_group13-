import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'registration_screen.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _registrationController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _errorText;
  bool _isLoading = false;
  bool _obscurePassword = true;

  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void dispose() {
    _registrationController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    final registrationNumber = _registrationController.text.trim();
    final password = _passwordController.text;
    setState(() { _isLoading = true; _errorText = null; });
    try {
      final userQuery = await _firestore.collection('users')
          .where('registrationNumber', isEqualTo: registrationNumber).limit(1).get();
      if (userQuery.docs.isEmpty) {
        if (mounted) setState(() { _errorText = 'Registration number not found.'; _isLoading = false; });
        return;
      }
      final userEmail = userQuery.docs.first['email'] as String;
      await _auth.signInWithEmailAndPassword(email: userEmail, password: password);
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Login successful!'), backgroundColor: Colors.green));
      }
    } on firebase_auth.FirebaseAuthException catch (e) {
      if (mounted) setState(() { _isLoading = false; _errorText = 'Login failed: ${e.message}'; });
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _errorText = 'Error: ${e.toString()}'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Column(children: [
              Container(padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
                child: Image.asset('assets/images/bsu_logo.png', width: 72, height: 72)),
              const SizedBox(height: 20),
              Text('Campus Voting', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: cs.primary)),
              const SizedBox(height: 6),
              Text('Sign in to your account', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
            ])),
            const SizedBox(height: 36),
            Card(elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(padding: const EdgeInsets.all(24),
                child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  TextFormField(controller: _registrationController,
                    decoration: InputDecoration(labelText: 'Registration Number', hintText: 'e.g. 24/BSU/BCS/001',
                      prefixIcon: const Icon(Icons.badge_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), errorText: _errorText),
                    onChanged: (_) { if (_errorText != null) setState(() => _errorText = null); },
                    validator: (v) { if (v == null || v.trim().isEmpty) return 'Enter your registration number';
                      final upper = v.trim().toUpperCase();
                      if (upper.startsWith('ADMIN')) return null;
                      if (!RegExp(r'^.+/BSU/.+/.+$', caseSensitive: false).hasMatch(v.trim()))
                        return 'Format: ../BSU/../..';
                      return null; }),
                  const SizedBox(height: 16),
                  TextFormField(controller: _passwordController, obscureText: _obscurePassword,
                    decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      suffixIcon: IconButton(icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword))),
                    validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _isLoading ? null : _handleLogin,
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    child: _isLoading ? const SizedBox(height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Login', style: TextStyle(fontSize: 16))),
                ])))),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text("Don't have an account?", style: TextStyle(color: Colors.grey[600])),
              TextButton(onPressed: _isLoading ? null : () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RegistrationScreen())),
                child: const Text('Register')),
            ]),
          ])))));
  }
}
