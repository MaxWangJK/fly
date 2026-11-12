import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A decode error clears VideoPlayerValue.isInitialized. Controller.pause then
/// becomes a no-op, although the backend may still be active. Stop that backend
/// by its platform ID before asynchronous texture destruction, on every target.
class VideoCleanupPlatform extends VideoPlayerPlatform {
  VideoCleanupPlatform(this.delegate);
  final VideoPlayerPlatform delegate;

  @override
  Future<void> init() => delegate.init();
  @override
  Future<void> dispose(int playerId) async {
    try {
      await delegate.pause(playerId);
    } catch (_) {
      // A failed/missing player must still reach native disposal.
    }
    await delegate.dispose(playerId);
  }

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) =>
      delegate.createWithOptions(options);
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) =>
      delegate.videoEventsFor(playerId);
  @override
  Future<void> setLooping(int playerId, bool looping) =>
      delegate.setLooping(playerId, looping);
  @override
  Future<void> play(int playerId) => delegate.play(playerId);
  @override
  Future<void> pause(int playerId) => delegate.pause(playerId);
  @override
  Future<void> setVolume(int playerId, double volume) =>
      delegate.setVolume(playerId, volume);
  @override
  Future<void> seekTo(int playerId, Duration position) =>
      delegate.seekTo(playerId, position);
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) =>
      delegate.setPlaybackSpeed(playerId, speed);
  @override
  Future<Duration> getPosition(int playerId) => delegate.getPosition(playerId);
  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      delegate.buildViewWithOptions(options);
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) =>
      delegate.setMixWithOthers(mixWithOthers);
  @override
  Future<void> setAllowBackgroundPlayback(bool allowBackgroundPlayback) =>
      delegate.setAllowBackgroundPlayback(allowBackgroundPlayback);
  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(
    int playerId,
    bool preventsDisplaySleepDuringVideoPlayback,
  ) => delegate.setPreventsDisplaySleepDuringVideoPlayback(
    playerId,
    preventsDisplaySleepDuringVideoPlayback,
  );
  @override
  Future<void> setWebOptions(int playerId, VideoPlayerWebOptions options) =>
      delegate.setWebOptions(playerId, options);
  @override
  Future<List<VideoAudioTrack>> getAudioTracks(int playerId) =>
      delegate.getAudioTracks(playerId);
  @override
  Future<void> selectAudioTrack(int playerId, String trackId) =>
      delegate.selectAudioTrack(playerId, trackId);
  @override
  bool isAudioTrackSupportAvailable() =>
      delegate.isAudioTrackSupportAvailable();
  @override
  Future<List<VideoTrack>> getVideoTracks(int playerId) =>
      delegate.getVideoTracks(playerId);
  @override
  Future<void> selectVideoTrack(int playerId, VideoTrack? track) =>
      delegate.selectVideoTrack(playerId, track);
  @override
  bool isVideoTrackSupportAvailable() =>
      delegate.isVideoTrackSupportAvailable();
}
