//
//  SPWeakValue.m
//  CocoaLibSpotify iOS Library
//
//  Created by Charles Osmer on 1/4/14.
//
//

#import "SPWeakValue.h"

@interface SPWeakValue ()

@property(nonatomic, weak) id value;

@end

@implementation SPWeakValue

- (instancetype)initWithValue:(id)value
{
    if ((self = [super init])) {
        _value = value;
    }
    return self;
}

- (void)clear
{
    self.value = nil;
}

@end
