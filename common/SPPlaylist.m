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

@interface SPPlaylist ()

/// \note This should only be accessed on the Spotify thread.
@property(nonatomic, strong) SPWeakValue *callbackValue;

@property(nonatomic, copy) NSURL *spotifyURL;
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSString *description;
@property(nonatomic, copy) NSArray *items;
@property(nonatomic, strong) SPImage *image;
@property(nonatomic) BOOL loaded;
@property(nonatomic) BOOL hasPendingChanges;
@property(nonatomic) BOOL collaborative;

@property(nonatomic) float offlineDownloadProgress;
@property(nonatomic) sp_playlist_offline_status offlineStatus;

- (void)loadPlaylist;

@end

#pragma mark Callbacks

static void tracks_added(sp_playlist *pl, sp_track *const *tracks, int num_tracks, int position, void *userdata)
{

}

static void	tracks_removed(sp_playlist *pl, const int *tracks, int num_tracks, void *userdata)
{

}

static void	tracks_moved(sp_playlist *pl, const int *tracks, int num_tracks, int new_position, void *userdata)
{

}

static void	playlist_renamed(sp_playlist *pl, void *userdata)
{
    SPPlaylist *playlist = ((__bridge SPWeakValue *)userdata).value;
    if (!playlist) {
        return;
    }

    NSString *name = [NSString stringWithUTF8String:sp_playlist_name(pl)];
    dispatch_async(dispatch_get_main_queue(), ^{
        playlist.name = name;
    });
}

static void	playlist_state_changed(sp_playlist *pl, void *userdata)
{
    SPPlaylist *playlist = ((__bridge SPWeakValue *)userdata).value;
    if (!playlist) {
        return;
    }

    BOOL isLoaded = sp_playlist_is_loaded(pl);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (isLoaded && !playlist.isLoaded) {
            SPDispatchAsync(^{
                [playlist loadPlaylist];
            });
        }
    });
    
    [playlist offlineSyncStatusMayHaveChanged];
}

static void	playlist_update_in_progress(sp_playlist *pl, bool done, void *userdata)
{

}

static void	playlist_metadata_updated(sp_playlist *pl, void *userdata)
{
    SPPlaylist *playlist = ((__bridge SPWeakValue *)userdata).value;
    if (!playlist) {
        return;
    }
    
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{
            for (SPPlaylistItem *item in playlist.items) {
                if (item.itemClass == [SPTrack class]) {
                    SPTrack *track = item.item;
                    SPDispatchAsync(^{
                        sp_track_offline_status status = sp_track_offline_get_status(track.track);
                        dispatch_async(dispatch_get_main_queue(), ^() {
                            [track setOfflineStatusFromLibSpotifyUpdate:status];
                        });
                    });
                }
            }
        });
    }
}

static void	track_created_changed(sp_playlist *pl, int position, sp_user *user, int when, void *userdata)
{

}

static void	track_seen_changed(sp_playlist *pl, int position, bool seen, void *userdata)
{

}

static void	description_changed(sp_playlist *pl, const char *descriptionBuffer, void *userdata)
{
    SPPlaylist *playlist = ((__bridge SPWeakValue *)userdata).value;
    if (!playlist) {
        return;
    }
    
    NSString *description = [NSString stringWithUTF8String:descriptionBuffer];
    dispatch_async(dispatch_get_main_queue(), ^{
        playlist.description = description;
    });
}

static void	image_changed(sp_playlist *pl, const byte *imageId, void *userdata)
{
    SPPlaylist *playlist = ((__bridge SPWeakValue *)userdata).value;
    if (!playlist) {
        return;
    }
    
    SPImage *image = [SPImage imageWithImageId:imageId inSession:playlist.session];
    dispatch_async(dispatch_get_main_queue(), ^{
        playlist.image = image;
    });
}

static void	track_message_changed(sp_playlist *pl, int position, const char *message, void *userdata)
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
    NULL
};

@implementation SPPlaylist

#pragma mark - KVO

+ (NSSet *)keyPathsForValuesAffectingMarkedForOfflinePlayback
{
    return [NSSet setWithObject:@"offlineStatus"];
}

#pragma mark - Lifecycle

