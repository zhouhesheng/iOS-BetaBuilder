//
//  NSObject+DeepMutableCopy.m
//

#import "NSObject+DeepMutableCopy.h"


@implementation NSString (DeepMutableCopy)

- (id)deepMutableCopy
{
    return [self mutableCopy];
}

@end

@implementation NSDate (DeepMutableCopy)

- (id)deepMutableCopy
{
    return [self copy];
}

@end

@implementation NSData (DeepMutableCopy)

- (id)deepMutableCopy
{
    return [self mutableCopy];
}

@end

@implementation NSNumber (DeepMutableCopy)

- (id)deepMutableCopy
{
    return [self copy];
}

@end

@implementation NSDictionary (DeepMutableCopy)

- (id)deepMutableCopy
{
    NSMutableDictionary* rv = [[NSMutableDictionary alloc] initWithCapacity:[self count]];
    NSArray* keys = [self allKeys];
    
    for (id k in keys)
    {
        [rv setObject:[[self valueForKey:k] deepMutableCopy]
               forKey:k];
    }
    
    return rv;
}

@end

@implementation NSArray (DeepMutableCopy)

- (id)deepMutableCopy
{
    NSUInteger n = [self count];
    NSMutableArray* rv = [[NSMutableArray alloc] initWithCapacity:n];
    
    for (int i = 0; i < n; i++)
    {
        [rv insertObject:[[self objectAtIndex:i] deepMutableCopy]
                 atIndex:i];
    }
    
    return rv;
}

@end

