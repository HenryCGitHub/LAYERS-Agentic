import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/tier_document.dart';

class FirestoreVaultService {
  static final FirestoreVaultService _instance =
      FirestoreVaultService._internal();
  factory FirestoreVaultService() => _instance;
  FirestoreVaultService._internal();

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  StreamSubscription? _docsSubscription;

  /// Starts listening to real-time Firestore changes for the logged-in user.
  void startRealtimeSync({
    required String uid,
    required void Function(Map<String, TierDocument> remoteDocs) onSync,
  }) {
    _docsSubscription?.cancel();
    try {
      _docsSubscription = _firestore
          .collection('users')
          .doc(uid)
          .collection('documents')
          .snapshots()
          .listen((snapshot) {
      final docsMap = <String, TierDocument>{};
      for (final docSnap in snapshot.docs) {
        try {
          final data = docSnap.data();
          final doc = TierDocument.fromJson(data);
          docsMap[doc.id] = doc;
        } catch (e) {
          debugPrint('Error parsing Firestore document ${docSnap.id}: $e');
        }
      }
      onSync(docsMap);
    }, onError: (e) {
      debugPrint('Firestore real-time sync error: $e');
    });
    } catch (e) {
      debugPrint('Firestore startRealtimeSync error: $e');
    }
  }

  void stopRealtimeSync() {
    _docsSubscription?.cancel();
    _docsSubscription = null;
  }

  /// Saves or updates a document in Firestore.
  Future<void> saveDocument({
    required String uid,
    required TierDocument doc,
  }) async {
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('documents')
          .doc(doc.id)
          .set(doc.toJson());
    } catch (e) {
      debugPrint('Firestore saveDocument error: $e');
    }
  }

  /// Deletes a document from Firestore.
  Future<void> deleteDocument({
    required String uid,
    required String docId,
  }) async {
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('documents')
          .doc(docId)
          .delete();
    } catch (e) {
      debugPrint('Firestore deleteDocument error: $e');
    }
  }

  /// Saves settings (activeDocumentId, etc.) in Firestore.
  Future<void> saveSettings({
    required String uid,
    required Map<String, dynamic> settings,
  }) async {
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .set(settings, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firestore saveSettings error: $e');
    }
  }

  /// Fetches saved user settings (`activeDocumentId`, `themeMode`) from Firestore.
  Future<Map<String, dynamic>?> fetchUserSettings({required String uid}) async {
    try {
      final snap = await _firestore.collection('users').doc(uid).get();
      return snap.data();
    } catch (e) {
      debugPrint('Firestore fetchUserSettings error: $e');
      return null;
    }
  }

  /// Shares a project with a collaborator via email.
  Future<bool> inviteCollaborator({
    required String projectId,
    required String projectTitle,
    required String ownerEmail,
    required String collaboratorEmail,
    required String role, // 'editor' or 'viewer'
  }) async {
    try {
      final cleanEmail = collaboratorEmail.trim().toLowerCase();
      if (cleanEmail.isEmpty) return false;
      await _firestore
          .collection('collaborations')
          .doc('${projectId}_$cleanEmail')
          .set({
        'projectId': projectId,
        'projectTitle': projectTitle,
        'ownerEmail': ownerEmail,
        'collaboratorEmail': cleanEmail,
        'role': role,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('Firestore inviteCollaborator error: $e');
      return false;
    }
  }

  /// Lists collaborators invited to a given project.
  Future<List<Map<String, String>>> listCollaborators({
    required String projectId,
  }) async {
    try {
      final snap = await _firestore
          .collection('collaborations')
          .where('projectId', isEqualTo: projectId)
          .get();
      return [
        for (final doc in snap.docs)
          {
            'email': (doc.data()['collaboratorEmail'] ?? '').toString(),
            'role': (doc.data()['role'] ?? 'editor').toString(),
          },
      ];
    } catch (e) {
      debugPrint('Firestore listCollaborators error: $e');
      return const [];
    }
  }
}
