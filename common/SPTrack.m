//
//  SPTrack.m
//  CocoaLibSpotify
//
//  Created by Daniel Kennett on 2/19/11.
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

#import "SPTrack.h"
#import "SPTrackInternal.h"
#import "SPAlbum.h"
#import "SPArtist.h"
#import "SPSession.h"
#import "SPURLExtensions.h"
#import "SPSessionInternal.h"

@interface SPTrack ()

-(BOOL)checkLoaded;
-(void)loadTrackData;

@property (nonatomic, readwrite, copy) NSURL *spotifyURL;

@property (nonatomic, readwrite) sp_track_availability availability;
@property (nonatomic, readwrite, getter=isLoaded) BOOL loaded;
@property (nonatomic, readwrite) sp_track_offline_status offlineStatus;
@property (nonatomic, readwrite) NSUInteger discNumber;
@property (nonatomic, readwrite) NSTimeInterval duration;
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite) NSUInteger popularity;
@property (nonatomic, readwrite) NSUInteger trackNumber;
@property (nonatomic, readwrite, getter = isLocal) BOOL local;
@property (nonatomic, readwrite) sp_track *track;

@property (nonatomic, readwrite, assign) __unsafe_unretained SPSession *session;
	
@end

@implementation SPTrack (SPTrackInternal)

-(void)setStarredFromLibSpotifyUpdate:(BOOL)starred {
	[self willChangeValueForKey:@"starred"];
	_starred = starred;
	[self didChangeValueForKey:@"starred"];
}

-(void)setOfflineStatusFromLibSpotifyUpdate:(sp_track_offline_status)status {
	self.offlineStatus = status;
}

-(void)updateAlbumBrowseSpecificMembers {
	
	SPAssertOnLibSpotifyThread();
	
	self.discNumber = sp_track_disc(self.track);
	self.trackNumber = sp_track_index(self.track);
}

@end

@implementation SPTrack

+ (SPTrack *)trackForTrackStruct:(sp_track *)spTrack inSession:(SPSession *)aSession
{
    return [[SPTrack alloc] initWithTrackStruct:spTrack inSession:aSession];
}

+ (void)trackForTrackURL:(NSURL *)trackURL inSession:(SPSession *)aSession callback:(void (^)(SPTrack *track))block
{
    NSParameterAssert(trackURL != nil);
    NSParameterAssert(block != nil);
    
	sp_linktype linkType = [trackURL spotifyLinkType];
	if (linkType != SP_LINKTYPE_TRACK && linkType != SP_LINKTYPE_LOCALTRACK) {
		block(nil);
		return;
	}
	
	SPDispatchAsync(^{
		SPTrack *trackObj = nil;
		sp_link *link = [trackURL createSpotifyLink];
		if (link != NULL) {
			sp_track *track = sp_link_as_track(link);
			sp_track_add_ref(track);
			trackObj = [SPTrack trackForTrackStruct:track inSession:aSession];
			sp_track_release(track);
			sp_link_release(link);
		}

		dispatch_async(dispatch_get_main_queue(), ^() {
            block(trackObj);
        });
	});
}

-(id)initWithTrackStruct:(sp_track *)tr inSession:(SPSession *)aSession {
	
	SPAssertOnLibSpotifyThread();

    if ((self = [super init])) {
        self.session = aSession;
        self.track = tr;
        sp_track_add_ref(self.track);
        
        if (!sp_track_is_loaded(self.track)) {
            [aSession addLoadingObject:self];
        } else {
            [self loadTrackData];
        }
    }   
    return self;
}

-(NSString *)description {
    return [NSString stringWithFormat:@"%@: %@", [super description], [self name]];
}
         
-(BOOL)checkLoaded {
	
	SPAssertOnLibSpotifyThread();
	
	BOOL isLoaded = sp_track_is_loaded(self.track);
	
    if (isLoaded)
        [self loadTrackData];

	return isLoaded;
}

