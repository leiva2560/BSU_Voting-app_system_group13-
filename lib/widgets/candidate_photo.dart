import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Displays a candidate photo from:
/// 1. `photoBase64` — base64-encoded bytes stored directly in Firestore (new)
/// 2. `photoPath`   — Firebase Storage path (legacy)
/// 3. `photoUrl`    — direct download URL (legacy)
class CandidatePhotoWidget extends StatelessWidget {
  const CandidatePhotoWidget({
    super.key,
    required this.candidateData,
    this.radius = 24,
  });

  final Map<String, dynamic> candidateData;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final base64Str = candidateData['photoBase64'] as String?;
    final path = candidateData['photoPath'] as String?;
    final url = candidateData['photoUrl'] as String?;

    // 1. Base64 bytes in Firestore
    if (base64Str != null && base64Str.isNotEmpty) {
      try {
        final Uint8List bytes = base64Decode(base64Str);
        return CircleAvatar(
          radius: radius,
          backgroundImage: MemoryImage(bytes),
        );
      } catch (_) {}
    }

    // 2. Firebase Storage path
    if (path != null && path.isNotEmpty) {
      return FutureBuilder<String>(
        future: FirebaseStorage.instanceFor(
                bucket: 'gs://bsuvotingapp.firebasestorage.app')
            .ref()
            .child(path)
            .getDownloadURL(),
        builder: (context, snap) {
          if (snap.hasData) {
            return CircleAvatar(
              radius: radius,
              backgroundImage: NetworkImage(snap.data!),
            );
          }
          return CircleAvatar(
            radius: radius,
            backgroundColor: Colors.grey[200],
            child: snap.hasError
                ? Icon(Icons.broken_image,
                    size: radius * 0.7, color: Colors.grey)
                : SizedBox(
                    width: radius * 0.7,
                    height: radius * 0.7,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
          );
        },
      );
    }

    // 3. Direct URL
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(url),
        onBackgroundImageError: (_, __) {},
      );
    }

    // Fallback
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.grey[200],
      child: Icon(Icons.person, size: radius * 0.8, color: Colors.grey),
    );
  }
}
