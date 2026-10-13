import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rume/utils/booking_helpers.dart';

class ViewFeedbackDialog extends StatefulWidget {
  final String feedbackId;
  final String bookingId; 
  final double rating;
  final String description;
  final String status;

  const ViewFeedbackDialog({
    super.key,
    required this.feedbackId,
    required this.bookingId,
    required this.rating,
    required this.description,
    required this.status,
  });

  @override
  State<ViewFeedbackDialog> createState() => _ViewFeedbackDialogState();
}

class _ViewFeedbackDialogState extends State<ViewFeedbackDialog> {
  bool _isDeleting = false;

  String _getFeedbackStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Pending Review';
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      default:
        return status;
    }
  }

  Future<void> _deleteFeedback() async {
    final confirm = await BookingHelpers.showConfirmDialog(
      context: context,
      title: 'Delete Feedback',
      content:
          'Are you sure you want to delete your feedback? This action cannot be undone.',
      confirmText: 'Delete',
      confirmColor: Colors.red,
    );

    if (confirm != true || !mounted) return;

    setState(() => _isDeleting = true);

    try {
      await FirebaseFirestore.instance
          .collection('feedbacks')
          .doc(widget.feedbackId)
          .delete();
      if (mounted) {
        Navigator.of(context).pop(true); 
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Feedback deleted successfully.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete feedback: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }

  Widget _buildStarRating(double rating, {double size = 24}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return Icon(
          index < rating ? Icons.star : Icons.star_border,
          color: Colors.amber,
          size: size,
        );
      }),
    );
  }
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Your Feedback'),
      content: SingleChildScrollView(
        child: ListBody(
          children: <Widget>[
            _buildStarRating(widget.rating),
            const SizedBox(height: 16),
            Text(widget.description),
            const SizedBox(height: 16),
            Text('Status: ${_getFeedbackStatusText(widget.status)}',
                style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        ElevatedButton.icon(
          onPressed: _isDeleting ? null : _deleteFeedback,
          icon: _isDeleting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.delete_outline),
          label: const Text('Delete'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.red.withOpacity(0.5),
          ),
        ),
      ],
    );
  }
}