-(void)loadTrackData {
	
	SPAssertOnLibSpotifyThread();
	
	NSURL *trackURL = nil;
	SPAlbum *newAlbum = nil;
	NSString *newName = nil;
	BOOL newLocal = sp_track_is_local(self.session.session, self.track);
	NSUInteger newTrackNumber = sp_track_index(self.track);
	NSUInteger newDiscNumber = sp_track_disc(self.track);
	NSUInteger newPopularity = sp_track_popularity(self.track);
	NSTimeInterval newDuration = (NSTimeInterval)sp_track_duration(self.track) / 1000.0;
	sp_track_availability newAvailability = sp_track_get_availability(self.session.session, self.track);
	sp_track_offline_status newOfflineStatus = sp_track_offline_get_status(self.track);
	BOOL newLoaded = sp_track_is_loaded(self.track);
	BOOL newStarred = sp_track_is_starred(self.session.session, self.track);
	
	sp_link *link = sp_link_create_from_track(self.track, 0);
	if (link != NULL) {
		trackURL = [NSURL urlWithSpotifyLink:link];
		sp_link_release(link);
	}
	
	sp_album *spAlbum = sp_track_album(self.track);
	if (spAlbum != NULL)
		newAlbum = [SPAlbum albumWithAlbumStruct:spAlbum inSession:self.session];
	
	const char *nameCharArray = sp_track_name(self.track);
	if (nameCharArray != NULL) {
		NSString *nameString = [NSString stringWithUTF8String:nameCharArray];
		newName = [nameString length] > 0 ? nameString : nil;
	} else {
		newName = nil;
	}
	
	dispatch_async(dispatch_get_main_queue(), ^{
		self.spotifyURL = trackURL;
		self.name = newName;
		self.local = newLocal;
		self.trackNumber = newTrackNumber;
		self.discNumber = newDiscNumber;
		self.popularity = newPopularity;
		self.duration = newDuration;
		self.availability = newAvailability;
		self.offlineStatus = newOfflineStatus;
		[self setStarredFromLibSpotifyUpdate:newStarred];
		self.loaded = newLoaded;
	});
}

-(void)albumBrowseDidLoad {
	if (self.track) self.discNumber = sp_track_disc(self.track);
}

-(SPTrack *)playableTrack {
	
	if (!self.track) return nil;

	sp_track *linked = sp_track_get_playable(self.session.session, self.track);
	if (!linked) return nil;
	
	return [SPTrack trackForTrackStruct:linked inSession:self.session];
	
}

#pragma mark -
#pragma mark Properties 

@synthesize trackNumber;
@synthesize discNumber;
@synthesize popularity;
@synthesize duration;
@synthesize availability;
@synthesize offlineStatus;
@synthesize loaded;
@synthesize name;
@synthesize session;
@synthesize starred = _starred;
@synthesize local;
@synthesize spotifyURL;
@synthesize track = _track;

-(sp_track *)track {
#if DEBUG
	SPAssertOnLibSpotifyThread();
#endif 
	return _track;
}

- (void)firstArtistCompletion:(void(^)(SPArtist *))completion
{
    NSParameterAssert(completion != nil);
    
    void(^mainQueueCompletion)(id) = ^(id result){
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(result);
        });
    };

    SPDispatchAsync(^{
        sp_track *track = self.track;
        if (!track) {
            mainQueueCompletion(nil);
            return;
        }
        
        int artistCount = sp_track_num_artists(track);
        if (artistCount == 0) {
            mainQueueCompletion(nil);
            return;
        }
        
        sp_artist *artist = sp_track_artist(track, 0);
        if (!artist) {
            mainQueueCompletion(nil);
            return;
        }
        
        SPArtist *spArtist = [SPArtist artistWithArtistStruct:artist inSession:self.session];
        mainQueueCompletion(spArtist);
    });
}

- (void)albumCompletion:(void(^)(SPAlbum *))completion
{
    NSParameterAssert(completion != nil);
    
    void(^mainQueueCompletion)(id) = ^(id result){
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(result);
        });
    };
    
    SPDispatchAsync(^{
        sp_track *track = self.track;
        if (!track) {
            mainQueueCompletion(nil);
            return;
        }
        
        sp_album *album = sp_track_album(track);
        if (!album) {
            mainQueueCompletion(nil);
            return;
        }
        
        SPAlbum *spAlbum = [SPAlbum albumWithAlbumStruct:album inSession:self.session];
        mainQueueCompletion(spAlbum);
    });
}

-(void)setStarred:(BOOL)starred {
    SPDispatchAsync(^() {
		sp_track *track = self.track;
		sp_track_set_starred([session session], (sp_track *const *)&track, 1, starred);
	});
	_starred = starred;
}

-(void)dealloc {
	sp_track *outgoing_track = _track;
	_track = NULL;
    SPDispatchAsync(^() { if (outgoing_track) sp_track_release(outgoing_track); });
    session = nil;
}

@end
