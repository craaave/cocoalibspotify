//
//  SPPlaylist.m
//  CocoaLibSpotify
//
//  Created by Daniel Kennett on 2/14/11.
/*
Copyright (c) 2011, Spotify AB
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Spotify AB nor the names of its contributors may 
      be used to endorse or promote products derived from this software 
      without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL SPOTIFY AB BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT 
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, 
OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#import "SPPlaylist.h"
#import "SPPlaylistInternal.h"
#import "SPSession.h"
#import "SPTrack.h"
#import "SPTrackInternal.h"
#import "SPImage.h"
#import "SPUser.h"
#import "SPURLExtensions.h"
#import "SPErrorExtensions.h"
#import "SPPlaylistItem.h"
#import "SPPlaylistItemInternal.h"
#import "SPWeakValue.h"

#pragma mark Callbacks

// Called when one or more tracks have been added to a playlist
static void tracks_added(sp_playlist *pl, sp_track *const *tracks, int num_tracks, int position, void *userdata)
{

}

// Called when one or more tracks have been removed from a playlist
static void	tracks_removed(sp_playlist *pl, const int *tracks, int num_tracks, void *userdata)
{

}

// Called when one or more tracks have been moved within a playlist
static void	tracks_moved(sp_playlist *pl, const int *tracks, int num_tracks, int new_position, void *userdata)
{

}

// Called when a playlist has been renamed. sp_playlist_name() can be used to find out the new name
static void	playlist_renamed(sp_playlist *pl, void *userdata)
{

}

/*
 Called when state changed for a playlist.
 
 There are three states that trigger this callback:
 
 Collaboration for this playlist has been turned on or off
 The playlist started having pending changes, or all pending changes have now been committed
 The playlist started loading, or finished loading
 */
static void	playlist_state_changed(sp_playlist *pl, void *userdata)
{

}

// Called when a playlist is updating or is done updating
static void	playlist_update_in_progress(sp_playlist *pl, bool done, void *userdata)
{

}

// Called when metadata for one or more tracks in a playlist has been updated.
static void	playlist_metadata_updated(sp_playlist *pl, void *userdata)
{

}

// Called when create time and/or creator for a playlist entry changes
static void	track_created_changed(sp_playlist *pl, int position, sp_user *user, int when, void *userdata)
{

}

// Called when seen attribute for a playlist entry changes
static void	track_seen_changed(sp_playlist *pl, int position, bool seen, void *userdata)
{

}

// Called when playlist description has changed
static void	description_changed(sp_playlist *pl, const char *desc, void *userdata)
{

}

static void	image_changed(sp_playlist *pl, const byte *image, void *userdata)
{
    
}

// Called when message attribute for a playlist entry changes
static void	track_message_changed(sp_playlist *pl, int position, const char *message, void *userdata)
{

}

// Called when playlist subscribers changes (count or list of names)
static void	subscribers_changed(sp_playlist *pl, void *userdata)
{

}

static sp_playlist_callbacks _playlistCallbacks = {
	&tracks_added,
	&tracks_removed,
	&tracks_moved,
	&playlist_renamed,
	&playlist_state_changed,
	&playlist_update_in_progress,
	&playlist_metadata_updated,
	&track_created_changed,
	&track_seen_changed,
	&description_changed,
    &image_changed,
    &track_message_changed,
    &subscribers_changed
};

#pragma mark - Playlist

@interface SPPlaylist ()

@property(nonatomic, strong) SPWeakValue *callbackValue;

@end

@implementation SPPlaylist

+ (SPPlaylist *)playlistWithPlaylistStruct:(sp_playlist *)playlist inSession:(SPSession *)session
{
	return [session playlistForPlaylistStruct:playlist];
}

+ (void)playlistWithPlaylistURL:(NSURL *)playlistURL inSession:(SPSession *)session callback:(void (^)(SPPlaylist *playlist))callback
{
    NSParameterAssert(playlistURL != nil);
    NSParameterAssert(callback != nil);
    
    void(^mainQueueCallback)(id) = ^(id playlist){
        dispatch_async(dispatch_get_main_queue(), ^{
            callback(playlist);
        });
    };
    
	if ([playlistURL spotifyLinkType] != SP_LINKTYPE_PLAYLIST) {
		mainQueueCallback(nil);
		return;
	}
    
    SPDispatchAsync(^{
        sp_link *link = [playlistURL createSpotifyLink];
        if (!link) {
            mainQueueCallback(nil);
            return;
        }
        
        sp_playlist *playlistStruct = sp_playlist_create(session.session, link);
        sp_link_release(link);

        SPPlaylist *playlist = [session playlistForPlaylistStruct:playlistStruct];
        sp_playlist_release(playlistStruct);

        mainQueueCallback(playlist);
    });
}

- (id)initWithPlaylistStruct:(sp_playlist *)playlistStruct inSession:(SPSession *)session
{
	SPAssertOnLibSpotifyThread();
    
    NSParameterAssert(playlistStruct != NULL);
    NSParameterAssert(session != nil);
	
    if ((self = [super init])) {
        _session = session;
        _playlist = playlistStruct;

        sp_playlist_add_ref(playlistStruct);
        
    }
    return self;
}

- (void)dealloc
{
    sp_playlist *playlist = _playlist;
    SPWeakValue *callbackValue = _callbackValue;

    if (playlist != NULL) {
        SPDispatchAsync(^() {
            if (callbackValue) {
                sp_playlist_remove_callbacks(playlist, &_playlistCallbacks, (__bridge void *)callbackValue);
            }

            sp_playlist_release(playlist);
        });
    }
}

#pragma mark - Properties

- (void)setMarkedForOfflinePlayback:(BOOL)isMarkedForOfflinePlayback
{
	SPDispatchAsync(^{
		sp_playlist_set_offline_mode(self.session.session, self.playlist, isMarkedForOfflinePlayback);
	});
}

- (BOOL)isMarkedForOfflinePlayback
{
	return self.offlineStatus != SP_PLAYLIST_OFFLINE_STATUS_NO;
}

#pragma mark - Loading

- (void)startLoading
{

}

#pragma mark - Item management

- (void)addItem:(SPTrack *)item atIndex:(NSUInteger)index callback:(SPErrorableOperationCallback)block
{
    NSAssert(NO, @"Not implemented");
}

- (void)addItems:(NSArray *)items atIndex:(NSUInteger)index callback:(SPErrorableOperationCallback)block
{
    NSAssert(NO, @"Not implemented");
}

- (void)removeItemAtIndex:(NSUInteger)index callback:(SPErrorableOperationCallback)block
{
    NSAssert(NO, @"Not implemented");
}

- (void)moveItemsAtIndexes:(NSIndexSet *)indexes toIndex:(NSUInteger)newLocation callback:(SPErrorableOperationCallback)block
{
    NSAssert(NO, @"Not implemented");
}

@end

#pragma mark - Internal

@implementation SPPlaylist (SPPlaylistInternal)

- (void)offlineSyncStatusMayHaveChanged
{
	SPAssertOnLibSpotifyThread();
}

@end
