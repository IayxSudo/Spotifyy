#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

void IayxifySBInvokeSeekDouble(id target, SEL selector, double argument);

/// Sends a no-argument, void-returning message.
///
/// Used for transport calls such as `pause`, where -performSelector: would
/// hand ARC an undefined return value from a method that returns nothing.
void IayxifyInvokeVoid(id target, SEL selector);

/// Sends a one-object-argument, void-returning message (e.g. addPlayerObserver:).
void IayxifyInvokeObjectVoid(id target, SEL selector, id argument);
NSString *IayxifyJBRootPath(NSString *path);

NS_ASSUME_NONNULL_END
