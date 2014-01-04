//
//  SPWeakValue.h
//  CocoaLibSpotify iOS Library
//
//  Created by Charles Osmer on 1/4/14.
//
//

#import <Foundation/Foundation.h>

@interface SPWeakValue : NSObject

@property(nonatomic, weak, readonly) id value;

- (instancetype)initWithValue:(id)value;

// Sets the receiver's value to nil.
- (void)clear;

@end
