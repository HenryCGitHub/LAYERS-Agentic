import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/tier_document.dart';

class AiAccessRecord {
  final String email;
  final String status; // 'invited' | 'approved' | 'revoked'
  final String displayName;
  final String? inviteUrl;
  final int? invitedAtMs;
  final int? acceptedAtMs;
  final int? revokedAtMs;

  const AiAccessRecord({
    required this.email,
    required this.status,
    this.displayName = '',
    this.inviteUrl,
    this.invitedAtMs,
    this.acceptedAtMs,
    this.revokedAtMs,
  });

  factory AiAccessRecord.fromMap(String docId, Map<String, dynamic> data) {
    int? parseMs(dynamic raw) {
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      if (raw is Timestamp) return raw.millisecondsSinceEpoch;
      return null;
    }

    return AiAccessRecord(
      email: (data['email'] ?? docId).toString().trim().toLowerCase(),
      status: (data['status'] ?? 'invited').toString().trim().toLowerCase(),
      displayName: (data['displayName'] ?? '').toString().trim(),
      inviteUrl: data['inviteUrl']?.toString(),
      invitedAtMs: parseMs(data['invitedAt']),
      acceptedAtMs: parseMs(data['acceptedAt']),
      revokedAtMs: parseMs(data['revokedAt']),
    );
  }
}

class FirestoreVaultService {
  static final FirestoreVaultService _instance =
      FirestoreVaultService._internal();
  factory FirestoreVaultService() => _instance;
  FirestoreVaultService._internal();

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _docsSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _allAiAccessSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _myAiAccessSubscription;

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
          .listen(
        (snapshot) {
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
        },
        onError: (e) {
          debugPrint('Firestore real-time sync error: $e');
        },
      );
    } catch (e) {
      debugPrint('Firestore startRealtimeSync error: $e');
    }
  }

  void stopRealtimeSync() {
    _docsSubscription?.cancel();
    _docsSubscription = null;
    _allAiAccessSubscription?.cancel();
    _allAiAccessSubscription = null;
    _myAiAccessSubscription?.cancel();
    _myAiAccessSubscription = null;
  }

  /// Watches all `ai_access` records in real time (Admin only).
  void watchAllAiAccessEntries({
    required void Function(List<AiAccessRecord> entries) onEntries,
  }) {
    _allAiAccessSubscription?.cancel();
    try {
      _allAiAccessSubscription =
          _firestore.collection('ai_access').snapshots().listen(
        (snapshot) {
          final items = <AiAccessRecord>[
            for (final d in snapshot.docs)
              AiAccessRecord.fromMap(d.id, d.data()),
          ];
          items.sort(
            (a, b) => (b.invitedAtMs ?? 0).compareTo(a.invitedAtMs ?? 0),
          );
          onEntries(items);
        },
        onError: (e) {
          debugPrint('Firestore watchAllAiAccessEntries error: $e');
        },
      );
    } catch (e) {
      debugPrint('Firestore watchAllAiAccessEntries init error: $e');
    }
  }

  /// Watches the current user's own `ai_access/{email}` status in real time.
  void watchMyAiAccess({
    required String email,
    required void Function(String? status) onStatus,
  }) {
    _myAiAccessSubscription?.cancel();
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty) return;
    try {
      _myAiAccessSubscription = _firestore
          .collection('ai_access')
          .doc(cleanEmail)
          .snapshots()
          .listen(
        (snap) {
          if (!snap.exists || snap.data() == null) {
            onStatus(null);
            return;
          }
          onStatus(snap.data()!['status']?.toString().trim().toLowerCase());
        },
        onError: (e) {
          debugPrint('Firestore watchMyAiAccess error: $e');
        },
      );
    } catch (e) {
      debugPrint('Firestore watchMyAiAccess init error: $e');
    }
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
