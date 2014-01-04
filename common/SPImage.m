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
#import "SPWeakValue.h"

static NSCache *g_imageCache;

@interface SPImage ()

@property (nonatomic, strong) SPPlatformNativeImage *image;
@property (nonatomic, strong) SPWeakValue *callbackValue;

@property (nonatomic) sp_image *spImage;
@property (nonatomic, getter = isLoaded) BOOL loaded;

- (void)releaseResources;

@end

#pragma mark - LibSpotify

static SPPlatformNativeImage *create_native_image(sp_image *image)
{
    NSCParameterAssert(image != NULL);
    SPCAssertOnLibSpotifyThread();
    
    size_t size = 0;
    const byte *data = sp_image_data(image, &size);
    
    if (size == 0) {
        return nil;
    }
    
    return [[SPPlatformNativeImage alloc] initWithData:[NSData dataWithBytes:data length:size]];
}

static void image_loaded(sp_image *image, void *userdata)
{
    NSCParameterAssert(image != NULL);

	SPWeakValue *weakValue = (__bridge SPWeakValue *)userdata;
    SPImage *imageValue = weakValue.value;
	if (!imageValue) {
        return;
    }

	BOOL isLoaded = sp_image_is_loaded(image);

	SPPlatformNativeImage *nativeImage = nil;
	if (isLoaded) {
        nativeImage = create_native_image(image);
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		imageValue.image = nativeImage;
		imageValue.loaded = isLoaded;

        [imageValue releaseResources];
	});
}

/// This is a hack. There is no supported method to go directly from an
/// image id to a spotify url. However, the unique portion of the url
/// appears to be the image id encoded as a hex string.
static NSURL *create_url_from_image_id(const byte *image_id)
{
    NSCParameterAssert(image_id != NULL);
    
    static const char hexchars[] = "0123456789abcdef";
    
    char *hexstring = calloc(2*SPImageIdLength + 1, 1);
    for (NSUInteger i = 0, j = 0; i < SPImageIdLength; i++) {
        const byte b = image_id[i];
        hexstring[j++] = hexchars[b >> 4];
        hexstring[j++] = hexchars[b & 0xF];
    }

    NSString *urlstring = [NSString stringWithUTF8String:hexstring];
    urlstring = [@"spotify:image:" stringByAppendingString:urlstring];

    free(hexstring);
    
    return [[NSURL alloc] initWithString:urlstring];
}

#pragma mark - SPImage

@implementation SPImage {
	BOOL _hasStartedLoading;
}

+ (void)initialize
{
    if (self == [SPImage class]) {
        g_imageCache = [[NSCache alloc] init];
    }
}

+ (SPImage *)imageWithImageId:(const byte *)imageId inSession:(SPSession *)session
{
    NSParameterAssert(imageId != nil);
    
    NSURL *url = create_url_from_image_id(imageId);
	return [self imageWithImageURL:url inSession:session];
}

+ (void)imageWithImageURL:(NSURL *)imageURL inSession:(SPSession *)session callback:(void (^)(SPImage *image))block
{
    NSParameterAssert(block != nil);
    
    SPImage *image = [self imageWithImageURL:imageURL inSession:session];
    dispatch_async(dispatch_get_main_queue(), ^() {
        block(image);
    });
}

+ (SPImage *)imageWithImageURL:(NSURL *)imageURL inSession:(SPSession *)session
{
    NSParameterAssert(imageURL != nil);
    NSParameterAssert(session != nil);

    if ([imageURL spotifyLinkType] != SP_LINKTYPE_IMAGE) {
		return nil;
	}
    
    SPImage *image = [g_imageCache objectForKey:imageURL];
    if (image) {
        return image;
    }
    
    image = [[SPImage alloc] initWithImageURL:imageURL inSession:session];
    [g_imageCache setObject:image forKey:imageURL];
    
    return image;
}

#pragma mark -

- (id)initWithImageURL:(NSURL *)url inSession:(SPSession *)session
{
    if ((self = [super init])) {
        _session = session;
        _spotifyURL = url;
    }

    return self;
}

- (void)startLoading
{
    SPAssertOnMainThread();

	if (_hasStartedLoading) {
        return;
    }

	_hasStartedLoading = YES;
    
    NSAssert(!self.spImage, @"Image struct already created");
    NSAssert(!self.callbackValue, @"Image callback value already created");
    
    NSURL *spotifyURL = self.spotifyURL;
    SPSession *session = self.session;

	SPDispatchAsync(^{
        sp_link *link = [spotifyURL createSpotifyLink];
        if (link == NULL) {
            return;
        }

		sp_image *spImage = sp_image_create_from_link(session.session, link);
        sp_link_release(link);
        
        if (spImage == NULL) {
            return;
        }

        BOOL isLoaded = sp_image_is_loaded(spImage);

        SPPlatformNativeImage *nativeImage = nil;
        if (isLoaded) {
            nativeImage = create_native_image(spImage);
            sp_image_release(spImage);

            dispatch_async(dispatch_get_main_queue(), ^{
                self.image = nativeImage;
                self.loaded = isLoaded;
            });
        }
        else {
            SPWeakValue *callbackValue = [[SPWeakValue alloc] initWithValue:self];
            sp_image_add_load_callback(spImage, &image_loaded, (__bridge void *)(callbackValue));

            dispatch_async(dispatch_get_main_queue(), ^{
                self.image = nativeImage;
                self.loaded = isLoaded;
                
                self.spImage = spImage;
                self.callbackValue = callbackValue;
            });
        }
	});
}

- (void)releaseResources
{
    sp_image *image = self.spImage;
    SPWeakValue *callbackValue = self.callbackValue;

    [callbackValue clear];

    self.spImage = nil;
    self.callbackValue = nil;

    if (image) {
        SPDispatchAsync(^() {
            sp_image_remove_load_callback(image, &image_loaded, (__bridge void *)callbackValue);
            sp_image_release(image);
        });
    }
}

- (void)dealloc
{
    [self releaseResources];
}

@end
