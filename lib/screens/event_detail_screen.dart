import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import '../models/event.dart';
import '../models/event_category.dart';
import '../services/firestore_service.dart';
import 'live_navigation.dart';

class EventDetailScreen extends StatefulWidget {
  final Event event;

  const EventDetailScreen({super.key, required this.event});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  // ── Hype local state ──
  // Seeded from widget.event in initState. Updated instantly on tap so the
  // UI doesn't wait for Firestore to confirm before showing the new state.
  late bool _hasHyped;
  late int _hypeCount;

  // ── RSVP local state ──
  // _hasRsvpd starts as false and is updated by _loadRsvpStatus() which
  // runs an async Firestore read right after the screen opens.
  bool _hasRsvpd = false;
  late int _rsvpCount;

  // ── Save/Favorites local state ──
  bool _hasSaved = false;

  // ── Rating local state ──
  int _myRating = 0;          // 0 = no rating selected yet
  bool _hasReviewed = false;
  bool _submittingReview = false;
  late double _averageRating;
  late int _reviewCount;
  final TextEditingController _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // Seed hype state from the event snapshot passed in.
    _hasHyped = uid != null && widget.event.hypedBy.contains(uid);
    _hypeCount = widget.event.hypeCount;

    // Seed RSVP count from the event snapshot, then check subcollection async.
    _rsvpCount = widget.event.rsvpCount;

    // Seed rating from event snapshot; actual user review loaded async.
    _averageRating = widget.event.averageRating;
    _reviewCount = widget.event.reviewCount;

    _loadRsvpStatus();
    _loadSavedStatus();
    _loadReviewStatus();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  // Checks whether the current user has an RSVP document in the subcollection.
  // Called once on open — result updates the button state when it comes back.
  Future<void> _loadRsvpStatus() async {
    final uid = _currentUid;
    if (uid == null || widget.event.id == null) return;

    final hasRsvpd =
        await _firestoreService.checkUserRsvp(widget.event.id!, uid);
    if (mounted) setState(() => _hasRsvpd = hasRsvpd);
  }

  // Checks whether the current user has saved this event to favorites.
  Future<void> _loadSavedStatus() async {
    final uid = _currentUid;
    if (uid == null || widget.event.id == null) return;

    final hasSaved =
        await _firestoreService.checkEventSaved(widget.event.id!, uid);
    if (mounted) setState(() => _hasSaved = hasSaved);
  }

  // Loads the current user's existing review (if any) so we can pre-fill
  // the star widget and show their previous comment.
  Future<void> _loadReviewStatus() async {
    final uid = _currentUid;
    if (uid == null || widget.event.id == null) return;

    final review = await _firestoreService.getUserReview(widget.event.id!, uid);
    if (mounted && review != null) {
      setState(() {
        _hasReviewed = true;
        _myRating = (review['rating'] as int?) ?? 0;
        _commentController.text = (review['comment'] as String?) ?? '';
      });
    }
  }

  // Submits (or updates) the user's review via a Firestore transaction.
  // Updates the local averageRating/reviewCount optimistically after success.
  Future<void> _submitReview() async {
    final uid = _currentUid;
    if (uid == null || widget.event.id == null || _myRating == 0) return;

    // Capture messenger before any await so we don't use context across gaps.
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _submittingReview = true);

    try {
      await _firestoreService.submitReview(
        widget.event.id!,
        uid,
        _myRating,
        comment: _commentController.text,
      );

      if (!mounted) return;

      // Reload review to confirm saved rating.
      final review =
          await _firestoreService.getUserReview(widget.event.id!, uid);
      if (!mounted) return;
      setState(() {
        _hasReviewed = true;
        _submittingReview = false;
        if (review != null) _myRating = (review['rating'] as int?) ?? _myRating;
      });

      // Refresh cached average from the event document.
      final updatedEvent = await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.event.id)
          .get();
      if (mounted && updatedEvent.exists) {
        final data = updatedEvent.data()!;
        setState(() {
          _averageRating = (data['averageRating'] ?? 0).toDouble();
          _reviewCount = (data['reviewCount'] ?? 0) as int;
        });
      }

