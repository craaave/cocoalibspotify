//
//  SPImage.m
//  CocoaLibSpotify
//
//  Created by Daniel Kennett on 2/20/11.
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

#import "SPImage.h"
#import "SPSession.h"
#import "SPURLExtensions.h"

@interface SPImageCallbackProxy : NSObject
// SPImageCallbackProxy is here to bridge the gap between -dealloc and the 
// playlist callbacks being unregistered, since that's done async.
@property (nonatomic, readwrite, assign) __unsafe_unretained SPImage *image;
@end

@implementation SPImageCallbackProxy
@synthesize image;
@end

@interface SPImage ()

-(void) cacheSpotifyURL;

@property (nonatomic, readwrite) const byte *imageId;
@property (nonatomic, readwrite, strong) SPPlatformNativeImage *image;
@property (nonatomic, readwrite) sp_image *spImage;
@property (nonatomic, readwrite, getter=isLoaded) BOOL loaded;
@property (nonatomic, readwrite, assign) __unsafe_unretained SPSession *session;
@property (nonatomic, readwrite, copy) NSURL *spotifyURL;
@property (nonatomic, readwrite, strong) SPImageCallbackProxy *callbackProxy;

@end

static SPPlatformNativeImage *create_native_image(sp_image *image)
{
    size_t size = 0;
    const byte *data = sp_image_data(image, &size);
    
    if (size == 0) {
        return nil;
    }
    
    return [[SPPlatformNativeImage alloc] initWithData:[NSData dataWithBytes:data length:size]];
}

static void image_loaded(sp_image *image, void *userdata) {
	
	SPImageCallbackProxy *proxy = (__bridge SPImageCallbackProxy *)userdata;
	if (!proxy.image) return;
	
	BOOL isLoaded = sp_image_is_loaded(image);

	SPPlatformNativeImage *im = nil;
	if (isLoaded) {
        im = create_native_image(proxy.image.spImage);
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		proxy.image.image = im;
		proxy.image.loaded = isLoaded;
	});
}

@implementation SPImage {
	BOOL _hasStartedLoading;
	SPPlatformNativeImage *_image;
}

static NSCache *imageCache;

+ (void)initialize
{
    if (self == [SPImage class]) {
        imageCache = [[NSCache alloc] init];
    }
}

+ (NSData *)cacheKeyFromImageId:(const byte *)imageId
{
    return [NSData dataWithBytes:imageId length:SPImageIdLength];;
}

+(void)createLinkFromImageId:(const byte *)imageId inSession:(SPSession *)aSession callback:(void (^)(NSURL *url))block;
{
    NSParameterAssert(imageId != nil);
    NSParameterAssert(aSession != nil);
    NSParameterAssert(block != nil);
    
	NSData *cacheKey = [self cacheKeyFromImageId:imageId];
	SPImage *cachedImage = [imageCache objectForKey:cacheKey];
    
    if (cachedImage && cachedImage.spotifyURL) {
        block(cachedImage.spotifyURL);
        return;
    }
    
    SPDispatchAsync(^{
        sp_image *image = sp_image_create(aSession.session, imageId);
        if (image == NULL) {
            dispatch_async(dispatch_get_main_queue(), ^() { block(nil); });
            return;
        }
        
        sp_link *link = sp_link_create_from_image(image);
        sp_image_release(image);
        
        if (link == NULL) {
            dispatch_async(dispatch_get_main_queue(), ^() { block(nil); });
            return;
        }
    
        NSURL *url = [NSURL urlWithSpotifyLink:link];
        sp_link_release(link);
        
        dispatch_async(dispatch_get_main_queue(), ^() { block(url); });
    });
}

+(SPImage *)imageWithImageId:(const byte *)imageId inSession:(SPSession *)aSession {

	SPAssertOnLibSpotifyThread();

    NSParameterAssert(imageId != nil);
    NSParameterAssert(aSession != nil);
	
	NSData *cacheKey = [self cacheKeyFromImageId:imageId];
	SPImage *image = [imageCache objectForKey:cacheKey];
	if (image) {
		return image;
    }

	image = [[SPImage alloc] initWithImageStruct:NULL imageId:imageId inSession:aSession];
	[imageCache setObject:image forKey:cacheKey];
    
	return image;
}

