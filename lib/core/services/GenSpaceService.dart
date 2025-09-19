import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/firebase_service.dart';
import '../../features/upload/models/processing_job_model.dart';
import 'dart:async';

class GenSpaceService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  List<ProcessingJob> _jobs = [];
  bool _isLoading = false;
  String? _error;
  StreamSubscription? _jobsSubscription;

  List<ProcessingJob> get jobs => _jobs;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Get user jobs with real-time updates - integrates with queue system
  Future<void> getUserJobs() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final user = FirebaseService.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Cancel previous subscription if exists
      _jobsSubscription?.cancel();

      // Listen to real-time updates from Firebase
      _jobsSubscription = _firestore
          .collection('GenSpace_jobs')
          .where('userId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .listen((snapshot) {
        try {
          _jobs = snapshot.docs.map((doc) {
            final data = doc.data();
            // Ensure the ID is included
            data['id'] = doc.id;
            return ProcessingJob.fromJson(data);
          }).toList();

          _isLoading = false;
          _error = null;
          notifyListeners();
          
          if (kDebugMode) print('✅ Updated ${_jobs.length} jobs from Firebase');
        } catch (e) {
          if (kDebugMode) print('❌ Error processing job snapshot: $e');
          _error = e.toString();
          _isLoading = false;
          notifyListeners();
        }
      }, onError: (error) {
        if (kDebugMode) print('❌ Error listening to jobs: $error');
        _error = error.toString();
        _isLoading = false;
        notifyListeners();
      });

    } catch (e) {
      if (kDebugMode) print('❌ Error setting up jobs listener: $e');
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Force refresh jobs (fallback method)
  Future<void> refreshJobs() async {
    try {
      final user = FirebaseService.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final QuerySnapshot snapshot = await _firestore
          .collection('GenSpace_jobs')
          .where('userId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .get();

      _jobs = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return ProcessingJob.fromJson(data);
      }).toList();

      notifyListeners();
      if (kDebugMode) print('✅ Refreshed ${_jobs.length} jobs');
    } catch (e) {
      if (kDebugMode) print('❌ Error refreshing jobs: $e');
      throw e;
    }
  }

  Future<void> deleteJob(String jobId) async {
    try {
      await _firestore.collection('GenSpace_jobs').doc(jobId).delete();
      
      // Remove from local list
      _jobs.removeWhere((job) => job.id == jobId);
      notifyListeners();
    } catch (e) {
      print('Error deleting job: $e');
      throw e;
    }
  }



  // Listen to real-time updates for a specific job
  Stream<ProcessingJob?> getJobStream(String jobId) {
    return _firestore
        .collection('GenSpace_jobs')
        .doc(jobId)
        .snapshots()
        .map((snapshot) {
          if (!snapshot.exists) return null;
          final data = snapshot.data() as Map<String, dynamic>;
          data['id'] = snapshot.id;
          return ProcessingJob.fromJson(data);
        });
  }

  /// Cancel job subscription and dispose
  @override
  void dispose() {
    _jobsSubscription?.cancel();
    super.dispose();
  }
}