      messenger.showSnackBar(
        const SnackBar(content: Text('Review submitted!')),
      );
    } catch (_) {
      if (mounted) setState(() => _submittingReview = false);
    }
  }

  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  // Pill badge showing the event category with its associated color and icon.
  Widget _categoryBadge(EventCategory category) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: category.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: category.color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(category.icon, size: 14, color: category.color),
          const SizedBox(width: 5),
          Text(
            category.label,
            style: TextStyle(
              color: category.color,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceBadge(bool isFree) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: isFree ? Colors.green.shade600 : Colors.red.shade600,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isFree ? Icons.money_off : Icons.attach_money,
            color: Colors.white,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            isFree ? 'Free Event' : 'Paid Event',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  // ── Save toggle ─────────────────────────────────────────────────────────────

  Future<void> _onSaveTapped() async {
    final uid = _currentUid;
    if (uid == null || widget.event.id == null) return;

    final wasSaved = _hasSaved;
    setState(() => _hasSaved = !wasSaved);

    try {
      if (wasSaved) {
        await _firestoreService.unsaveEvent(uid, widget.event.id!);
      } else {
        await _firestoreService.saveEvent(uid, widget.event);
      }
    } catch (_) {
      if (mounted) setState(() => _hasSaved = wasSaved);
    }
  }

  // ── Share ────────────────────────────────────────────────────────────────────

  // Builds a plain-text summary of the event and opens the native iOS share
  // sheet. The user can then send it via Messages, WhatsApp, email, etc.
  void _onShareTapped() {
    final date = DateFormat('MMM d, yyyy – h:mm a').format(widget.event.createdAt);

    // Build the share text — keep it readable when pasted into any app.
    final text = '''
${widget.event.name}

${widget.event.description.isNotEmpty ? widget.event.description : 'No description.'}

📅 $date
📍 ${widget.event.latitude.toStringAsFixed(5)}, ${widget.event.longitude.toStringAsFixed(5)}

Shared via Campus Vibes''';

    // Share.share() opens the native share sheet with the text pre-filled.
    // The subject is used by apps like Mail as the email subject line.
    Share.share(text.trim(), subject: widget.event.name);
  }

  // ── Hype toggle ─────────────────────────────────────────────────────────────

  Future<void> _onHypeTapped() async {
    final uid = _currentUid;
    if (uid == null) return;

    final wasHyped = _hasHyped;
    setState(() {
      _hasHyped = !wasHyped;
      _hypeCount += wasHyped ? -1 : 1;
    });

    try {
      if (wasHyped) {
        await _firestoreService.unhypeEvent(widget.event.id!, uid);
      } else {
        await _firestoreService.hypeEvent(widget.event.id!, uid);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasHyped = wasHyped;
          _hypeCount += wasHyped ? 1 : -1;
        });
      }
    }
  }

  // ── RSVP toggle ─────────────────────────────────────────────────────────────

  Future<void> _onRsvpTapped() async {
    final uid = _currentUid;
    if (uid == null) return;

    final wasRsvpd = _hasRsvpd;
    // Optimistic update — flip the button immediately.
    setState(() {
      _hasRsvpd = !wasRsvpd;
      _rsvpCount += wasRsvpd ? -1 : 1;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (wasRsvpd) {
        await _firestoreService.unrsvpEvent(widget.event.id!, uid);
      } else {
        // Pass display name + email so the attendee list can show real names.
        await _firestoreService.rsvpEvent(
          widget.event.id!,
          uid,
          displayName: user?.displayName,
          email: user?.email,
        );
      }
    } catch (_) {
      // Roll back on failure.
      if (mounted) {
        setState(() {
          _hasRsvpd = wasRsvpd;
          _rsvpCount += wasRsvpd ? 1 : -1;
        });
      }
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Event Details'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(
              _hasSaved ? Icons.bookmark : Icons.bookmark_border,
            ),
            tooltip: _hasSaved ? 'Remove from favorites' : 'Save to favorites',
            onPressed: _onSaveTapped,
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share event',
            onPressed: _onShareTapped,
          ),
        ],
      ),
      // SingleChildScrollView prevents overflow when the attendee list expands.
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Event name
            Text(
              widget.event.name,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 8),
            _priceBadge(widget.event.isFree),
            const SizedBox(height: 8),
            _categoryBadge(widget.event.category),
            const SizedBox(height: 16),

            // Event photo (if one was attached)
            if (widget.event.imageUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: widget.event.imageUrl!,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => const AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Center(
                        child: CircularProgressIndicator(color: Colors.orange)),
                  ),
                  errorWidget: (context, url, error) => const SizedBox(
                    height: 80,
                    child: Center(
                        child: Icon(Icons.broken_image,
                            color: Colors.grey, size: 40)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Description
            Text(
              widget.event.description.isNotEmpty
                  ? widget.event.description
                  : 'No description available.',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black87,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),

            // Location row
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                Text(
                  '${widget.event.latitude.toStringAsFixed(5)}, ${widget.event.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Created date row
            Row(
              children: [
                const Icon(Icons.calendar_today,
                    color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                Text(
                  DateFormat('MMM d, yyyy – h:mm a')
                      .format(widget.event.createdAt),
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Hype button ────────────────────────────────────────────────
            _AnimatedActionRow(
              isActive: _hasHyped,
              count: _hypeCount,
              activeLabel: 'Hyped!',
              inactiveLabel: 'Hype',
              countSuffix: _hypeCount == 1 ? 'hype' : 'hypes',
              activeIcon: Icons.local_fire_department,
              inactiveIcon: Icons.local_fire_department_outlined,
              activeColor: Colors.orange,
              onTap: _currentUid == null ? null : _onHypeTapped,
            ),
            const SizedBox(height: 12),

            // ── RSVP button ────────────────────────────────────────────────
            _AnimatedActionRow(
              isActive: _hasRsvpd,
              count: _rsvpCount,
              activeLabel: 'Going!',
              inactiveLabel: "I'm Going",
              countSuffix: _rsvpCount == 1 ? 'going' : 'going',
              activeIcon: Icons.check_circle,
              inactiveIcon: Icons.check_circle_outline,
              activeColor: Colors.green,
              onTap: _currentUid == null ? null : _onRsvpTapped,
            ),
            const SizedBox(height: 16),

            // ── Attendee list ──────────────────────────────────────────────
            // ExpansionTile collapses by default and expands when tapped.
            // StreamBuilder keeps the list live — new RSVPs appear instantly.
            if (widget.event.id != null)
              _AttendeeList(
                eventId: widget.event.id!,
                rsvpCount: _rsvpCount,
                firestoreService: _firestoreService,
              ),
            const SizedBox(height: 16),

            // ── Rating section ─────────────────────────────────────────────
            // Gate: only show rating UI after the event date has passed.
            // Uses createdAt as the event date — swap for a dedicated
            // eventDate field if one is added to the Event model later.
            if (widget.event.id != null &&
                widget.event.createdAt.isBefore(DateTime.now())) ...[
              const Divider(),
              const SizedBox(height: 8),

              // Average rating summary (shown whenever there are reviews).
              if (_reviewCount > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 20),
                      const SizedBox(width: 4),
                      Text(
                        _averageRating.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '($_reviewCount ${_reviewCount == 1 ? 'review' : 'reviews'})',
                        style: const TextStyle(
                            fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                ),

              // Submit/edit review form.
              if (_currentUid != null) ...[
                Text(
                  _hasReviewed ? 'Your Review' : 'Rate This Event',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                // 5-star tap row.
                Row(
                  children: List.generate(5, (i) {
                    final star = i + 1;
                    return GestureDetector(
                      onTap: () => setState(() => _myRating = star),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(
                          _myRating >= star
                              ? Icons.star
                              : Icons.star_border,
                          color: Colors.amber,
                          size: 32,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 10),

                // Optional comment field.
                TextField(
                  controller: _commentController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Leave a comment (optional)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 10),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (_myRating == 0 || _submittingReview)
                        ? null
                        : _submitReview,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _submittingReview
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            _hasReviewed
                                ? 'Update Review'
                                : 'Submit Review',
                          ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Review list.
              if (_reviewCount > 0)
                _ReviewList(
                  eventId: widget.event.id!,
                  firestoreService: _firestoreService,
                ),
              const SizedBox(height: 16),
            ],

            // Get Directions button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LiveNavigationScreen(
                        destLat: widget.event.latitude,
                        destLng: widget.event.longitude,
                        eventName: widget.event.name,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.directions_walk),
                label: const Text('Get Directions',
                    style: TextStyle(fontSize: 18)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ─── Reusable animated button row ────────────────────────────────────────────
// Both the Hype and RSVP buttons share the exact same visual pattern:
//   [animated button]   [animated count]
// Pulling it into its own widget avoids duplicating the animation code.

class _AnimatedActionRow extends StatelessWidget {
  final bool isActive;
  final int count;
  final String activeLabel;
  final String inactiveLabel;
  final String countSuffix;
  final IconData activeIcon;
  final IconData inactiveIcon;
  final Color activeColor;
  final VoidCallback? onTap;

  const _AnimatedActionRow({
    required this.isActive,
    required this.count,
    required this.activeLabel,
    required this.inactiveLabel,
    required this.countSuffix,
    required this.activeIcon,
    required this.inactiveIcon,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // TweenAnimationBuilder bounces the button scale on each toggle.
        // ValueKey(isActive) restarts the animation when isActive flips.
        TweenAnimationBuilder<double>(
          key: ValueKey(isActive),
          tween: Tween(begin: 1.25, end: 1.0),
          duration: const Duration(milliseconds: 350),
          curve: Curves.elasticOut,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: ElevatedButton.icon(
            onPressed: onTap,
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                isActive ? activeIcon : inactiveIcon,
                key: ValueKey(isActive),
                color: isActive ? activeColor : null,
              ),
            ),
            label: Text(
              isActive ? activeLabel : inactiveLabel,
              style: const TextStyle(fontSize: 16),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: isActive ? activeColor.withValues(alpha: 0.1) : null,
              foregroundColor: isActive ? activeColor : null,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Count slides up when the number changes.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, animation) => SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.5),
              end: Offset.zero,
            ).animate(animation),
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: Text(
            '$count $countSuffix',
            key: ValueKey(count),
            style: const TextStyle(
              fontSize: 15,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Attendee list ────────────────────────────────────────────────────────────
// Shows a collapsible list of everyone who has RSVP'd.
// Uses a StreamBuilder so new RSVPs appear in real time without refreshing.

class _AttendeeList extends StatelessWidget {
  final String eventId;
  final int rsvpCount;
  final FirestoreService firestoreService;

  const _AttendeeList({
    required this.eventId,
    required this.rsvpCount,
    required this.firestoreService,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      // ExpansionTile is a built-in Flutter widget that shows a header row
      // and expands to reveal its children when the user taps it.
      child: ExpansionTile(
        leading: const Icon(Icons.people, color: Colors.green),
        title: Text(
          rsvpCount == 0
              ? 'No attendees yet'
              : '$rsvpCount ${rsvpCount == 1 ? 'person' : 'people'} going',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        // Don't show the expand arrow if no one has RSVP'd.
        trailing: rsvpCount == 0 ? const SizedBox.shrink() : null,
        children: [
          StreamBuilder<QuerySnapshot>(
            stream: firestoreService.getRsvpsStream(eventId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                      child: CircularProgressIndicator(color: Colors.green)),
                );
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No attendees yet.',
                      style: TextStyle(color: Colors.grey)),
                );
              }

              final rsvps = snapshot.data!.docs;

              return ListView.builder(
                // shrinkWrap + NeverScrollableScrollPhysics lets a ListView
                // live inside a ScrollView without fighting over scroll control.
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: rsvps.length,
                itemBuilder: (context, index) {
                  final data = rsvps[index].data() as Map<String, dynamic>;
                  // Show displayName if available, fall back to email, then 'Anonymous'.
                  final name = (data['displayName'] as String?)?.isNotEmpty == true
                      ? data['displayName'] as String
                      : (data['email'] as String?) ?? 'Anonymous';

                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.green.shade100,
                      child: Text(
                        // First letter of the name as an avatar.
                        name[0].toUpperCase(),
                        style: const TextStyle(
                            fontSize: 12, color: Colors.green),
                      ),
                    ),
                    title: Text(name,
                        style: const TextStyle(fontSize: 14)),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Review list ──────────────────────────────────────────────────────────────
// Collapsible list of all reviews, streamed live from the reviews subcollection.

class _ReviewList extends StatelessWidget {
  final String eventId;
  final FirestoreService firestoreService;

  const _ReviewList({
    required this.eventId,
    required this.firestoreService,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        leading: const Icon(Icons.rate_review, color: Colors.amber),
        title: const Text(
          'Reviews',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        children: [
          StreamBuilder<QuerySnapshot>(
            stream: firestoreService.getReviewsStream(eventId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                      child:
                          CircularProgressIndicator(color: Colors.amber)),
                );
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No reviews yet.',
                      style: TextStyle(color: Colors.grey)),
                );
              }

              final reviews = snapshot.data!.docs;

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: reviews.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 16, endIndent: 16),
                itemBuilder: (context, index) {
                  final data =
                      reviews[index].data() as Map<String, dynamic>;
                  final rating = (data['rating'] as int?) ?? 0;
                  final comment =
                      (data['comment'] as String?)?.trim() ?? '';

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Star display
                        Row(
                          children: List.generate(
                            5,
                            (i) => Icon(
                              i < rating ? Icons.star : Icons.star_border,
                              color: Colors.amber,
                              size: 16,
                            ),
                          ),
                        ),
                        if (comment.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(comment,
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.black87)),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