+ (SPPlaylist *)playlistWithPlaylistStruct:(sp_playlist *)playlist inSession:(SPSession *)session
{
	return [[SPPlaylist alloc] initWithPlaylistStruct:playlist inSession:session];
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

        SPPlaylist *playlist = [[SPPlaylist alloc] initWithPlaylistStruct:playlistStruct inSession:session];
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

- (SPUser *)owner
{
    NSAssert(NO, @"Not implemented");
    return nil;
}

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
    SPDispatchAsync(^() {
        if (self.callbackValue) {
            return;
        }

        self.callbackValue = [[SPWeakValue alloc] initWithValue:self];
        sp_playlist_add_callbacks(self.playlist, &_playlistCallbacks, (__bridge void *)self.callbackValue);
        
        // TODO: The playlist should probably be removed from RAM at some point.
        sp_playlist_set_in_ram(self.session.session, self.playlist, true);
        
        if (sp_playlist_is_loaded(self.playlist)) {
            [self loadPlaylist];
        }
    });
}

- (void)loadPlaylist
{
    SPAssertOnLibSpotifyThread();
    
    NSAssert(self.playlist != nil, @"Can't load nil playlist");
    NSAssert(sp_playlist_is_loaded(self.playlist), @"Playlist isn't loaded");

    SPSession *session = self.session;
    sp_playlist *playlist = self.playlist;
    
    NSURL *spotifyURL = nil;
    sp_link *link = sp_link_create_from_playlist(playlist);
    if (link) {
        spotifyURL = [NSURL urlWithSpotifyLink:link];
        sp_link_release(link);
    }
    
    NSString *name = nil;
    const char *nameBuffer = sp_playlist_name(playlist);
    if (nameBuffer) {
        name = [NSString stringWithUTF8String:nameBuffer];
    }
    
    NSString *description = nil;
    const char *descriptionBuffer = sp_playlist_get_description(playlist);
    if (description) {
        description = [NSString stringWithUTF8String:descriptionBuffer];
    }
    
    SPImage *image = nil;
    byte imageId[SPImageIdLength];
    if (sp_playlist_get_image(self.playlist, imageId)) {
        image = [SPImage imageWithImageId:imageId inSession:session];
    }

    BOOL newCollaborative = sp_playlist_is_collaborative(playlist);
    BOOL newHasPendingChanges = sp_playlist_has_pending_changes(playlist);
    
    sp_playlist_offline_status offlineStatus = sp_playlist_get_offline_status(session.session, playlist);
    float downloadProgress = sp_playlist_get_offline_download_completed(session.session, playlist) / 100.0;
    
    NSArray *items = [self createItems];
    
    dispatch_async(dispatch_get_main_queue(), ^() {
        self.spotifyURL = spotifyURL;
        self.name = name;
        self.description = description;
        self.image = image;
        self.hasPendingChanges = newHasPendingChanges;
        self.collaborative = newCollaborative;
        self.items = items;
        self.offlineStatus = offlineStatus;
        self.offlineDownloadProgress = downloadProgress;
        self.loaded = YES;
    });
}

- (NSArray *)createItems
{
    SPAssertOnLibSpotifyThread();

    int count = sp_playlist_num_tracks(self.playlist);
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:count];

    for (int i = 0; i < count; i++) {
        sp_track *track = sp_playlist_track(self.playlist, i);
        NSAssert(track != NULL, @"Failed to create playlist item");
        
        SPPlaylistItem *item = [[SPPlaylistItem alloc] initWithPlaceholderTrack:track atIndex:i inPlaylist:self];
        [items addObject:item];
    }
    
    return items;
}

#pragma mark - Item management

- (void)addItem:(SPTrack *)item atIndex:(NSUInteger)index callback:(SPErrorableOperationCallback)callback
{
    [self addItems:@[item] atIndex:index callback:callback];
}

- (void)addItems:(NSArray *)items atIndex:(NSUInteger)index callback:(SPErrorableOperationCallback)callback
{
    NSParameterAssert(items != nil);
    NSParameterAssert(callback != nil);
    
	SPDispatchAsync(^{
        sp_track **tracks = malloc(sizeof(sp_track *)*items.count);
        
        NSUInteger count = 0;
        for (SPTrack *track in items.reverseObjectEnumerator) {
            tracks[count++] = track.track;
        }
        
        sp_error errorCode = sp_playlist_add_tracks(self.playlist, tracks, count, (int)index, self.session.session);
        
        free(tracks);
		
		NSError *error = nil;
		if (errorCode != SP_ERROR_OK) {
			error = [NSError spotifyErrorWithCode:errorCode];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            callback(error);
        });
	});
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
    
    sp_playlist_offline_status status = sp_playlist_get_offline_status(self.session.session, self.playlist);
    float progress = sp_playlist_get_offline_download_completed(self.session.session, self.playlist) / 100.0;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.offlineStatus = status;
        self.offlineDownloadProgress = progress;
    });
}

@end
