//
//  NSObject+DeepMutableCopy.h
//

#import <Foundation/Foundation.h>


@interface NSString (DeepMutableCopy)
- (id)deepMutableCopy;
@end

@interface NSDate (DeepMutableCopy)
- (id)deepMutableCopy;
@end

@interface NSData (DeepMutableCopy)
- (id)deepMutableCopy;
@end

@interface NSNumber (DeepMutableCopy)
- (id)deepMutableCopy;
@end

@interface NSDictionary (DeepMutableCopy)
- (id)deepMutableCopy;
@end

@interface NSArray (DeepMutableCopy)
- (id)deepMutableCopy;
@end