+(void)imageWithImageURL:(NSURL *)imageURL inSession:(SPSession *)aSession callback:(void (^)(SPImage *image))block {
    
	NSParameterAssert(imageURL != nil);
    NSParameterAssert(aSession != nil);
    NSParameterAssert(block != nil);
    
    SPImage *cachedImage = [imageCache objectForKey:imageURL];
    if (cachedImage) {
        block(cachedImage);
        return;
    }
    
	if ([imageURL spotifyLinkType] != SP_LINKTYPE_IMAGE) {
		block(nil);
		return;
	}
	
	SPDispatchAsync(^{
		
		SPImage *spImage = nil;
		sp_link *link = [imageURL createSpotifyLink];
		sp_image *image = sp_image_create_from_link(aSession.session, link);
		
		if (link != NULL) {
			sp_link_release(link);
        }
		
		if (image != NULL) {
			spImage = [self imageWithImageId:sp_image_image_id(image) inSession:aSession];
			sp_image_release(image);
		}
		
        if (spImage) {
            [imageCache setObject:spImage forKey:imageURL];
        }
        
		dispatch_async(dispatch_get_main_queue(), ^() {
            block(spImage);
        });
	});
}

#pragma mark -

-(id)initWithImageStruct:(sp_image *)anImage imageId:(const byte *)anId inSession:aSession {
	
	SPAssertOnLibSpotifyThread();
	
    if ((self = [super init])) {
		
		self.session = aSession;
		self.imageId = anId;
        
		_imageIdData = [[NSData alloc] initWithBytes:anId length:SPImageIdLength];
        
		if (anImage != NULL) {
			self.spImage = anImage;
			sp_image_add_ref(self.spImage);
			
			self.callbackProxy = [[SPImageCallbackProxy alloc] init];
			self.callbackProxy.image = self;
			
			sp_image_add_load_callback(self.spImage,
									   &image_loaded,
									   (__bridge void *)(self.callbackProxy));
			
			BOOL isLoaded = sp_image_is_loaded(self.spImage);

			SPPlatformNativeImage *im = nil;
			if (isLoaded) {
                im = create_native_image(self.spImage);
			}

			dispatch_async(dispatch_get_main_queue(), ^{
				[self cacheSpotifyURL];
				self.image = im;
				self.loaded = isLoaded;
			});
        }
    }
    return self;
}

-(sp_image *)spImage {
#if DEBUG
	SPAssertOnLibSpotifyThread();
#endif 
	return _spImage;
}

@synthesize spImage = _spImage;
@synthesize loaded;
@synthesize session;
@synthesize spotifyURL;
@synthesize imageId;
@synthesize callbackProxy;

#pragma mark -

-(void)startLoading {

	if (_hasStartedLoading) return;
	_hasStartedLoading = YES;
	
	SPDispatchAsync(^{
		
		if (self.spImage != NULL)
			return;
		
		self.spImage = sp_image_create(self.session.session, self.imageId);
		
		if (self.spImage != NULL) {
			[self cacheSpotifyURL];
			
			// Clear out previous proxy.
			self.callbackProxy.image = nil;
			self.callbackProxy = nil;
			
			self.callbackProxy = [[SPImageCallbackProxy alloc] init];
			self.callbackProxy.image = self;
			
			sp_image_add_load_callback(self.spImage, &image_loaded, (__bridge void *)(self.callbackProxy));
			BOOL isLoaded = sp_image_is_loaded(self.spImage);
            
			SPPlatformNativeImage *im = nil;
			if (isLoaded) {
                im = create_native_image(self.spImage);
			}
			
			dispatch_async(dispatch_get_main_queue(), ^{
				self.image = im;
				self.loaded = isLoaded;
			});
		}
	});
	
}

-(void)dealloc {

	sp_image *outgoing_image = _spImage;
	SPImageCallbackProxy *outgoingProxy = self.callbackProxy;
	self.callbackProxy.image = nil;
	self.callbackProxy = nil;
    
    SPDispatchAsync(^() {
		if (outgoing_image) sp_image_remove_load_callback(outgoing_image, &image_loaded, (__bridge void *)outgoingProxy);
		if (outgoing_image) sp_image_release(outgoing_image);
	});
}

-(void)cacheSpotifyURL {
	
	SPDispatchAsync(^{

		if (self.spotifyURL != NULL)
			return;
		
		sp_link *link = sp_link_create_from_image(self.spImage);
		
		if (link != NULL) {
			NSURL *url = [NSURL urlWithSpotifyLink:link];
			sp_link_release(link);
			dispatch_async(dispatch_get_main_queue(), ^{
				self.spotifyURL = url;
			});
		}
	});
}

@end
